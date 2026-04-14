// MARK: ExteraGram

import Foundation

// MARK: - Public API models

/// A single badge attached to an ExteraGram profile (developer / supporter).
/// The `documentId` references an animated emoji from the "exteraBadges" sticker pack.
public struct EGBadgeDTO: Codable, Equatable, Hashable {
    public let documentId: Int64
    /// Custom tooltip text, or nil → use default "Developer"/"Supporter" string.
    public var text: String?

    public init(documentId: Int64, text: String? = nil) {
        self.documentId = documentId
        self.text = text
    }

    enum CodingKeys: String, CodingKey {
        case documentId = "document_id"
        case text
    }
}

public enum EGProfileStatus: String, Codable, Equatable {
    case `default`  = "DEFAULT"
    case developer  = "DEVELOPER"
    case supporter  = "SUPPORTER"
}

/// Full profile record returned by the ExteraGram API `/profiles` endpoint.
public struct EGProfileDTO: Codable {
    public let id: Int64
    /// `"USER"` or `"CHAT"`.
    public let type: String
    public let status: EGProfileStatus
    public let badge: EGBadgeDTO?
    public let canChangeBadge: Bool?
    public let deleted: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case status
        case badge
        case canChangeBadge = "can_change_badge"
        case deleted
    }
}

// MARK: - Internal cache model

struct EGBadgeInfo: Codable, Equatable {
    let badge: EGBadgeDTO?
    let status: EGProfileStatus
    let canChangeBadge: Bool
}
