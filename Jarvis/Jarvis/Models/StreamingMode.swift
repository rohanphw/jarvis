import Foundation

/// Mode for video streaming
enum StreamingMode: String, Codable {
    /// Streaming from Meta Ray-Ban glasses via DAT SDK
    case glasses

    /// Fallback mode using iPhone's camera (for development without glasses)
    case iPhone
}
