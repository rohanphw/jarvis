import Foundation
import SwiftData

/// Repository for managing conversation data in SwiftData
///
/// Provides a clean API for CRUD operations, search, and export functionality.
/// All operations are performed on the main actor for UI safety.
@MainActor
class ConversationRepository {
    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    // MARK: - Create

    /// Create a new conversation
    func createConversation(mode: StreamingMode) -> Conversation {
        let conversation = Conversation(mode: mode)
        modelContext.insert(conversation)
        return conversation
    }

    /// Add a message to a conversation
    func addMessage(
        to conversation: Conversation,
        role: MessageRole,
        content: String,
        audioMetadata: AudioMetadata? = nil
    ) {
        let message = Message(
            role: role,
            content: content,
            audioMetadata: audioMetadata
        )
        message.conversation = conversation
        conversation.messages.append(message)

        // Auto-generate title from first user message
        if conversation.messages.count == 1 && role == .user {
            conversation.generateTitle()
        }

        try? modelContext.save()
    }

    // MARK: - Read

    /// Fetch all conversations sorted by date
    func fetchAllConversations(sortedBy sortOrder: SortOrder = .reverse) -> [Conversation] {
        let descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.timestamp, order: sortOrder)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Search conversations by text content
    func searchConversations(query: String) -> [Conversation] {
        guard !query.isEmpty else {
            return fetchAllConversations()
        }

        let predicate = #Predicate<Conversation> { conversation in
            conversation.title.localizedStandardContains(query) ||
            conversation.messages.contains { message in
                message.content.localizedStandardContains(query)
            }
        }

        let descriptor = FetchDescriptor<Conversation>(
            predicate: predicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        return (try? modelContext.fetch(descriptor)) ?? []
    }

