// MARK: exteraGram — CPython runtime lifecycle manager

import Foundation
import EGLogging

/// Manages CPython initialization and plugin directory layout.
/// All interactions with Python must happen through `withPython {}` to ensure GIL safety.
public final class EGPluginRuntime {
    public static let shared = EGPluginRuntime()

    public private(set) var isInitialized: Bool { EGPythonBridge.isInitialized }

    private init() {}

    /// Initialize CPython. Safe to call multiple times (no-op after first call).
    public func initialize() {
        guard !EGPythonBridge.isInitialized else { return }

        // Set up directories
        EGPluginsDirectory.plugins.create()
        EGPluginsDirectory.sitePackages.create()

        // Migrate any plugins from old AppSupport location
        migrateFromAppSupport()

        // Locate the Python stdlib inside the bundled framework
        guard let stdlibPath = Bundle.main.path(
            forResource: "python3.12", ofType: nil,
            inDirectory: "Frameworks/Python.framework/lib"
        ) ?? Bundle.main.path(
            forResource: "lib", ofType: nil,
            inDirectory: "Frameworks/Python.framework"
        ) else {
            EGLogger.shared.log("PluginRuntime", "FATAL: Python stdlib not found in bundle — add Python.xcframework")
            return
        }

        // SDK .py files are shipped as Bazel `data` and land in the bundle root
        let sdkPath = Bundle.main.bundlePath + "/Python/SDK"

        setenv("PYTHONPATH", [
            stdlibPath,
            sdkPath,
            EGPluginsDirectory.plugins.path,
            EGPluginsDirectory.sitePackages.path
        ].joined(separator: ":"), 1)
        setenv("PYTHONDONTWRITEBYTECODE", "1", 1)
        setenv("PYTHONIOENCODING", "utf-8", 1)
        setenv("PYTHONFAULTHANDLER", "1", 1)
        // Prevent Python from trying to write to read-only bundle paths
        setenv("PYTHONNOUSERSITE", "1", 1)

        let ok = EGPythonBridge.initialize()
        if ok {
            EGLoggerBridge.shared.start()
            EGLogger.shared.log("PluginRuntime", "Engine ready. plugins=\(EGPluginsDirectory.plugins.path)")
        }
    }

    /// Execute block with Python GIL held. No-op if Python not initialized.
    public func withPython(_ block: () -> Void) {
        EGPythonBridge.withPython(block)
    }

    // MARK: - One-time migration from Application Support to Documents

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
            // Remove old dir after successful migration
            try? fm.removeItem(at: oldDir)
            EGLogger.shared.log("PluginRuntime", "Migrated plugins from AppSupport → Documents")
        } catch {
            EGLogger.shared.log("PluginRuntime", "Migration error: \(error)")
        }
    }
}

// MARK: - Plugin directory layout

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
