import Foundation
import Combine
import SwiftUI
import SwiftData

/// ViewModel orchestrating voice chat with Claude AI
///
/// This is the conductor that wires together:
/// - Video frames from StreamingService
/// - Speech recognition (iOS SFSpeech)
/// - Claude Vision API
/// - Text-to-speech (iOS AVSpeech)
/// - Conversation persistence via ConversationRepository
@MainActor
class ChatViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Whether chat session is active
    @Published var isActive: Bool = false

    /// Current user transcript (real-time)
    @Published var userTranscript: String = ""

    /// Current assistant transcript (real-time)
    @Published var assistantTranscript: String = ""

    /// Whether Jarvis is currently speaking
    @Published var isAssistantSpeaking: Bool = false

    // MARK: - Private Properties

    private var modelContext: ModelContext?
    private var repository: ConversationRepository?
    private var currentConversation: Conversation?
    private var sessionStartTime: Date?

    // Services
    private let claudeService: ClaudeVisionService
    private let speechRecognition: SpeechRecognitionManager
    private let textToSpeech: TextToSpeechManager

    // Frame management
    private var lastVideoFrame: UIImage?
    private var isProcessingQuery: Bool = false

    // Message pending storage
    private var pendingUserMessage: String?

    // MARK: - Initialization

    init(modelContext: ModelContext?) {
        self.modelContext = modelContext
        if let context = modelContext {
            self.repository = ConversationRepository(modelContext: context)
        }

        // Initialize services
        self.claudeService = ClaudeVisionService()
        self.speechRecognition = SpeechRecognitionManager()
        self.textToSpeech = TextToSpeechManager()

        // Setup callbacks
        setupCallbacks()
    }

    /// Initialize with modelContext (called from view onAppear)
    func initialize(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.repository = ConversationRepository(modelContext: modelContext)
    }

    // MARK: - Setup Callbacks

    private func setupCallbacks() {
        // Speech recognition callbacks
        speechRecognition.onSpeechStart = { [weak self] in
            Task { @MainActor in
                self?.userTranscript = ""
                print("[ChatViewModel] 🎤 User started speaking")
            }
        }

        speechRecognition.onTranscriptUpdate = { [weak self] transcript in
            Task { @MainActor in
                self?.userTranscript = transcript
            }
        }

        speechRecognition.onSpeechEnd = { [weak self] transcript in
            guard let self = self else { return }
            Task { @MainActor in
                self.userTranscript = transcript
                self.pendingUserMessage = transcript
                print("[ChatViewModel] 👤 User: \(transcript)")

                // Process query with Claude
                await self.processUserQuery(transcript)
            }
        }

        speechRecognition.onError = { [weak self] error in
            print("[ChatViewModel] ❌ Speech recognition error: \(error)")
        }

        // Claude callbacks
        claudeService.onResponseUpdate = { [weak self] response in
            Task { @MainActor in
                self?.assistantTranscript = response
            }
        }

        claudeService.onResponseComplete = { [weak self] response in
            guard let self = self else { return }
            Task { @MainActor in
                self.assistantTranscript = response
                print("[ChatViewModel] 🤖 Claude: \(response)")

                // Store messages
                if let pending = self.pendingUserMessage, !pending.isEmpty {
                    self.storeUserMessage(content: pending)
                    self.pendingUserMessage = nil
                }

                self.storeAssistantMessage(content: response)

                // Speak response
                self.textToSpeech.speak(response)
            }
        }

        claudeService.onError = { [weak self] error in
            print("[ChatViewModel] ❌ Claude error: \(error)")
        }

        // TTS callbacks
        textToSpeech.onSpeechStart = { [weak self] in
            Task { @MainActor in
                self?.isAssistantSpeaking = true
                print("[ChatViewModel] 🔊 Jarvis started speaking")
            }
        }

        textToSpeech.onSpeechFinish = { [weak self] in
            Task { @MainActor in
                self?.isAssistantSpeaking = false
                self?.assistantTranscript = ""
                self?.isProcessingQuery = false

                // Ready for next question
                print("[ChatViewModel] ✅ Ready for next query")
            }
        }

        print("[ChatViewModel] ✅ Callbacks configured")
    }

    // MARK: - Session Lifecycle

    /// Start chat session with Claude
    func startSession(mode: StreamingMode) async throws {
        print("[ChatViewModel] 🚀 Starting session in \(mode.rawValue) mode")

        // Create new conversation
        guard let repo = repository else {
            throw ChatError.repositoryNotInitialized
        }

        currentConversation = repo.createConversation(mode: mode)
        sessionStartTime = Date()

        // Request speech recognition permission
        let granted = await speechRecognition.requestPermission()
        guard granted else {
            throw ChatError.speechPermissionDenied
        }

        // Start services
        claudeService.start()

        // Start listening
        try speechRecognition.startListening()

        isActive = true
        print("[ChatViewModel] ✅ Session started")
    }

    /// Stop chat session without saving
    func stopSession() async {
        print("[ChatViewModel] ⏹️ Stopping session (not saving)")

        // Stop services
        speechRecognition.stopListening()
        textToSpeech.stop()
        claudeService.stop()

        isActive = false

        print("[ChatViewModel] ✅ Session stopped")
    }

    /// Save the current conversation
    func saveConversation() {
        print("[ChatViewModel] 💾 Saving conversation")

        // Store any pending messages
        if let pending = pendingUserMessage, !pending.isEmpty {
            storeUserMessage(content: pending)
            pendingUserMessage = nil
        }

        if !assistantTranscript.isEmpty {
            storeAssistantMessage(content: assistantTranscript)
        }

        // Finalize conversation duration
        if let conversation = currentConversation,
           let startTime = sessionStartTime {
            conversation.duration = Date().timeIntervalSince(startTime)
        }

        print("[ChatViewModel] ✅ Conversation saved")
    }

    /// Discard the current conversation
    func discardConversation() {
        print("[ChatViewModel] 🗑️ Discarding conversation")

        // Delete the conversation from repository
        if let conversation = currentConversation,
           let repo = repository {
            repo.deleteConversation(conversation)
        }

        // Clear state
        currentConversation = nil
        sessionStartTime = nil
        userTranscript = ""
        assistantTranscript = ""
        pendingUserMessage = nil

        print("[ChatViewModel] ✅ Conversation discarded")
    }

    // MARK: - Frame Handling

    /// Process video frame from streaming service
    func processVideoFrame(_ image: UIImage) {
        // Store latest frame for vision queries
        lastVideoFrame = image
    }

    /// Process captured photo and get AI description
    func processPhotoCaptureWithDescription(_ image: UIImage) {
        print("[ChatViewModel] 📸 Photo captured, requesting AI description...")

        Task {
            do {
                try await claudeService.sendVisionMessage(
                    text: "Describe what you see in this image in detail.",
                    image: image
                )
            } catch {
                print("[ChatViewModel] ❌ Failed to process photo: \(error)")
            }
        }
    }

    // MARK: - Query Processing

    private func processUserQuery(_ text: String) async {
        guard !isProcessingQuery else {
            print("[ChatViewModel] ⚠️ Already processing a query, skipping...")
            return
        }

        isProcessingQuery = true

        do {
            // If we have a recent video frame, send vision query
            if let frame = lastVideoFrame {
                try await claudeService.sendVisionMessage(text: text, image: frame)
            } else {
                // Text-only query
                try await claudeService.sendTextMessage(text)
            }
        } catch {
            print("[ChatViewModel] ❌ Query processing error: \(error)")
            isProcessingQuery = false
        }
    }

    // MARK: - Message Storage

    /// Store user message
    private func storeUserMessage(content: String) {
        guard let conversation = currentConversation,
              let repo = repository else {
            return
        }

        // TODO: Add snapshot storage when Message model is updated
        repo.addMessage(
            to: conversation,
            role: MessageRole.user,
            content: content
        )

        print("[ChatViewModel] 💾 User message stored")
    }

    /// Store assistant response
    private func storeAssistantMessage(content: String) {
        guard let conversation = currentConversation,
              let repo = repository else {
            return
        }

        repo.addMessage(
            to: conversation,
            role: MessageRole.assistant,
            content: content
        )

        print("[ChatViewModel] 💾 Assistant message stored")
    }
}

// MARK: - Errors

enum ChatError: LocalizedError {
    case repositoryNotInitialized
    case sessionNotActive
    case speechPermissionDenied
    case claudeConnectionFailed

    var errorDescription: String? {
        switch self {
        case .repositoryNotInitialized:
            return "Conversation repository not initialized"
        case .sessionNotActive:
            return "No active chat session"
        case .speechPermissionDenied:
            return "Speech recognition permission denied"
        case .claudeConnectionFailed:
            return "Failed to connect to Claude API"
        }
    }
}
