// MARK: exteraGram — Plugin execution watchdog (5-second timeout)

import Foundation
import EGLogging

/// Monitors plugin execution time. If a plugin callback takes longer than the timeout,
/// the plugin is marked as "not responding" and its hooks are cleared.
final class EGPluginsWatchdog {
    static let shared = EGPluginsWatchdog()
    private let timeout: TimeInterval = 5.0
    private var timers: [String: Timer] = [:]
    private let lock = NSLock()
    private init() {}

    /// Start a watchdog timer for a plugin execution. Call `end(pluginId:)` when done.
    func begin(pluginId: String, onTimeout: @escaping () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        timers[pluginId]?.invalidate()
        let timer = Timer.scheduledTimer(withTimeInterval: timeout, repeats: false) { [weak self] _ in
            EGLogger.shared.log("Watchdog", "Plugin '\(pluginId)' timed out (>\(self?.timeout ?? 5)s)")
            onTimeout()
        }
        timers[pluginId] = timer
    }

    func end(pluginId: String) {
        lock.lock()
        defer { lock.unlock() }
        timers[pluginId]?.invalidate()
        timers.removeValue(forKey: pluginId)
    }
}
