// MARK: exteraGram — Plugin TL hook registry

import Foundation

/// Closure-based hook registry. TelegramCore calls these at dispatch points.
/// EGPluginEngine registers closures here at engine startup.
/// No dependency on EGPluginEngine — TelegramCore stays self-contained.
public enum EGPluginHooks {
    /// Called before messages.sendReaction is dispatched.
    /// Modify params["big"] = true to force large reaction animation.
    public static var sendReactionHook: ((inout [String: Any]) -> Void)?

    /// Called when enqueueMessages fires for a real outgoing user message.
    /// params["peer_id"]: Int64, params["count"]: Int
    public static var sendMessageHook: ((inout [String: Any]) -> Void)?

    /// Called when a message is being edited.
    /// params["peer_id"]: Int64, params["message_id"]: Int32, params["text"]: String
    public static var editMessageHook: ((inout [String: Any]) -> Void)?

    /// Called when messages are deleted interactively.
    /// params["message_ids"]: [Int32], params["delete_for_everyone"]: Bool
    public static var deleteMessagesHook: ((inout [String: Any]) -> Void)?

    /// When true, incoming messages are stored without MediaSpoilerMessageAttribute
    /// and without MessageTextEntity(.Spoiler) — anti-spoiler plugin sets this.
    public nonisolated(unsafe) static var antiSpoilerEnabled: Bool = false
}
