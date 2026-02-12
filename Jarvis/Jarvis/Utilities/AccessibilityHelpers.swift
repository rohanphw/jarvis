import Foundation

/// Helpers for accessibility labels and hints
struct AccessibilityHelpers {
    /// Format duration for VoiceOver
    static func formatDurationForAccessibility(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60

        if minutes > 0 {
            return "\(minutes) minute\(minutes == 1 ? "" : "s") and \(seconds) second\(seconds == 1 ? "" : "s")"
        } else {
            return "\(seconds) second\(seconds == 1 ? "" : "s")"
        }
    }

    /// Format date for VoiceOver
    static func formatDateForAccessibility(_ date: Date) -> String {
        let now = Date()
        let calendar = Calendar.current

        // If today
        if calendar.isDateInToday(date) {
            return "Today at \(date.formatted(date: .omitted, time: .shortened))"
        }

        // If yesterday
        if calendar.isDateInYesterday(date) {
            return "Yesterday at \(date.formatted(date: .omitted, time: .shortened))"
        }

        // If this week
        if let daysAgo = calendar.dateComponents([.day], from: date, to: now).day,
           daysAgo < 7 {
            return date.formatted(date: .complete, time: .shortened)
        }

        // Otherwise
        return date.formatted(date: .long, time: .shortened)
    }

    /// Create accessibility label for conversation
    static func conversationAccessibilityLabel(
        title: String,
        messageCount: Int,
        date: Date,
        duration: TimeInterval
    ) -> String {
        let dateString = formatDateForAccessibility(date)
        let durationString = formatDurationForAccessibility(duration)

        return "Conversation: \(title). \(messageCount) message\(messageCount == 1 ? "" : "s"). \(dateString). Duration: \(durationString)"
    }
}
