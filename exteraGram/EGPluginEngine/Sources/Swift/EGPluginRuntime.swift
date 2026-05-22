// MARK: exteraGram — CPython runtime lifecycle manager

import Foundation
import EGLogging
import EGPluginEngineBridge

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

        // Extract stdlib zip (python3.14.zip) from bundle to Caches on first launch.
        // Returns the home dir where lib/python3.14/ was extracted.
        guard let pythonHome = prepareStdlibAndGetHome() else {
            EGLogger.shared.log("PluginRuntime",
                "Python stdlib extraction failed — engine disabled.")
            return
        }

        // Locate the Python SDK .py files (base_plugin, hook_utils, etc.)
        let sdkPath = findSDKPath()

        // Locate the bundled third-party site-packages (requests, cachetools, ...).
        // Optional — engine still starts without it; plugins just won't see those imports.
        let bundledSitePackages = findBundledSitePackages()

        // Log stdlib directory contents to help diagnose extraction issues.
        let stdlibContents = (try? FileManager.default.contentsOfDirectory(atPath: pythonHome))?
            .sorted().joined(separator: ", ") ?? "(empty)"
        EGPluginDebugLog.shared.append(tag: "Runtime", "stdlib dir: \(stdlibContents)")

        // Start logger bridge BEFORE init so ObjC error notifications have a listener.
        EGLoggerBridge.shared.start()

        // CPython must be initialized on the main thread.
        // If we're already on main, call directly; otherwise dispatch synchronously.
        let doInit = {
            EGPluginDebugLog.shared.append(tag: "Runtime", "Initializing CPython… home=\(pythonHome) sdk=\(sdkPath ?? "not found")")
            let ok = EGPythonBridge.initialize(
                withHome: pythonHome,
                sdkPath: sdkPath ?? "",
                pluginsPath: EGPluginsDirectory.plugins.path,
                sitePackagesPath: EGPluginsDirectory.sitePackages.path
            )
            if ok {
                EGLogger.shared.log("PluginRuntime",
                    "Engine ready. home=\(pythonHome) sdk=\(sdkPath ?? "not found")")
                EGPluginDebugLog.shared.append(tag: "Runtime", "CPython ready ✓")
                // Add the bundled third-party site-packages (requests, cachetools…)
                // to sys.path *after* init so the writable user dir keeps priority.
                if let bundled = bundledSitePackages {
                    EGPythonBridge.append(toSysPath: bundled)
                    EGPluginDebugLog.shared.append(tag: "Runtime",
                        "Bundled site-packages on sys.path: \(bundled)")
                }
            } else {
                EGPluginDebugLog.shared.append(tag: "Runtime", "CPython init FAILED ✗")
                EGLogger.shared.log("PluginRuntime", "CPython init failed")
            }
        }
        if Thread.isMainThread {
            doInit()
        } else {
            DispatchQueue.main.sync { doInit() }
        }
    }

    /// Execute block with Python GIL held. No-op if Python not initialized.
    public func withPython(_ block: () -> Void) {
        EGPythonBridge.withPython(block)
    }

    /// Returns the bundle path for a sample plugin shipped with the app.
    /// Example: samplePluginPath(id: "bigReactions") → ".../bigReactions.plugin"
    public func samplePluginPath(id: String) -> String? {
        return Bundle.main.path(forResource: id, ofType: "plugin", inDirectory: "Python/Plugins")
            ?? Bundle.main.urls(forResourcesWithExtension: "plugin", subdirectory: nil)?
               .first(where: { $0.deletingPathExtension().lastPathComponent == id })?.path
    }

    // MARK: - Path discovery

    /// Extract python3.14.zip from the app bundle to Library/Caches/EGPythonStdlib/ on first
    /// launch (or when the app is updated). The zip contains lib/python3.14/** so after
    /// extraction PyConfig.home = cacheDir → Python finds stdlib at cacheDir/lib/python3.14/.
    private func prepareStdlibAndGetHome() -> String? {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let stdlibHome = caches.appendingPathComponent("EGPythonStdlib")
        let markerPath = stdlibHome.appendingPathComponent(".extracted_version").path

        let currentVersion = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
        let extractedVersion = try? String(contentsOfFile: markerPath, encoding: .utf8)

        if extractedVersion == currentVersion {
            return stdlibHome.path
        }

        guard let zipURL = Bundle.main.url(forResource: "python3.14", withExtension: "zip") else {
            EGLogger.shared.log("PluginRuntime",
                "python3.14.zip not found in bundle — " +
                "ensure @python_apple_support//:PythonStdlibZip is in data deps.")
            return nil
        }

        // Remove stale extraction and re-extract
        try? FileManager.default.removeItem(at: stdlibHome)

        let ok = EGPythonBridge.extractPythonStdlibZip(zipURL.path, toDirectory: stdlibHome.path)
        guard ok else {
            EGLogger.shared.log("PluginRuntime", "Failed to extract python3.14.zip")
            return nil
        }

        // Stamp the version so we skip extraction on subsequent launches
        try? currentVersion.write(toFile: markerPath, atomically: true, encoding: .utf8)
        EGLogger.shared.log("PluginRuntime", "Python stdlib extracted to \(stdlibHome.path)")
        return stdlibHome.path
    }

    /// Extract `bundled-site-packages.zip` from the app bundle into
    /// `Library/Caches/EGPythonBundledSitePackages/` on first launch (or after
    /// app updates) and return that directory's path. The zip is shipped as
    /// a single file rather than a directory tree because ios_framework
    /// flattens data dependencies into the framework root — and multiple
    /// package `__init__.py` files would then collide.
    private func findBundledSitePackages() -> String? {
        guard let zipURL = Bundle.main.url(forResource: "bundled-site-packages",
                                           withExtension: "zip") else {
            EGLogger.shared.log("PluginRuntime",
                "bundled-site-packages.zip not found in bundle — third-party imports unavailable")
            return nil
        }

        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let extractDir = caches.appendingPathComponent("EGPythonBundledSitePackages")
        let markerPath = extractDir.appendingPathComponent(".extracted_version").path

        let currentVersion = (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
        let extractedVersion = try? String(contentsOfFile: markerPath, encoding: .utf8)

        if extractedVersion == currentVersion,
           FileManager.default.fileExists(atPath: extractDir.path) {
            return extractDir.path
        }

        // Re-extract on first launch or after an app update.
        try? FileManager.default.removeItem(at: extractDir)
        guard EGPythonBridge.extractPythonStdlibZip(zipURL.path, toDirectory: extractDir.path)
        else {
            EGLogger.shared.log("PluginRuntime",
                "Failed to extract bundled-site-packages.zip")
            return nil
        }
        try? currentVersion.write(toFile: markerPath, atomically: true, encoding: .utf8)
        EGLogger.shared.log("PluginRuntime",
            "Bundled site-packages extracted to \(extractDir.path)")
        return extractDir.path
    }

    /// Find the Python SDK directory (contains base_plugin.py, hook_utils.py, etc.)
    private func findSDKPath() -> String? {
        // Bazel bundles Python/SDK/**/*.py preserving the directory structure.
        for subdir in ["Python/SDK", "Python/SDK/", nil as String?] {
            let url: URL?
            if let subdir {
                url = Bundle.main.url(forResource: "base_plugin", withExtension: "py",
                                      subdirectory: subdir)
            } else {
                url = Bundle.main.url(forResource: "base_plugin", withExtension: "py")
            }
            if let url {
                return url.deletingLastPathComponent().path
            }
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
