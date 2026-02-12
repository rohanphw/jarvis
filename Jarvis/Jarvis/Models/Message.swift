import Foundation
import SwiftData

/// A single message in a conversation
///
/// Messages represent text exchanges between the user and Jarvis (assistant)
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

    /// Audio metadata (duration, tokens, cost)
    var audioMetadata: AudioMetadata?

    /// The conversation this message belongs to
    @Relationship
    var conversation: Conversation?

    // MARK: - Computed Properties

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
        audioMetadata: AudioMetadata? = nil
    ) {
        self.id = id
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.audioMetadata = audioMetadata
    }
}
