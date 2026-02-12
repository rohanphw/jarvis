import Foundation
import Combine
import UIKit

/// Service managing real-time voice conversations with Grok AI
///
/// Handles:
/// - WebSocket connection to wss://api.x.ai/v1/realtime
/// - Bidirectional audio streaming (PCM Int16)
/// - Server-side voice activity detection (VAD)
/// - Real-time transcripts
/// - Video frame injection
@MainActor
class GrokVoiceService: ObservableObject {

    // MARK: - Published Properties

    /// Whether connected to Grok API
    @Published var isConnected: Bool = false

    /// Current user transcript (live updating)
    @Published var userTranscript: String = ""

    /// Current assistant transcript (live updating)
    @Published var assistantTranscript: String = ""

    /// Whether assistant is currently speaking
    @Published var isAssistantSpeaking: Bool = false

    // MARK: - Callbacks

    /// Called when audio data is received from Grok (PCM Int16, 24kHz)
    var onAudioReceived: ((Data) -> Void)?

    /// Called when transcript updates (text, isUser)
    var onTranscriptUpdate: ((String, Bool) -> Void)?

    /// Called when an error occurs
    var onError: ((Error) -> Void)?

    // MARK: - Private Properties

    private var webSocket: URLSessionWebSocketTask?
    private var session: URLSession?
    private var currentSessionID: String?

    // Transcript accumulation
    private var currentUserTranscript: String = ""
    private var currentAssistantTranscript: String = ""

    // Retry logic
    private var maxRetries: Int = 3
    private var currentRetry: Int = 0
    private var reconnectTask: Task<Void, Never>?

    // MARK: - Initialization

    init() {
        print("[GrokVoiceService] Initialized")
    }

    nonisolated deinit {
        // Cancel reconnect task immediately
        reconnectTask?.cancel()

        // Disconnect synchronously to avoid retain cycle
        Task { @MainActor [weak self] in
            self?.disconnect()
        }
    }

    // MARK: - Connection Management

    /// Connect to Grok Voice Agent API with retry logic
    func connectWithRetry() async throws {
        while currentRetry < maxRetries {
            do {
                try await connect()
                currentRetry = 0  // Reset on success
                print("[GrokVoiceService] ✅ Connected successfully")
                return
            } catch {
                currentRetry += 1
                let delay = min(pow(2.0, Double(currentRetry)), 10.0)  // Max 10s

                if currentRetry >= maxRetries {
                    print("[GrokVoiceService] ❌ Max retries (\(maxRetries)) exceeded")
                    throw GrokError.maxRetriesExceeded
                }

                print("[GrokVoiceService] ⚠️ Connection failed (attempt \(currentRetry)/\(maxRetries)), retrying in \(delay)s...")
                try await Task.sleep(for: .seconds(delay))
            }
        }
    }

    /// Connect to Grok Voice Agent API
    func connect() async throws {
        guard !isConnected else {
            print("[GrokVoiceService] ⚠️ Already connected")
            return
        }

        print("[GrokVoiceService] 🔌 Connecting to Grok API...")

        // Build WebSocket URL
        guard let url = URL(string: "\(Constants.Grok.baseURL)?model=\(Constants.Grok.model)") else {
            throw GrokError.invalidURL
        }

        // Configure request with API key
        var request = URLRequest(url: url)
        request.setValue("Bearer \(Constants.Grok.apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("realtime=v1", forHTTPHeaderField: "X-API-Version")

        // Create session and task
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        session = URLSession(configuration: config)

        webSocket = session?.webSocketTask(with: request)
        webSocket?.resume()

        // Start receiving messages
        startReceiving()

        // Send session configuration
        try await sendSessionConfig()

        isConnected = true
        print("[GrokVoiceService] ✅ Connected to Grok API")
    }

    /// Disconnect from Grok API
    func disconnect() {
        print("[GrokVoiceService] 🔌 Disconnecting...")

        // Cancel any pending reconnect attempts
        reconnectTask?.cancel()
        reconnectTask = nil

        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        session?.invalidateAndCancel()
        session = nil

        isConnected = false
        currentSessionID = nil
        currentRetry = 0

        print("[GrokVoiceService] ✅ Disconnected")
    }

    /// Attempt automatic reconnection
    private func attemptReconnect() {
        guard reconnectTask == nil else { return }

        reconnectTask = Task {
            do {
                print("[GrokVoiceService] 🔄 Attempting automatic reconnection...")
                try await Task.sleep(for: .seconds(2))
                try await connectWithRetry()
                print("[GrokVoiceService] ✅ Reconnected successfully")
            } catch {
                print("[GrokVoiceService] ❌ Reconnection failed: \(error)")
                onError?(error)
            }
            reconnectTask = nil
        }
    }

    // MARK: - Session Configuration

    private func sendSessionConfig() async throws {
        let config: [String: Any] = [
            "type": "session.update",
            "session": [
                "instructions": buildSystemPrompt(),
                "voice": "Ara",  // Grok voice: Ara (warm, conversational)
                "turn_detection": [
                    "type": "server_vad"  // Server-side voice activity detection
                ],
                "audio": [
                    "input": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 16000  // 16kHz input from microphone
                        ]
                    ],
                    "output": [
                        "format": [
                            "type": "audio/pcm",
                            "rate": 24000  // 24kHz output to speaker
                        ]
                    ]
                ]
            ]
        ]

