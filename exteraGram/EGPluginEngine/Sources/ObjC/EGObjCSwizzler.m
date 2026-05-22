// MARK: exteraGram — ObjC runtime swizzling utilities

#import "EGObjCSwizzler.h"
#import <objc/message.h>

// ---------------------------------------------------------------------------
// Forward-invocation hook registry
// ---------------------------------------------------------------------------
//
// Per-class table of installed invokers: Class -> NSDictionary(SELName -> Block).
// The Class is keyed by pointer (NSMapTable opaque personality) and not retained
// — classes live forever anyway.
//
// `g_originalForward` saves the pre-swizzle forwardInvocation: IMP per class so
// trampolined classes can chain to the original when the runtime delivers a
// selector that wasn't trampolined.
//
// All registry mutations are guarded by `g_hookLock`. The forwardInvocation: trampoline
// reads under the lock but releases it before calling the (potentially slow) invoker
// block — invokers run unlocked.

static NSMapTable<Class, NSMutableDictionary<NSString *, EGForwardInvocationBlock> *> *g_hooksByClass = nil;
static NSMapTable<Class, NSValue *> *g_originalForward = nil;
static NSLock *g_hookLock = nil;
static dispatch_once_t g_hookOnce = 0;

static void eg_hooks_init_once(void) {
    dispatch_once(&g_hookOnce, ^{
        g_hooksByClass = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaquePersonality | NSPointerFunctionsOpaqueMemory
                                               valueOptions:NSPointerFunctionsStrongMemory];
        g_originalForward = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsOpaquePersonality | NSPointerFunctionsOpaqueMemory
                                                  valueOptions:NSPointerFunctionsStrongMemory];
        g_hookLock = [[NSLock alloc] init];
    });
}

static SEL eg_aliasSEL(SEL original) {
    NSString *name = [@"__eg_alias_" stringByAppendingString:NSStringFromSelector(original)];
    return NSSelectorFromString(name);
}

// Walk the class hierarchy starting at `cls` looking for an invoker registered for `selName`.
// Caller must hold g_hookLock.
static EGForwardInvocationBlock eg_lookupInvoker_locked(Class cls, NSString *selName) {
    Class probe = cls;
    while (probe) {
        NSMutableDictionary *perClass = [g_hooksByClass objectForKey:probe];
        EGForwardInvocationBlock b = perClass[selName];
        if (b) return b;
        probe = class_getSuperclass(probe);
    }
    return nil;
}

// Walk the class hierarchy looking for a saved original forwardInvocation: IMP.
// Caller must hold g_hookLock.
static IMP eg_lookupOriginalForward_locked(Class cls) {
    Class probe = cls;
    while (probe) {
        NSValue *v = [g_originalForward objectForKey:probe];
        if (v) return (IMP)v.pointerValue;
        probe = class_getSuperclass(probe);
    }
    return NULL;
}

// Our forwardInvocation: replacement.
static void eg_forwardInvocation_imp(id self, SEL _cmd, NSInvocation *invocation) {
    SEL original = invocation.selector;
    NSString *selName = NSStringFromSelector(original);
    Class cls = object_getClass(self);

    [g_hookLock lock];
    EGForwardInvocationBlock invoker = eg_lookupInvoker_locked(cls, selName);
    IMP origForward = invoker ? NULL : eg_lookupOriginalForward_locked(cls);
    [g_hookLock unlock];

    if (invoker) {
        invoker(invocation, eg_aliasSEL(original));
        return;
    }

    if (origForward) {
        ((void (*)(id, SEL, NSInvocation *))origForward)(self, _cmd, invocation);
        return;
    }

    // Fallback to NSObject's default which raises NSInvalidArgumentException.
    IMP nsImp = class_getMethodImplementation([NSObject class], @selector(forwardInvocation:));
    ((void (*)(id, SEL, NSInvocation *))nsImp)(self, _cmd, invocation);
}

@implementation EGObjCSwizzler

