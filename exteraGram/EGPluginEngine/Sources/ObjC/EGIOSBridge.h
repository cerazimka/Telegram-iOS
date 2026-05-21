// MARK: exteraGram — EGPluginEngine ObjC/Python bridge

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bridge between Python and iOS Swift/ObjC layer.
/// Uses CPython C API internally; public interface is pure ObjC.
@interface EGPythonBridge : NSObject

/// Initialize CPython 3.14 runtime using the modern PyConfig API.
/// @param pythonHome  Path where lib/python3.14/ can be found (PyConfig.home).
/// @param sdkPath     Path to Python SDK .py files (added to module search paths).
/// @param pluginsPath Path to installed .plugin files.
/// @param sitePkgs    Path to site-packages directory.
/// @return YES if CPython started successfully.
+ (BOOL)initializeWithHome:(NSString *)pythonHome
                   sdkPath:(NSString *)sdkPath
               pluginsPath:(NSString *)pluginsPath
          sitePackagesPath:(NSString *)sitePkgs;

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

/// Returns YES if the loaded plugin module exposes a `__settings__` attribute.
+ (BOOL)pluginHasSettings:(NSString *)pluginId;

/// Returns the plugin's `__settings__.to_dict()` as an NSDictionary, or nil if none.
+ (nullable NSDictionary *)getPluginSettingsSchema:(NSString *)pluginId;

/// Call `on_setting_action(key)` on the loaded plugin module, if defined.
/// Used by 'button'-type settings to dispatch tap events into Python.
+ (void)invokePluginAction:(NSString *)pluginId key:(NSString *)key;

/// Extract python3.14.zip (bundled as a data resource) to destDir, preserving paths.
/// Returns YES on success. Idempotent — call before initializeWithHome:.
+ (BOOL)extractPythonStdlibZip:(NSString *)zipPath toDirectory:(NSString *)destDir;

/// Block set by EGPluginsEngineImpl to wire set_anti_spoiler() → EGPluginHooks.antiSpoilerEnabled.
@property (class, nonatomic, copy, nullable) void (^antiSpoilerEnabledSetter)(BOOL);

@end

NS_ASSUME_NONNULL_END

