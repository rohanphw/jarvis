import SwiftUI
import SwiftData

/// Container view for streaming session
///
/// Manages the entire streaming lifecycle:
/// - Video display (30 FPS from glasses or iPhone)
/// - Chat overlay with transcripts
/// - Controls (stop, photo, settings)
struct StreamSessionView: View {
    @EnvironmentObject private var wearablesViewModel: WearablesViewModel
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let mode: StreamingMode

    @State private var streamViewModel: StreamSessionViewModel?
    @StateObject private var chatViewModel: ChatViewModel

    @State private var showSaveDialog = false
    @State private var showSettingsSheet = false
    @State private var isSessionStopped = false

    init(mode: StreamingMode) {
        self.mode = mode
        // StreamViewModel will be initialized in onAppear with shared WearablesService
        // ChatViewModel will be initialized properly with modelContext in onAppear
        _chatViewModel = StateObject(wrappedValue: ChatViewModel(modelContext: nil))
    }

    var body: some View {
        Group {
            if let streamViewModel = streamViewModel {
                streamContent(streamViewModel: streamViewModel)
            } else {
                // Loading until streamViewModel is initialized
                Color.black
                    .ignoresSafeArea()
                    .overlay {
                        ProgressView()
                            .scaleEffect(1.5)
                            .tint(.white)
                    }
            }
        }
        .statusBar(hidden: true)
        .onAppear {
            // Initialize streamViewModel with shared WearablesService
            streamViewModel = StreamSessionViewModel(
                streamingService: nil,
                wearablesService: wearablesViewModel.wearablesService
            )

            // Initialize chatViewModel with modelContext
            chatViewModel.initialize(modelContext: modelContext)

            // Setup callbacks
            setupCallbacks()

            // Start streaming
            Task {
                await startSession()
            }
        }
        .onDisappear {
            // Only stop if not already stopped
            if !isSessionStopped {
                Task {
                    await stopSession()
                }
            }
        }
        .confirmationDialog("Save Conversation?", isPresented: $showSaveDialog) {
            Button("Save") {
                Task {
                    chatViewModel.saveConversation()
                    await stopSession()
                    dismiss()
                }
            }
            Button("Don't Save", role: .destructive) {
                Task {
                    chatViewModel.discardConversation()
                    await stopSession()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Would you like to save this conversation to your history?")
        }
        .sheet(isPresented: $showSettingsSheet) {
            SessionSettingsView()
        }
        .alert("Error", isPresented: Binding(
            get: { streamViewModel?.showError ?? false },
            set: { if !$0 { streamViewModel?.dismissError() } }
        )) {
            Button("OK") {
                streamViewModel?.dismissError()
            }
        } message: {
            if let error = streamViewModel?.errorMessage {
                Text(error)
            }
        }
    }

    @ViewBuilder
    private func streamContent(streamViewModel: StreamSessionViewModel) -> some View {
        VStack(spacing: 0) {
            // Top Half: Video Feed
            ZStack {
                if let frame = streamViewModel.currentVideoFrame {
                    Image(uiImage: frame)
                        .resizable()
                        .interpolation(.none) // Faster rendering, no anti-aliasing overhead
                        .aspectRatio(contentMode: .fill)
                        .frame(maxWidth: .infinity)
                        .clipped()
                        .drawingGroup() // GPU acceleration for smoother rendering
                } else {
                    // Loading state
                    Color.black
                        .overlay {
                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)
                                    .tint(.white)

                                Text(streamViewModel.isWaitingForDevice ? "Waiting for device..." : "Starting stream...")
                                    .foregroundColor(.white)
                                    .font(.headline)
                            }
                        }
                }

                // Refined status overlay
                VStack {
                    HStack(spacing: 10) {
                        // Minimal status indicators
                        HStack(spacing: 6) {
                            Circle()
                                .fill(streamViewModel.isStreaming ? Color.green : Color.white.opacity(0.3))
                                .frame(width: 4, height: 4)

                            Text(mode == .glasses ? "Glasses" : "iPhone")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                                )
                        )

                        HStack(spacing: 6) {
                            Circle()
                                .fill(chatViewModel.isActive ? Color.green : Color.white.opacity(0.3))
                                .frame(width: 4, height: 4)

                            Text("Claude")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.9))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(
                            Capsule()
                                .fill(.ultraThinMaterial)
                                .overlay(
                                    Capsule()
                                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                                )
                        )

                        Spacer()

                        // Minimal controls
                        HStack(spacing: 8) {
                            if mode == .glasses {
                                Button(action: { streamViewModel.capturePhoto() }) {
                                    Image(systemName: "camera")
                                        .font(.system(size: 16, weight: .medium))
                                        .foregroundColor(.white.opacity(0.9))
                                        .frame(width: 36, height: 36)
                                        .background(
                                            Circle()
                                                .fill(.ultraThinMaterial)
                                                .overlay(
                                                    Circle()
                                                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                                                )
                                        )
                                }
                                .disabled(!streamViewModel.isStreaming)
                            }

                            Button(action: { showSettingsSheet = true }) {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 16, weight: .medium))
                                    .foregroundColor(.white.opacity(0.9))
                                    .frame(width: 36, height: 36)
                                    .background(
                                        Circle()
                                            .fill(.ultraThinMaterial)
                                            .overlay(
                                                Circle()
                                                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 0.5)
                                            )
                                    )
                            }
                        }
                    }
                    .padding(16)

                    Spacer()
                }
            }
            .frame(height: UIScreen.main.bounds.height / 2)

            // Bottom Half: Conversation Bubbles
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Messages ScrollView
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(spacing: 16) {
                                if chatViewModel.userTranscript.isEmpty && chatViewModel.assistantTranscript.isEmpty {
                                    // Empty state
                                    VStack(spacing: 12) {
                                        Image(systemName: "waveform")
                                            .font(.system(size: 48))
                                            .foregroundColor(.gray.opacity(0.5))

                                        Text("Start talking to Jarvis")
                                            .font(.headline)
                                            .foregroundColor(.gray)
                                    }
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                                    .padding(.top, 60)
                                } else {
                                    // User message
                                    if !chatViewModel.userTranscript.isEmpty {
                                        MessageBubbleView(
                                            text: chatViewModel.userTranscript,
                                            isUser: true
                                        )
                                        .equatable()
                                        .id("user")
                                    }

                                    // Assistant message
                                    if !chatViewModel.assistantTranscript.isEmpty {
                                        MessageBubbleView(
                                            text: chatViewModel.assistantTranscript,
                                            isUser: false,
                                            isTyping: chatViewModel.isAssistantSpeaking
                                        )
                                        .equatable()
                                        .id("assistant")
                                    }
                                }
                            }
                            .padding()
                        }
                        .onChange(of: chatViewModel.assistantTranscript) { _, _ in
                            withAnimation {
                                proxy.scrollTo("assistant", anchor: .bottom)
                            }
                        }
                    }

                    // Bottom bar with stop button
                    HStack {
                        Spacer()

                        Button(action: { showSaveDialog = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "stop.fill")
                                Text("End Session")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(colors: [.red, .red.opacity(0.8)], startPoint: .leading, endPoint: .trailing)
                            )
                            .cornerRadius(25)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color.black.opacity(0.8))
                }
            }
        }
        .background(Color.black)
    }

    // MARK: - Session Lifecycle

    private func startSession() async {
        guard let streamViewModel = streamViewModel else { return }

        // Set mode
        streamViewModel.streamingMode = mode

        print("[StreamSessionView] 🚀 Starting session (parallel initialization)...")

        // Start streaming and chat in parallel for faster startup
        async let streamingTask: Void = streamViewModel.startStreaming()
        async let chatTask: Void = {
            do {
                try await chatViewModel.startSession(mode: mode)
            } catch {
                await MainActor.run {
                    streamViewModel.showError("Failed to start chat: \(error.localizedDescription)")
                }
            }
        }()

        // Wait for both to complete
        _ = await (streamingTask, chatTask)

        print("[StreamSessionView] ✅ Session fully started")
    }

    private func stopSession() async {
        guard let streamViewModel = streamViewModel else { return }
        guard !isSessionStopped else { return }  // Prevent double-stop

        isSessionStopped = true
        print("[StreamSessionView] ⏹️ Stopping session...")

        await chatViewModel.stopSession()
        await streamViewModel.stopStreaming()

        print("[StreamSessionView] ✅ Session stopped")
    }

    // MARK: - Setup Callbacks

    private func setupCallbacks() {
        guard let streamViewModel = streamViewModel else { return }

        // Send throttled frames to chat
        streamViewModel.onFrameForLLM = { [weak chatViewModel] image in
            chatViewModel?.processVideoFrame(image)
        }

        // Handle photo captures with AI description
        streamViewModel.onPhotoCaptured = { [weak chatViewModel] image in
            chatViewModel?.processPhotoCaptureWithDescription(image)
        }
    }
}

