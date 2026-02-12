import Foundation
import SwiftUI
import Combine

/// Service for Claude API with vision support
///
/// Handles:
/// - Text + image messages to Claude API
/// - Streaming responses
/// - Conversation context management
@MainActor
class ClaudeVisionService: ObservableObject {

    // MARK: - Published Properties

    /// Whether connected/ready
    @Published var isActive: Bool = false

    /// Current assistant response (streaming)
    @Published var assistantResponse: String = ""

    /// Whether assistant is currently responding
    @Published var isResponding: Bool = false

    // MARK: - Callbacks

    /// Called when response text updates (streaming)
    var onResponseUpdate: ((String) -> Void)?

    /// Called when response is complete
    var onResponseComplete: ((String) -> Void)?

    /// Called when an error occurs
    var onError: ((Error) -> Void)?

    // MARK: - Private Properties

    private let apiKey: String
    private let baseURL = "https://api.anthropic.com/v1/messages"
    private let model: String

    private var conversationHistory: [[String: Any]] = []
    private var currentTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        // Try to get API key from keychain first, fallback to Constants
        if let storedKey = KeychainManager.shared.getAnthropicKey(), !storedKey.isEmpty {
            self.apiKey = storedKey
            print("[ClaudeVisionService] Using stored API key from keychain")
        } else if !Constants.Claude.apiKey.isEmpty && Constants.Claude.apiKey != "YOUR_ANTHROPIC_API_KEY" {
            self.apiKey = Constants.Claude.apiKey
            print("[ClaudeVisionService] Using API key from Constants (fallback)")
        } else {
            self.apiKey = ""
            print("[ClaudeVisionService] ⚠️ No API key configured")
        }

