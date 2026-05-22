// MARK: exteraGram — ObjC runtime swizzling utilities

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

/// Block called when a hooked method is invoked. The invocation has its target,
/// selector and arguments already configured. The block is responsible for calling
/// the original implementation by setting `invocation.selector = aliasSelector` and
/// calling `[invocation invoke]` (or skipping the call entirely).
typedef void (^EGForwardInvocationBlock)(NSInvocation *invocation, SEL aliasSelector);

/// Lightweight ObjC method swizzler. Used by plugins that hook into UIKit or Telegram ObjC classes.
@interface EGObjCSwizzler : NSObject

/// Swizzle instance method. Returns YES if successful.
+ (BOOL)swizzleClass:(Class)cls
     originalSelector:(SEL)original
     swizzledSelector:(SEL)swizzled;

/// Swizzle class method. Returns YES if successful.
+ (BOOL)swizzleClassMethod:(Class)cls
          originalSelector:(SEL)original
          swizzledSelector:(SEL)swizzled;

/// Install a forwardInvocation-based hook on an instance method.
///
/// The original IMP is moved to an aliased selector (`__eg_alias_<sel>`), the original
/// selector is repointed at `_objc_msgForward`, and `forwardInvocation:` on the class
/// is swizzled to dispatch into `invoker`. The invoker receives the NSInvocation and
/// the aliased selector — it must invoke the original (or not) and may inspect/modify
/// arguments and return value.
///
/// Subsequent calls for the same (class, selector) replace the invoker.
/// Hooks do NOT automatically fire on subclass overrides — hook the subclass too if needed.
///
/// @return YES if the method exists on `cls` (or is inherited) and the hook was installed.
+ (BOOL)installForwardHookOnClass:(Class)cls
                         selector:(SEL)sel
                          invoker:(EGForwardInvocationBlock)invoker;

/// Compute the aliased selector that holds the original IMP for the given selector.
+ (SEL)aliasSelectorForOriginal:(SEL)sel;

@end

NS_ASSUME_NONNULL_END
