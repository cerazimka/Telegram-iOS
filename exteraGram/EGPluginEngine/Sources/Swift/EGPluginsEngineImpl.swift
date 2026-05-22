// MARK: exteraGram — Plugin engine: load/unload/enable/disable

import Foundation
import EGLogging
import EGPluginEngineBridge
import TelegramCore

/// Core engine. Owned by EGSettingsUI's PluginsController.
/// Does NOT import EGSettingsUI — dependency flows: EGSettingsUI → EGPluginEngine.
public final class EGPluginsEngineImpl {
    private var errorStates: [String: String] = [:]
    private var notResponding: [String: Bool] = [:]
    private var hasSettingsMap: [String: Bool] = [:]
    private let engineQueue = DispatchQueue(
        label: "app.exteragram.ios.pluginEngine",
        qos: .userInitiated
    )

    public init() {}

    // MARK: - Lifecycle

    /// Start engine and load the given plugins.
    /// `plugins` is a list of (id, filePath) pairs from PluginsController.
    public func start(plugins: [(id: String, filePath: String)], completion: @escaping () -> Void) {
        // Spin up the bulletin/toast presenter on the main thread before any
        // plugins try to call into _ios_bridge.show_bulletin / show_toast.
        DispatchQueue.main.async { EGPluginBulletinHost.shared.start() }
        engineQueue.async {
            EGPluginRuntime.shared.initialize()
            guard EGPythonBridge.isInitialized else {
                EGLogger.shared.log("PluginEngine", "Python unavailable — engine stub mode")
                completion()
                return
            }
            // Wire TL hook registry
            EGPluginHooks.sendReactionHook = { params in
                EGTLHookBridge.shared.dispatchTLHook("messages.sendReaction", params: &params)
            }
            EGLogger.shared.log("PluginEngine", "Starting \(plugins.count) plugin(s)…")
            for plugin in plugins {
                // loadPlugin also calls EGPluginRuntime.initialize() — dispatch_once makes it safe.
                self.loadPlugin(id: plugin.id, filePath: plugin.filePath)
            }
            EGLogger.shared.log("PluginEngine", "Engine started")
            completion()
        }
    }

    public func stop(pluginIds: [String], completion: @escaping () -> Void) {
        engineQueue.async {
            EGPluginHooks.sendReactionHook = nil
            for id in pluginIds {
                if EGPythonBridge.isInitialized {
                    EGPythonBridge.unloadPlugin(id)
                }
            }
            self.errorStates.removeAll()
            self.notResponding.removeAll()
            self.hasSettingsMap.removeAll()
            EGLogger.shared.log("PluginEngine", "Engine stopped")
            completion()
        }
    }

    // MARK: - Install (validate + copy file to Documents/EGPlugins/)

    /// Validate metadata and copy the plugin file to its final location.
    /// Returns the parsed metadata on success; caller creates the EGPlugin.
    public func installPlugin(from filePath: String) throws -> EGFullPluginMetadata {
        let meta = try EGPluginLoader.shared.parseAndValidate(path: filePath)
        EGPluginsDirectory.plugins.create()
        let dest = EGPluginsDirectory.plugins.url.appendingPathComponent("\(meta.id).plugin")
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.copyItem(atPath: filePath, toPath: dest.path)
        EGLogger.shared.log("PluginEngine", "Installed \(meta.id) v\(meta.version)")
        return meta
    }

    // MARK: - Load / Unload