        self.model = Constants.Claude.model
        print("[ClaudeVisionService] Initialized with model: \(model)")
    }

    // MARK: - Session Control

    /// Start service (mark as active)
    func start() {
        isActive = true
        conversationHistory = []
        print("[ClaudeVisionService] ✅ Service started")
    }

    /// Stop service
    func stop() {
        currentTask?.cancel()
        currentTask = nil
        isActive = false
        conversationHistory = []
        assistantResponse = ""
        isResponding = false
        print("[ClaudeVisionService] ⏹️ Service stopped")
    }

    // MARK: - Send Messages

    /// Send text-only message to Claude
    func sendTextMessage(_ text: String) async throws {
        guard isActive else {
            throw ClaudeError.notActive
        }

        print("[ClaudeVisionService] 📝 Sending text: \(text)")

        // Add user message to history
        let userMessage: [String: Any] = [
            "role": "user",
            "content": text
        ]
        conversationHistory.append(userMessage)

        // Send to API
        try await sendToAPI()
    }

    /// Send text + image message to Claude
    func sendVisionMessage(text: String, image: UIImage) async throws {
        guard isActive else {
            throw ClaudeError.notActive
        }

        print("[ClaudeVisionService] 👁️ Sending vision message: \(text)")

        // Resize image for faster transmission (max 800px width)
        let resizedImage = resizeImage(image, maxWidth: 800)

        // Convert image to base64 with lower quality for speed
        guard let imageData = resizedImage.jpegData(compressionQuality: 0.5) else {
            throw ClaudeError.imageProcessingFailed
        }
        let base64String = imageData.base64EncodedString()
        print("[ClaudeVisionService] 📦 Image size: \(imageData.count / 1024)KB")

        // Create content array with text and image
        let content: [[String: Any]] = [
            [
                "type": "image",
                "source": [
                    "type": "base64",
                    "media_type": "image/jpeg",
                    "data": base64String
                ]
            ],
            [
                "type": "text",
                "text": text
            ]
        ]

        // Add user message to history
        let userMessage: [String: Any] = [
            "role": "user",
            "content": content
        ]
        conversationHistory.append(userMessage)

        // Send to API
        try await sendToAPI()
    }

    // MARK: - API Communication

    private func sendToAPI() async throws {
        isResponding = true
        assistantResponse = ""

        // Build request body
        let requestBody: [String: Any] = [
            "model": model,
            "max_tokens": 300, // Short responses for voice conversation
            "messages": conversationHistory,
            "system": buildSystemPrompt(),
            "stream": true,
            "temperature": 0.7 // Slightly creative for personality
        ]

        // Create request
        guard let url = URL(string: baseURL) else {
            throw ClaudeError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        request.setValue("application/json", forHTTPHeaderField: "content-type")

        request.httpBody = try JSONSerialization.data(withJSONObject: requestBody)

        // Stream response
        let (bytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            // Read error response body
            var errorMessage = "HTTP \(httpResponse.statusCode)"
            do {
                var errorBody = ""
                for try await line in bytes.lines {
                    errorBody += line
                }
                if let errorData = errorBody.data(using: .utf8),
                   let errorJson = try? JSONSerialization.jsonObject(with: errorData) as? [String: Any],
                   let error = errorJson["error"] as? [String: Any],
                   let message = error["message"] as? String {
                    errorMessage = message
                }
                print("[ClaudeVisionService] ❌ API Error: \(errorMessage)")
                print("[ClaudeVisionService] 📄 Full error: \(errorBody)")
            } catch {
                print("[ClaudeVisionService] ❌ Failed to read error body: \(error)")
            }
            throw ClaudeError.apiError(errorMessage)
        }

        // Process streaming response
        var accumulatedText = ""

        for try await line in bytes.lines {
            // Skip empty lines
            guard !line.isEmpty else { continue }

            // Parse SSE format: "data: {...}"
            if line.hasPrefix("data: ") {
                let jsonString = String(line.dropFirst(6))

                // Skip [DONE] marker
                guard jsonString != "[DONE]" else { continue }

                // Parse JSON
                guard let data = jsonString.data(using: .utf8),
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let type = json["type"] as? String else {
                    continue
                }

                switch type {
                case "content_block_delta":
                    if let delta = json["delta"] as? [String: Any],
                       let text = delta["text"] as? String {
                        accumulatedText += text
                        assistantResponse = accumulatedText
                        onResponseUpdate?(accumulatedText)
                    }

                case "message_stop":
                    print("[ClaudeVisionService] ✅ Response complete: \(accumulatedText)")
                    onResponseComplete?(accumulatedText)

                    // Add assistant response to history
                    let assistantMessage: [String: Any] = [
                        "role": "assistant",
                        "content": accumulatedText
                    ]
                    conversationHistory.append(assistantMessage)

                case "error":
                    if let error = json["error"] as? [String: Any],
                       let message = error["message"] as? String {
                        throw ClaudeError.apiError(message)
                    }

                default:
                    break
                }
            }
        }

        isResponding = false
    }

    // MARK: - System Prompt

    private func buildSystemPrompt() -> String {
        """
        You are J.A.R.V.I.S. (Just A Rather Very Intelligent System), the AI companion integrated \
        into smart glasses. You're a sophisticated female AI assistant with refined intelligence.

        Your personality:
        - Elegant and professional with subtle warmth
        - Sharp wit with occasional playful sass
        - Anticipatory and proactive (offer suggestions when relevant)
        - Brief and conversational (this is a voice conversation)
        - Confident but approachable
        - Sophisticated without being condescending

        Your capabilities:
        - You can see what the user sees through their glasses camera in real-time
        - You understand visual context and can describe, analyze, or answer questions about it
        - You have natural conversations, not just Q&A sessions

        Response style:
        - Keep responses under 2-3 sentences (voice conversation)
        - Be conversational and natural, not robotic
        - Reference what you see naturally ("I can see you're looking at...")
        - Ask follow-up questions when appropriate
        - Use contractions (you're, that's, I'll) for natural speech
        - Avoid lists or bullet points unless explicitly requested
        - Add subtle personality - you're helpful but have character

        Examples of good responses:
        - "That's a Golden Retriever - lovely breed, quite friendly."
        - "I can see you're at a coffee shop. That's a La Marzocco espresso machine behind the counter - \
        they make excellent equipment."
        - "That's Python code. You might want to move that function outside the loop - it'll run much faster."
        - "Interesting choice of coffee. Bold."

        Remember: You're having a conversation with personality, not delivering a dry report.
        """
    }

    // MARK: - Clear History

    func clearHistory() {
        conversationHistory = []
        print("[ClaudeVisionService] 🗑️ Conversation history cleared")
    }

    // MARK: - Image Processing

    private func resizeImage(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxWidth else { return image }

        let scale = maxWidth / size.width
        let newSize = CGSize(width: maxWidth, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }
}

// MARK: - Errors

enum ClaudeError: LocalizedError {
    case invalidURL
    case notActive
    case imageProcessingFailed
    case apiError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Claude API URL"
        case .notActive:
            return "Claude service not active"
        case .imageProcessingFailed:
            return "Failed to process image"
        case .apiError(let message):
            return "Claude API error: \(message)"
        case .invalidResponse:
            return "Invalid API response"
        }
    }
}