+ (BOOL)swizzleClass:(Class)cls originalSelector:(SEL)original swizzledSelector:(SEL)swizzled {
    Method originalMethod = class_getInstanceMethod(cls, original);
    Method swizzledMethod = class_getInstanceMethod(cls, swizzled);
    if (!originalMethod || !swizzledMethod) return NO;

    BOOL added = class_addMethod(
        cls, original,
        method_getImplementation(swizzledMethod),
        method_getTypeEncoding(swizzledMethod)
    );
    if (added) {
        class_replaceMethod(
            cls, swizzled,
            method_getImplementation(originalMethod),
            method_getTypeEncoding(originalMethod)
        );
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
    return YES;
}

+ (BOOL)swizzleClassMethod:(Class)cls originalSelector:(SEL)original swizzledSelector:(SEL)swizzled {
    return [self swizzleClass:object_getClass(cls)
             originalSelector:original
             swizzledSelector:swizzled];
}

+ (SEL)aliasSelectorForOriginal:(SEL)sel {
    return eg_aliasSEL(sel);
}

+ (BOOL)installForwardHookOnClass:(Class)cls
                         selector:(SEL)sel
                          invoker:(EGForwardInvocationBlock)invoker {
    if (!cls || !sel || !invoker) return NO;
    eg_hooks_init_once();

    Method originalMethod = class_getInstanceMethod(cls, sel);
    if (!originalMethod) return NO;

    const char *typeEncoding = method_getTypeEncoding(originalMethod);
    SEL aliasSel = eg_aliasSEL(sel);

    [g_hookLock lock];

    // 1. Install alias holding the original IMP on `cls` itself (idempotent).
    //    class_getInstanceMethod walks up the hierarchy — check explicitly
    //    whether `cls` itself defines the alias to avoid re-pointing it.
    Method aliasOnSelf = NULL;
    unsigned int count = 0;
    Method *list = class_copyMethodList(cls, &count);
    for (unsigned int i = 0; i < count; i++) {
        if (method_getName(list[i]) == aliasSel) { aliasOnSelf = list[i]; break; }
    }
    free(list);

    if (!aliasOnSelf) {
        IMP originalIMP = method_getImplementation(originalMethod);
        // class_addMethod returns NO if the class already has a method with this
        // name; the check above ruled that out, but stay defensive.
        if (!class_addMethod(cls, aliasSel, originalIMP, typeEncoding)) {
            [g_hookLock unlock];
            return NO;
        }
        // Repoint the original selector at _objc_msgForward so calls go through
        // forwardInvocation:. Type encoding is preserved so methodSignatureForSelector:
        // still returns the correct signature.
        class_replaceMethod(cls, sel, _objc_msgForward, typeEncoding);
    }

    // 2. Swizzle forwardInvocation: on `cls` (once per class).
    if (![g_originalForward objectForKey:cls]) {
        SEL fwdSel = @selector(forwardInvocation:);
        Method fwdMethod = class_getInstanceMethod(cls, fwdSel);
        const char *fwdEnc = method_getTypeEncoding(fwdMethod);
        IMP origFwdIMP = NULL;

        // Try to add — succeeds if `cls` doesn't override forwardInvocation: itself.
        BOOL added = class_addMethod(cls, fwdSel, (IMP)eg_forwardInvocation_imp, fwdEnc);
        if (added) {
            origFwdIMP = method_getImplementation(fwdMethod); // inherited IMP
        } else {
            // Class already overrides forwardInvocation: — replace and save original.
            Method ownFwd = class_getInstanceMethod(cls, fwdSel);
            origFwdIMP = method_setImplementation(ownFwd, (IMP)eg_forwardInvocation_imp);
        }
        if (origFwdIMP) {
            [g_originalForward setObject:[NSValue valueWithPointer:origFwdIMP] forKey:cls];
        }
    }

    // 3. Register the invoker for this (cls, selName).
    NSMutableDictionary *perClass = [g_hooksByClass objectForKey:cls];
    if (!perClass) {
        perClass = [NSMutableDictionary dictionary];
        [g_hooksByClass setObject:perClass forKey:cls];
    }
    perClass[NSStringFromSelector(sel)] = [invoker copy];

    [g_hookLock unlock];
    return YES;
}

@end
