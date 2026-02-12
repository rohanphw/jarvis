import Foundation
import SwiftData

/// A single message in a conversation
///
/// Messages can be from the user or the assistant (Jarvis), and optionally
/// include a visual snapshot of what the user was seeing at the time.
@Model
final class Message {
    /// Unique identifier
    @Attribute(.unique) var id: UUID

    /// Who sent this message (user or assistant)
    var role: MessageRole

    /// The text content of the message (transcript)
    var content: String

    /// When this message was sent
    var timestamp: Date

    /// PNG snapshot of user's view when message was sent (user messages only)
    /// - Note: Stored externally to keep database file size manageable
    @Attribute(.externalStorage)
    var snapshot: Data?

    /// Audio metadata (duration, tokens, cost)
    var audioMetadata: AudioMetadata?

    /// The conversation this message belongs to
    @Relationship
    var conversation: Conversation?

    // MARK: - Computed Properties

    /// Whether this message has a visual snapshot attached
    var hasSnapshot: Bool {
        snapshot != nil
    }

    /// Formatted timestamp for display (e.g., "2:30 PM")
    var formattedTime: String {
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: timestamp)
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        snapshot: Data? = nil,
        audioMetadata: AudioMetadata? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.snapshot = snapshot
        self.audioMetadata = audioMetadata
    }
}

// MARK: - Identifiable Conformance
extension Message: Identifiable {}