// MARK: - Message Bubble

struct MessageBubbleView: View, Equatable {
    let text: String
    let isUser: Bool
    var isTyping: Bool = false

    static func == (lhs: MessageBubbleView, rhs: MessageBubbleView) -> Bool {
        lhs.text == rhs.text && lhs.isUser == rhs.isUser && lhs.isTyping == rhs.isTyping
    }

    var body: some View {
        HStack {
            if isUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: isUser ? .trailing : .leading, spacing: 3) {
                Text(isUser ? "You" : "Jarvis")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.5))

                Text(text)
                    .font(.system(size: 15))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(isUser ? Color.white.opacity(0.15) : Color.white.opacity(0.08))
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
                            )
                    )

                if !isUser && isTyping {
                    HStack(spacing: 4) {
                        ForEach(0..<3) { index in
                            Circle()
                                .fill(Color.gray)
                                .frame(width: 6, height: 6)
                                .opacity(0.6)
                        }
                    }
                    .padding(.leading, 16)
                }
            }

            if !isUser {
                Spacer(minLength: 60)
            }
        }
    }
}


// MARK: - Chat Overlay

struct ChatOverlayView: View {
    let userTranscript: String
    let assistantTranscript: String
    let isAssistantSpeaking: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !userTranscript.isEmpty {
                TranscriptBubble(text: userTranscript, isUser: true)
            }