    /// Fetch a specific conversation by ID
    func fetchConversation(id: UUID) -> Conversation? {
        let predicate = #Predicate<Conversation> { $0.id == id }
        var descriptor = FetchDescriptor<Conversation>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    /// Fetch recent conversations (last N)
    func fetchRecentConversations(limit: Int = 10) -> [Conversation] {
        var descriptor = FetchDescriptor<Conversation>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    // MARK: - Update

    /// Update conversation duration
    func updateDuration(for conversation: Conversation, duration: TimeInterval) {
        conversation.duration = duration
        try? modelContext.save()
    }

    // MARK: - Delete

    /// Delete a conversation and all its messages
    func deleteConversation(_ conversation: Conversation) {
        modelContext.delete(conversation)
        try? modelContext.save()
    }

    /// Delete multiple conversations
    func deleteConversations(_ conversations: [Conversation]) {
        conversations.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    /// Delete conversations older than specified days
    func deleteOldConversations(olderThan days: Int) {
        guard let cutoffDate = Calendar.current.date(
            byAdding: .day,
            value: -days,
            to: Date()
        ) else { return }

        let predicate = #Predicate<Conversation> { $0.timestamp < cutoffDate }
        let descriptor = FetchDescriptor<Conversation>(predicate: predicate)

        guard let oldConversations = try? modelContext.fetch(descriptor) else { return }
        oldConversations.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    /// Delete all conversations (use with caution!)
    func deleteAllConversations() {
        let descriptor = FetchDescriptor<Conversation>()
        guard let allConversations = try? modelContext.fetch(descriptor) else { return }
        allConversations.forEach { modelContext.delete($0) }
        try? modelContext.save()
    }

    // MARK: - Export

    /// Export a conversation as Markdown
    func exportConversation(_ conversation: Conversation) -> String {
        var output = """
        # \(conversation.title)

        **Date:** \(conversation.timestamp.formatted(date: .long, time: .shortened))
        **Duration:** \(formatDuration(conversation.duration))
        **Mode:** \(conversation.mode.rawValue)
        **Messages:** \(conversation.messageCount)

        ---

        """

        for message in conversation.messages {
            let role = message.role == .user ? "👤 You" : "🤖 Jarvis"
            let time = message.timestamp.formatted(date: .omitted, time: .shortened)

            output += """
            ### \(role) · \(time)

            \(message.content)

            """

            if let audio = message.audioMetadata {
                output += "_Duration: \(String(format: "%.1f", audio.durationSeconds))s"
                if let cost = audio.costUSD {
                    output += " · Cost: $\(String(format: "%.4f", cost))"
                }
                output += "_\n\n"
            }

            output += "---\n\n"
        }

        return output
    }

    /// Export conversation as JSON
    func exportConversationAsJSON(_ conversation: Conversation) -> Data? {
        let exportData: [String: Any] = [
            "id": conversation.id.uuidString,
            "title": conversation.title,
            "timestamp": conversation.timestamp.ISO8601Format(),
            "duration": conversation.duration,
            "mode": conversation.mode.rawValue,
            "messages": conversation.messages.map { message in
                var messageDict: [String: Any] = [
                    "id": message.id.uuidString,
                    "role": message.role.rawValue,
                    "content": message.content,
                    "timestamp": message.timestamp.ISO8601Format()
                ]

                // Add audio metadata if exists
                if let audio = message.audioMetadata {
                    var audioDict: [String: Any] = [
                        "durationSeconds": audio.durationSeconds
                    ]

                    if let tokens = audio.tokensUsed {
                        audioDict["tokensUsed"] = tokens
                    } else {
                        audioDict["tokensUsed"] = NSNull()
                    }

                    if let cost = audio.costUSD {
                        audioDict["costUSD"] = cost
                    } else {
                        audioDict["costUSD"] = NSNull()
                    }

                    messageDict["audioMetadata"] = audioDict
                } else {
                    messageDict["audioMetadata"] = NSNull()
                }

                return messageDict
            }
        ]

        return try? JSONSerialization.data(withJSONObject: exportData, options: .prettyPrinted)
    }

    /// Export all conversations as combined Markdown
    func exportAllConversations() -> String {
        let conversations = fetchAllConversations()

        var output = """
        # Jarvis Conversation Export

        **Exported:** \(Date().formatted(date: .long, time: .shortened))
        **Total Conversations:** \(conversations.count)
        **Total Messages:** \(conversations.reduce(0) { $0 + $1.messageCount })

        ---

        """

        for conversation in conversations {
            output += "\n\n"
            output += exportConversation(conversation)
            output += "\n\n"
        }

        return output
    }

    /// Export all conversations as JSON array
    func exportAllConversationsAsJSON() -> Data? {
        let conversations = fetchAllConversations()

        let exportArray = conversations.compactMap { conversation in
            if let jsonData = exportConversationAsJSON(conversation),
               let json = try? JSONSerialization.jsonObject(with: jsonData) {
                return json
            }
            return nil
        }

        return try? JSONSerialization.data(withJSONObject: exportArray, options: .prettyPrinted)
    }

    // MARK: - Analytics

    /// Get total number of conversations
    func getTotalConversationCount() -> Int {
        let descriptor = FetchDescriptor<Conversation>()
        return (try? modelContext.fetchCount(descriptor)) ?? 0
    }

    /// Get total cost across all conversations
    func getTotalCost() -> Double {
        let conversations = fetchAllConversations()
        return conversations.reduce(0.0) { $0 + $1.totalCostUSD }
    }

    /// Get storage usage estimate (in MB)
    /// Note: Returns approximate text-based storage only
    func getStorageUsageEstimate() -> Double {
        let conversations = fetchAllConversations()
        // Rough estimate: count characters in content
        let totalChars = conversations.reduce(0) { total, conversation in
            total + conversation.messages.reduce(0) { msgTotal, message in
                msgTotal + message.content.count
            }
        }
        // Approximate 2 bytes per character
        return Double(totalChars * 2) / 1_048_576 // Convert to MB
    }

    // MARK: - Private Helpers

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