        try await sendJSON(config)
        print("[GrokVoiceService] ⚙️ Session configured (Voice: Ara, Server VAD enabled)")
    }

    private func buildSystemPrompt() -> String {
        """
        You are Jarvis, an AI assistant for Meta Ray-Ban smart glasses. Have natural \
        voice conversations with sub-second latency. Be concise, helpful, and conversational. \
        Keep responses very short - this is a live voice conversation, not written text. \
        Answer questions directly without preamble. Be warm and friendly like the voice Ara.
        """
    }

    // MARK: - Send Audio

    /// Send audio chunk to Grok (PCM Int16, 16kHz, mono)
    func sendAudio(data: Data) async throws {
        guard isConnected else {
            throw GrokError.notConnected
        }

        let base64 = data.base64EncodedString()
        try await sendJSON([
            "type": "input_audio_buffer.append",
            "audio": base64
        ])

        print("[GrokVoiceService] 🎤 Sent audio chunk (\(data.count) bytes)")
    }

    // MARK: - Send Image

    /// Send video frame to Grok for vision processing
    /// NOTE: Voice Agent API does NOT support images per official docs
    /// "The API focuses exclusively on audio and text modalities"
    func sendImage(image: UIImage) async throws {
        // Silently skip - Voice Agent API doesn't support vision
        // This prevents WebSocket disconnection from unsupported messages

        // Future: Could integrate separate grok-vision-beta endpoint if needed
        // For now, glasses are used for audio conversation only
    }

    // MARK: - Receive Messages

    private func startReceiving() {
        Task {
            while let webSocket = webSocket, isConnected {
                do {
                    let message = try await webSocket.receive()
                    await handleMessage(message)
                } catch {
                    if isConnected {
                        print("[GrokVoiceService] ❌ Receive error: \(error)")
                        onError?(error)

                        // Mark as disconnected
                        isConnected = false

                        // Attempt automatic reconnection
                        attemptReconnect()
                    }
                    break
                }
            }
        }
    }

    private func handleMessage(_ message: URLSessionWebSocketTask.Message) async {
        guard case .string(let text) = message else { return }
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else { return }

        switch type {
        case "session.created":
            if let session = json["session"] as? [String: Any],
               let id = session["id"] as? String {
                currentSessionID = id
                print("[GrokVoiceService] 🆔 Session created: \(id)")
            }

        case "session.updated":
            print("[GrokVoiceService] ✅ Session configuration confirmed")

        case "response.output_audio.delta", "response.audio.delta":
            // Incoming audio from Grok
            if let audioDelta = json["delta"] as? String,
               let audioData = Data(base64Encoded: audioDelta) {
                onAudioReceived?(audioData)
                isAssistantSpeaking = true
            }

        case "response.output_audio_transcript.delta", "response.audio_transcript.delta":
            // Real-time transcript of Grok's speech
            if let delta = json["delta"] as? String {
                currentAssistantTranscript += delta
                assistantTranscript = currentAssistantTranscript
                onTranscriptUpdate?(currentAssistantTranscript, false)
            }

        case "response.output_audio_transcript.done", "response.audio_transcript.done":
            // Final assistant transcript
            if let transcript = json["transcript"] as? String {
                currentAssistantTranscript = transcript
                assistantTranscript = transcript
                print("[GrokVoiceService] 🤖 Assistant: \(transcript)")
            }

        case "input_audio_buffer.speech_started":
            // User started speaking
            currentUserTranscript = ""
            userTranscript = ""
            print("[GrokVoiceService] 🎤 User speech started")

        case "input_audio_buffer.speech_stopped":
            // User stopped speaking
            print("[GrokVoiceService] 🎤 User speech stopped")

        case "conversation.item.input_audio_transcription.completed":
            // User speech transcription complete
            if let transcript = json["transcript"] as? String {
                currentUserTranscript = transcript
                userTranscript = transcript
                onTranscriptUpdate?(transcript, true)
                print("[GrokVoiceService] 👤 User: \(transcript)")
            }

        case "response.output_audio.done", "response.audio.done":
            // Assistant finished speaking
            isAssistantSpeaking = false
            currentAssistantTranscript = ""  // Reset for next response
            print("[GrokVoiceService] 🤖 Assistant finished speaking")

        case "response.done":
            // Full response cycle complete
            print("[GrokVoiceService] ✅ Response cycle complete")

        case "error":
            if let error = json["error"] as? [String: Any],
               let message = error["message"] as? String {
                print("[GrokVoiceService] ❌ API Error: \(message)")
                onError?(GrokError.apiError(message))
            }

        default:
            // Log unknown message types for debugging
            #if DEBUG
            print("[GrokVoiceService] 📦 Unhandled message type: \(type)")
            #endif
        }
    }

    // MARK: - Helpers

    private func sendJSON(_ dict: [String: Any]) async throws {
        let data = try JSONSerialization.data(withJSONObject: dict)
        guard let jsonString = String(data: data, encoding: .utf8) else {
            throw GrokError.invalidJSON
        }

        let message = URLSessionWebSocketTask.Message.string(jsonString)
        try await webSocket?.send(message)
    }
}

// MARK: - Errors

enum GrokError: LocalizedError {
    case invalidURL
    case notConnected
    case apiError(String)
    case invalidResponse
    case invalidJSON
    case imageProcessingFailed
    case maxRetriesExceeded

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid Grok API URL"
        case .notConnected:
            return "Not connected to Grok API"
        case .apiError(let message):
            return "Grok API Error: \(message)"
        case .invalidResponse:
            return "Invalid response from Grok API"
        case .invalidJSON:
            return "Failed to encode JSON"
        case .imageProcessingFailed:
            return "Failed to process image for Grok"
        case .maxRetriesExceeded:
            return "Failed to connect after multiple attempts. Please check your internet connection and API key."
        }
    }
}
