// MARK: exteraGram — in-memory plugin debug log buffer

import Foundation

/// Thread-safe ring buffer of recent plugin system log entries.
/// Written by EGLoggerBridge, EGPluginRuntime, and EGPluginsEngineImpl.
/// Observed by EGPluginDebugController (via EGPluginDebugLog.changed notification).
public final class EGPluginDebugLog {
    public static let shared = EGPluginDebugLog()

    public struct Entry: Identifiable, Sendable {
        public let id: UUID
        public let timestamp: Date
        public let tag: String
        public let message: String

        public init(tag: String, message: String) {
            self.id = UUID()
            self.timestamp = Date()
            self.tag = tag
            self.message = message
        }

        public var formattedTimestamp: String {
            let f = DateFormatter()
            f.dateFormat = "HH:mm:ss.SSS"
            return f.string(from: timestamp)
        }
    }

    public static let changed = Notification.Name("app.exteragram.ios.pluginDebugLogChanged")

    private let lock = NSLock()
    private var _entries: [Entry] = []
    private let maxEntries = 500

    private init() {}

    public var entries: [Entry] {
        lock.lock(); defer { lock.unlock() }
        return _entries
    }

    public func append(tag: String, _ message: String) {
        let entry = Entry(tag: tag, message: message)
        lock.lock()
        _entries.append(entry)
        if _entries.count > maxEntries { _entries.removeFirst() }
        lock.unlock()
        // Post on main queue so SwiftUI observers don't need to dispatch.
        if Thread.isMainThread {
            NotificationCenter.default.post(name: Self.changed, object: nil)
        } else {
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: Self.changed, object: nil)
            }
        }
    }

    public func clear() {
        lock.lock(); _entries = []; lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Self.changed, object: nil)
        }
    }
}

// C-callable bridge so ObjC can write synchronously to the debug log without
// going through the async NSNotification chain (avoids lost messages during init).
@_cdecl("EGPluginDebugLog_appendCStr")
public func EGPluginDebugLog_appendCStr(_ tag: UnsafePointer<CChar>?, _ message: UnsafePointer<CChar>?) {
    let tagStr = tag.map { String(cString: $0) } ?? "Plugin"
    let msgStr = message.map { String(cString: $0) } ?? ""
    EGPluginDebugLog.shared.append(tag: tagStr, msgStr)
}
