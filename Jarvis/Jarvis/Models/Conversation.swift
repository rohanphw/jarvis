import Foundation
import SwiftData

/// A conversation session between the user and Jarvis
///
/// Each conversation represents one streaming session and contains all messages
/// exchanged during that session, along with metadata like duration and mode.
@Model
final class Conversation {
    /// Unique identifier
    @Attribute(.unique) var id: UUID

    /// Auto-generated title from first user message (max 50 chars)
    var title: String

    /// When the conversation started
    var timestamp: Date

    /// Duration of the conversation in seconds
    var duration: TimeInterval

    /// Mode used for streaming (glasses or iPhone fallback)
    var mode: StreamingMode

    /// All messages in this conversation
    /// - Note: Cascade delete ensures messages are removed when conversation is deleted
    @Relationship(deleteRule: .cascade, inverse: \Message.conversation)
    var messages: [Message]

    // MARK: - Computed Properties

    /// Number of messages in this conversation
    var messageCount: Int {
        messages.count
    }

    /// Timestamp of the last message
    var lastMessageDate: Date? {
        messages.last?.timestamp
    }

    /// Total cost of this conversation (sum of all message costs)
    var totalCostUSD: Double {
        messages.compactMap { $0.audioMetadata?.costUSD }.reduce(0, +)
    }

    // MARK: - Initialization

    init(
        id: UUID = UUID(),
        title: String = "New Conversation",
        timestamp: Date = Date(),
        duration: TimeInterval = 0,
        mode: StreamingMode = .glasses,
        messages: [Message] = []
    ) {
        self.id = id
        self.title = title
        self.timestamp = timestamp
        self.duration = duration
        self.mode = mode
        self.messages = messages
    }

    // MARK: - Methods

    /// Auto-generate title from first user message
    func generateTitle() {
        guard let firstMessage = messages.first(where: { $0.role == .user }) else {
            self.title = "Conversation"
            return
        }

        let preview = String(firstMessage.content.prefix(50))
        self.title = preview.isEmpty ? "Conversation" : preview
    }
}
