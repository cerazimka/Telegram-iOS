// MARK: exteraGram — CPython runtime lifecycle manager

import Foundation
import EGLogging

/// Manages CPython initialization and plugin directory layout.
/// All interactions with Python must happen through `withPython {}` to ensure GIL safety.
public final class EGPluginRuntime {
    public static let shared = EGPluginRuntime()

    public var isInitialized: Bool { EGPythonBridge.isInitialized }

    private init() {}

    /// Initialize CPython. Safe to call multiple times (no-op after first call).
    public func initialize() {
        guard !EGPythonBridge.isInitialized else { return }

        // Set up writable plugin directories
        EGPluginsDirectory.plugins.create()
        EGPluginsDirectory.sitePackages.create()

        // Migrate any plugins from old AppSupport location
        migrateFromAppSupport()

        // Locate the Python 3.14 stdlib inside the app bundle.
        // Bazel bundles data files at their workspace-relative path, so we
        // search rather than hardcode the exact bundle path.
        guard let pythonHome = findPythonHome() else {
            EGLogger.shared.log("PluginRuntime",
                "Python.xcframework stdlib not found in bundle. " +
                "Run Bazel build with @python_apple_support//:PythonStdlib in data deps.")
            return
        }

        // Locate the Python SDK .py files (base_plugin, hook_utils, etc.)
        // Also searched because Bazel data path depends on build configuration.
        let sdkPath = findSDKPath()

        let ok = EGPythonBridge.initialize(
            withHome: pythonHome,
            sdkPath: sdkPath ?? "",
            pluginsPath: EGPluginsDirectory.plugins.path,
            sitePackagesPath: EGPluginsDirectory.sitePackages.path
        )

        if ok {
            EGLoggerBridge.shared.start()
            EGLogger.shared.log("PluginRuntime",
                "Engine ready. home=\(pythonHome) sdk=\(sdkPath ?? "not found")")
        }
    }

    /// Execute block with Python GIL held. No-op if Python not initialized.
    public func withPython(_ block: () -> Void) {
        EGPythonBridge.withPython(block)
    }

    // MARK: - Path discovery

    /// Find the directory whose `lib/python3.14/` subtree contains the stdlib.
    /// Sets config.home = this directory, so Python finds stdlib at <home>/lib/python3.14/.
    private func findPythonHome() -> String? {
        let bundleURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        guard let enumerator = FileManager.default.enumerator(
            at: bundleURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        for case let url as URL in enumerator {
            guard url.lastPathComponent == "python3.14" else { continue }
            guard let isDir = try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory,
                  isDir == true else { continue }
            // url = <bundle>/.../lib/python3.14  →  home = <bundle>/.../
            let libDir = url.deletingLastPathComponent()   // .../lib
            let homeDir = libDir.deletingLastPathComponent()
            return homeDir.path
        }
        return nil
    }

    /// Find the Python SDK directory (contains base_plugin.py, hook_utils.py, etc.)
    private func findSDKPath() -> String? {
        if let url = Bundle.main.url(forResource: "base_plugin", withExtension: "py") {
            return url.deletingLastPathComponent().path
        }
        return nil
    }

    // MARK: - One-time migration from Application Support → Documents

    private func migrateFromAppSupport() {
        guard let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return }

        let oldDir = appSupport.appendingPathComponent("EGPlugins")
        guard FileManager.default.fileExists(atPath: oldDir.path) else { return }

        let newDir = EGPluginsDirectory.plugins.url
        let fm = FileManager.default

        do {
            let files = try fm.contentsOfDirectory(atPath: oldDir.path)
            for name in files where name.hasSuffix(".plugin") {
                let src = oldDir.appendingPathComponent(name)
                let dst = newDir.appendingPathComponent(name)
                if !fm.fileExists(atPath: dst.path) {
                    try fm.copyItem(at: src, to: dst)
                }
            }
            try? fm.removeItem(at: oldDir)
            EGLogger.shared.log("PluginRuntime", "Migrated plugins AppSupport → Documents")
        } catch {
            EGLogger.shared.log("PluginRuntime", "Migration error: \(error)")
        }
    }
}

// MARK: - Plugin directory layout (Documents/EGPlugins/)

public enum EGPluginsDirectory {
    case plugins
    case sitePackages
    case data(String)

    public var url: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        switch self {
        case .plugins:       return docs.appendingPathComponent("EGPlugins")
        case .sitePackages:  return docs.appendingPathComponent("EGPlugins/site-packages")
        case .data(let id):  return docs.appendingPathComponent("EGPlugins/.data/\(id)")
        }
    }

    public var path: String { url.path }

    public func create() {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
}