    public func loadPlugin(id: String, filePath: String) {
        guard !filePath.isEmpty else { errorStates[id] = "No file path"; return }
        // Ensure Python is initialized. dispatch_once in EGPythonBridge makes this safe to call
        // from any thread, even concurrently — the second caller waits for the first to finish.
        EGPluginRuntime.shared.initialize()
        guard EGPythonBridge.isInitialized else {
            let msg = "Python runtime unavailable"
            errorStates[id] = msg
            EGPluginDebugLog.shared.append(tag: "Engine", "[\(id)] \(msg)")
            return
        }
        let watchdog = EGPluginsWatchdog.shared
        watchdog.begin(pluginId: id) { [weak self] in self?.notResponding[id] = true }
        EGPluginDebugLog.shared.append(tag: "Engine", "Loading plugin: \(id)")
        let errMsg = EGPythonBridge.loadPlugin(id, fromPath: filePath)
        watchdog.end(pluginId: id)
        if let errMsg {
            errorStates[id] = errMsg
            EGLogger.shared.log("PluginEngine", "Error loading \(id): \(errMsg)")
            EGPluginDebugLog.shared.append(tag: "Engine", "ERROR [\(id)]: \(errMsg)")
        } else {
            errorStates.removeValue(forKey: id)
            EGPluginDebugLog.shared.append(tag: "Engine", "Loaded [\(id)] ✓")
        }
    }

    public func unloadPlugin(_ id: String) {
        EGPythonBridge.unloadPlugin(id)
        errorStates.removeValue(forKey: id)
        notResponding.removeValue(forKey: id)
        hasSettingsMap.removeValue(forKey: id)
    }

    // MARK: - State queries

    public func isPluginError(_ id: String) -> Bool { errorStates[id] != nil }
    public func pluginErrorMessage(_ id: String) -> String? { errorStates[id] }
    public func isPluginNotResponding(_ id: String) -> Bool { notResponding[id] == true }

    /// Cheap cached check used during list rendering. Refreshed lazily —
    /// callers that need the up-to-date value should call refreshHasSettings.
    public func pluginHasSettings(_ id: String) -> Bool {
        if let cached = hasSettingsMap[id] { return cached }
        let value = EGPythonBridge.pluginHasSettings(id)
        hasSettingsMap[id] = value
        return value
    }

    /// Force a refresh of the pluginHasSettings cache for one plugin.
    public func refreshHasSettings(_ id: String) {
        hasSettingsMap[id] = EGPythonBridge.pluginHasSettings(id)
    }

    // MARK: - Enable / Disable

    public func setPluginEnabled(id: String, enabled: Bool) {
        if enabled {
            // filePath must be looked up by the caller (PluginsController)
            // This is a no-op stub; PluginsController calls loadPlugin/unloadPlugin directly
        } else {
            unloadPlugin(id)
        }
    }

    // MARK: - Settings

    /// Fetch the plugin's declared SettingItem list (already serialised to dicts
    /// by the Python `_eg_internal.get_settings_items`). The Swift renderer
    /// consumes these to build its UI.
    public func getPluginSettingsItems(_ id: String) -> [[String: Any]] {
        guard let raw = EGPythonBridge.getPluginSettings(id) else { return [] }
        return raw as? [[String: Any]] ?? []
    }

    /// Read a single namespaced UserDefaults value (mirrors the Python
    /// `_ios_bridge.get_plugin_setting` storage layout).
    public func getPluginSetting(_ id: String, key: String, default def: Any?) -> Any? {
        let defaultsKey = "eg.plugin.\(id).\(key)"
        return UserDefaults.standard.object(forKey: defaultsKey) ?? def
    }

    /// Write a value to the namespaced UserDefaults bucket. Notifies the Python
    /// plugin via invokePluginSettingChange so on_change fires synchronously.
    public func setPluginSetting(_ id: String, key: String, value: Any) {
        let defaultsKey = "eg.plugin.\(id).\(key)"
        UserDefaults.standard.set(value, forKey: defaultsKey)
    }

    /// Invoke the on_change callback (and persist) for the setting at `index`.
    public func notifyPluginSettingChange(_ id: String, index: Int, value: Any?) {
        EGPythonBridge.invokePluginSettingChange(id, index: index, value: value)
    }

    /// Invoke the on_click callback for the row at `index`.
    public func notifyPluginSettingClick(_ id: String, index: Int) {
        EGPythonBridge.invokePluginSettingClick(id, index: index)
    }
}
