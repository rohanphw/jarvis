import Foundation

/// Role of the message sender
enum MessageRole: String, Codable {
    /// Message from the user
    case user

    /// Message from Jarvis (AI assistant)
    case assistant
}
