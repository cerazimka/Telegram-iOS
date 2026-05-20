// MARK: exteraGram — ObjC runtime swizzling utilities

#import <Foundation/Foundation.h>
#import <objc/runtime.h>

NS_ASSUME_NONNULL_BEGIN

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

@end

NS_ASSUME_NONNULL_END
