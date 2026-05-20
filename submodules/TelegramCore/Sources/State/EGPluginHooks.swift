// MARK: exteraGram — Plugin TL hook registry

import Foundation

/// Closure-based hook registry. TelegramCore calls these at dispatch points.
/// EGPluginEngine registers closures here at engine startup.
/// No dependency on EGPluginEngine — TelegramCore stays self-contained.
public enum EGPluginHooks {
    /// Called before messages.sendReaction is dispatched.
    /// Modify params["big"] = true to force large reaction animation.
    public static var sendReactionHook: ((inout [String: Any]) -> Void)?
}
