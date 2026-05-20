// MARK: exteraGram — Swift-side TL hook dispatcher

import Foundation
import EGLogging

/// Called from TelegramCore at TL dispatch points.
/// Bridges Swift interception points → Python plugin callbacks via EGPythonBridge.
public final class EGTLHookBridge {
    public static let shared = EGTLHookBridge()
    private init() {}

    /// Fire all Python hooks registered for `tlType`.
    /// The `params` dict is modified in-place by any registered callback.
    public func dispatchTLHook(_ tlType: String, params: inout [String: Any]) {
        guard EGPythonBridge.isInitialized else { return }
        let mutable = NSMutableDictionary(dictionary: params)
        EGPythonBridge.dispatchTLHook(tlType, params: mutable)
        // Write back any modifications
        for (key, value) in mutable {
            if let k = key as? String { params[k] = value }
        }
    }

    /// Convenience for BigReactions: returns true if any plugin forces large reactions.
    public func shouldForceLargeReaction() -> Bool {
        guard EGPythonBridge.isInitialized,
              EGPythonBridge.hasHook("messages.sendReaction") else { return false }
        var params: [String: Any] = ["big": false]
        dispatchTLHook("messages.sendReaction", params: &params)
        return params["big"] as? Bool ?? false
    }
}
