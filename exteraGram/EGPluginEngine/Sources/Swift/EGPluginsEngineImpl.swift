// MARK: exteraGram — Plugin engine: load/unload/enable/disable

import Foundation
import EGLogging
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
        let watchdog = EGPluginsWatchdog.shared
        watchdog.begin(pluginId: id) { [weak self] in self?.notResponding[id] = true }
        let errMsg = EGPythonBridge.loadPlugin(id, fromPath: filePath)
        watchdog.end(pluginId: id)
        if let errMsg {
            errorStates[id] = errMsg
            EGLogger.shared.log("PluginEngine", "Error loading \(id): \(errMsg)")
        } else {
            errorStates.removeValue(forKey: id)
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
    public func pluginHasSettings(_ id: String) -> Bool { hasSettingsMap[id] == true }

    // MARK: - Enable / Disable

    public func setPluginEnabled(id: String, enabled: Bool) {
        if enabled {
            // filePath must be looked up by the caller (PluginsController)
            // This is a no-op stub; PluginsController calls loadPlugin/unloadPlugin directly
        } else {
            unloadPlugin(id)
        }
    }

    // MARK: - Settings (stub — expand when ui/settings.py lands)

    public func getPluginSetting(_ id: String, key: String, default def: Any?) -> Any? { def }
    public func setPluginSetting(_ id: String, key: String, value: Any) { }
}
