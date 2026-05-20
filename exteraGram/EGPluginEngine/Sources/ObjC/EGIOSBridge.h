// MARK: exteraGram — EGPluginEngine ObjC/Python bridge

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridge between Python and iOS Swift/ObjC layer.
/// Uses CPython C API internally; public interface is pure ObjC.
@interface EGPythonBridge : NSObject

/// Initialize CPython runtime. Call once before any plugin operations.
/// Returns YES if CPython started successfully.
+ (BOOL)initialize;

/// Whether CPython has been initialized.
@property (class, nonatomic, readonly) BOOL isInitialized;

/// Execute block with the Python GIL held. Safe to call from any thread.
/// No-op if not initialized.
+ (void)withPython:(NS_NOESCAPE void (^)(void))block;

/// Load a .plugin file as a Python module and call its on_load().
/// Returns nil on success, or an error description string on failure.
+ (nullable NSString *)loadPlugin:(NSString *)pluginId fromPath:(NSString *)path;

/// Unload a plugin: call on_unload() and remove from sys.modules.
+ (void)unloadPlugin:(NSString *)pluginId;

/// Fire all Python TL hook callbacks registered for tlType.
/// The params dict is converted to a Python dict, passed to each callback,
/// then the (possibly modified) values are written back into params.
+ (void)dispatchTLHook:(NSString *)tlType params:(NSMutableDictionary<NSString *, id> *)params;

/// Whether any loaded plugin has registered a hook for the given TL type.
+ (BOOL)hasHook:(NSString *)tlType;

/// Called by the Python _ios_bridge extension to log messages.
+ (void)logFromPlugin:(NSString *)tag message:(NSString *)message;

@end

NS_ASSUME_NONNULL_END
