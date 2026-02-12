import Foundation

/// Metadata about audio messages for analytics and cost tracking
struct AudioMetadata: Codable {
    /// Duration of the audio in seconds
    var durationSeconds: Double

    /// Number of tokens used (if available from API)
    var tokensUsed: Int?

    /// Estimated cost in USD (Grok Voice API: $0.05 per minute)
    var costUSD: Double?

    init(durationSeconds: Double, tokensUsed: Int? = nil) {
        self.durationSeconds = durationSeconds
        self.tokensUsed = tokensUsed
        // Calculate cost: $0.05 per minute
        self.costUSD = (durationSeconds / 60.0) * 0.05
    }
}
