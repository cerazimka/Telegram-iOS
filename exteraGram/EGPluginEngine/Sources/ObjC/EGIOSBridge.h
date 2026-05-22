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

/// Extract python3.14.zip (bundled as a data resource) to destDir, preserving paths.
/// Returns YES on success. Idempotent — call before initializeWithHome:.
+ (BOOL)extractPythonStdlibZip:(NSString *)zipPath toDirectory:(NSString *)destDir;

/// Append `path` to `sys.path` (acquires the GIL). No-op if Python isn't
/// initialised or if the path is already present.
+ (void)appendToSysPath:(NSString *)path;

/// Whether the plugin declares any settings (create_settings or __settings__).
+ (BOOL)pluginHasSettings:(NSString *)pluginId;

/// Snapshot of the plugin's settings items as dicts (one per row).
/// Each dict has at least: index, type, key, title, subtitle, icon, accent,
/// red, link_alias, default, options, has_on_change, has_on_click.
+ (nullable NSArray<NSDictionary<NSString *, id> *> *)getPluginSettings:(NSString *)pluginId;

/// Notify the plugin that the value of the setting at `index` changed.
/// The renderer should call this immediately after writing the value to UserDefaults.
+ (void)invokePluginSettingChange:(NSString *)pluginId
                            index:(NSInteger)index
                            value:(nullable id)value;

/// Notify the plugin that the row at `index` was tapped (Text-style rows).
+ (void)invokePluginSettingClick:(NSString *)pluginId index:(NSInteger)index;

/// Snapshot of registered menu items for the given surface (drawer / context /
/// settings / profile / chat). Each dict carries: handle, plugin_id, menu_type,
/// text, icon, priority, accent, red, link_alias.
+ (NSArray<NSDictionary<NSString *, id> *> *)menuItemsOfType:(NSString *)type;

/// Fire the on_click callback registered for `handle`. No-op if the handle
/// is unknown or the entry has no callback.
+ (void)invokeMenuItemClick:(NSInteger)handle;

@end

NS_ASSUME_NONNULL_END

