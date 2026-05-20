// MARK: exteraGram — ObjC runtime swizzling utilities

#import "EGObjCSwizzler.h"

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

@end