            if !assistantTranscript.isEmpty {
                TranscriptBubble(text: assistantTranscript, isUser: false)
            }

            if isAssistantSpeaking {
                VoiceIndicatorView()
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.black.opacity(0.7))
                .blur(radius: 10)
        )
    }
}

// MARK: - Transcript Bubble

struct TranscriptBubble: View {
    let text: String
    let isUser: Bool

    var body: some View {
        HStack(spacing: 8) {
            if isUser {
                Image(systemName: "person.fill")
                    .font(.caption)
                    .foregroundColor(.blue)
            } else {
                Image(systemName: "brain")
                    .font(.caption)
                    .foregroundColor(.purple)
            }

            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

// MARK: - Voice Indicator

struct VoiceIndicatorView: View {
    @State private var animating = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<4) { index in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.purple)
                    .frame(width: 3, height: animating ? 20 : 10)
                    .animation(
                        .easeInOut(duration: 0.5)
                            .repeatForever()
                            .delay(Double(index) * 0.1),
                        value: animating
                    )
            }

            Text("Speaking...")
                .font(.caption)
                .foregroundColor(.white)
                .padding(.leading, 8)
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Session Settings

struct SessionSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Audio") {
                    // Placeholder for audio settings
                    Text("Audio settings coming soon")
                        .foregroundColor(.secondary)
                }

                Section("Video") {
                    // Placeholder for video settings
                    Text("Video quality settings coming soon")
                        .foregroundColor(.secondary)
                }
            }
            .navigationTitle("Session Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    StreamSessionView(mode: .glasses)
        .environmentObject(WearablesViewModel())
        .modelContainer(for: [Conversation.self, Message.self])
}
