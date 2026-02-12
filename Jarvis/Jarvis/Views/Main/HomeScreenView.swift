import SwiftUI
import SwiftData

/// Redesigned minimal home screen
struct HomeScreenView: View {
    @EnvironmentObject private var wearablesViewModel: WearablesViewModel
    @Environment(\.modelContext) private var modelContext

    @State private var showStreamingView = false
    @State private var showHistoryView = false
    @State private var showSettingsSheet = false
    @State private var showAPIKeySetup = false
    @State private var selectedMode: StreamingMode = .glasses
    @State private var hasAPIKey: Bool = false

    // Computed properties
    private var isFullyReady: Bool {
        wearablesViewModel.hasActiveDevice && hasAPIKey
    }

    private var statusText: String {
        if !hasAPIKey {
            return "API Key Required"
        } else if !wearablesViewModel.hasActiveDevice {
            return "Device Disconnected"
        } else {
            return "Ready"
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                // Subtle gradient background
                LinearGradient(
                    colors: [
                        Color(red: 0.05, green: 0.05, blue: 0.12),
                        Color(red: 0.02, green: 0.02, blue: 0.08)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                if hasAPIKey {
                    mainContent
                } else {
                    setupRequiredView
                }
            }
            .preferredColorScheme(.dark)
            .onAppear {
                checkAPIKey()
            }
            .sheet(isPresented: $showAPIKeySetup) {
                APIKeySetupView {
                    showAPIKeySetup = false
                    checkAPIKey()
                }
            }
            .sheet(isPresented: $showSettingsSheet) {
                SettingsView()
                    .environmentObject(wearablesViewModel)
            }
            .fullScreenCover(isPresented: $showStreamingView) {
                StreamSessionView(mode: selectedMode)
                    .environmentObject(wearablesViewModel)
            }
            .navigationDestination(isPresented: $showHistoryView) {
                ConversationHistoryView()
            }
        }
    }

    // MARK: - Main Content

    private var mainContent: some View {
        ScrollView(showsIndicators: false) {
            VStack(spacing: 28) {
                Spacer()
                    .frame(height: 60)

                // Minimal header
                VStack(spacing: 20) {
                    Text("JARVIS")
                        .font(.system(size: 28, weight: .light, design: .default))
                        .foregroundColor(.white)
                        .kerning(4)

                    // Status indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(isFullyReady ? Color.green : Color.white.opacity(0.3))
                            .frame(width: 4, height: 4)

                        Text(statusText)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                            .textCase(.uppercase)
                            .kerning(1)
                    }
                }

                Spacer()
                    .frame(height: 40)

                // Primary action
                Button(action: { startStreaming(mode: .glasses) }) {
                    VStack(spacing: 10) {
                        Image(systemName: "eyeglasses")
                            .font(.system(size: 24, weight: .ultraLight))
                            .foregroundColor(.white)

                        Text("Start Session")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 32)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(.ultraThinMaterial)
                            .overlay(
                                RoundedRectangle(cornerRadius: 16)
                                    .strokeBorder(
                                        LinearGradient(
                                            colors: [
                                                Color.white.opacity(0.2),
                                                Color.white.opacity(0.05)
                                            ],
                                            startPoint: .topLeading,
                                            endPoint: .bottomTrailing
                                        ),
                                        lineWidth: 1
                                    )
                            )
                    )
                }
                .disabled(!wearablesViewModel.hasActiveDevice)
                .padding(.horizontal, 32)

                // iPhone fallback
                if Constants.Features.enableIPhoneFallback {
                    Button(action: { startStreaming(mode: .iPhone) }) {
                        HStack(spacing: 10) {
                            Image(systemName: "iphone")
                                .font(.system(size: 13))

                            Text("Use iPhone Camera")
                                .font(.system(size: 13, weight: .medium))

                            Spacer()

                            Image(systemName: "arrow.right")
                                .font(.system(size: 11))
                        }
                        .foregroundColor(.white.opacity(0.6))
                        .padding(14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color.white.opacity(0.03))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                                )
                        )
                    }
                    .padding(.horizontal, 32)
                }

                Spacer()
                    .frame(height: 20)

                // Quick actions
                HStack(spacing: 12) {
                    QuickActionTile(
                        icon: "clock.arrow.circlepath",
                        title: "History"
                    ) {
                        showHistoryView = true
                    }

                    QuickActionTile(
                        icon: "key",
                        title: "API Key"
                    ) {
                        showAPIKeySetup = true
                    }

                    QuickActionTile(
                        icon: "gearshape",
                        title: "Settings"
                    ) {
                        showSettingsSheet = true
                    }
                }
                .padding(.horizontal, 32)

                // Recent conversations
                CleanRecentConversationsSection(modelContext: modelContext)
                    .padding(.horizontal, 32)

                Spacer()
                    .frame(height: 40)
            }
        }
    }

    // MARK: - Setup Required View

    private var setupRequiredView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "key.fill")
                .font(.system(size: 40, weight: .ultraLight))
                .foregroundColor(.white.opacity(0.6))

            VStack(spacing: 8) {
                Text("API Key Required")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(.white)

                Text("Add your Anthropic API key to continue")
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
            }

            Button(action: { showAPIKeySetup = true }) {
                Text("Setup")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 140)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.15))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Actions

    private func startStreaming(mode: StreamingMode) {
        selectedMode = mode
        showStreamingView = true
    }

    private func checkAPIKey() {
        if let key = KeychainManager.shared.getAnthropicKey(), !key.isEmpty {
            hasAPIKey = true
        } else if !Constants.Claude.apiKey.isEmpty && Constants.Claude.apiKey != "YOUR_ANTHROPIC_API_KEY" {
            hasAPIKey = true
        } else {
            hasAPIKey = false
        }
    }
}

// MARK: - Quick Action Tile

struct QuickActionTile: View {
    let icon: String
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .light))
                    .foregroundColor(.white.opacity(0.7))
                    .frame(height: 24)

                Text(title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.6))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
                    )
            )
        }
    }
}

// MARK: - Glass Card Container

struct GlassCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(.ultraThinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color.white.opacity(0.04))
                        )

                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.15),
                                    Color.white.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ),
                            lineWidth: 1
                        )
                }
            )
    }
}

// MARK: - Clean Recent Conversations

struct CleanRecentConversationsSection: View {
    let modelContext: ModelContext
    @State private var recentConversations: [Conversation] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Recent")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))

                Spacer()

                if !recentConversations.isEmpty {
                    NavigationLink(destination: ConversationHistoryView()) {
                        Text("View All")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            }

            if recentConversations.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "bubble.left.and.bubble.right")
                        .font(.system(size: 28, weight: .ultraLight))
                        .foregroundColor(.white.opacity(0.3))
                        .padding(.top, 16)

                    Text("No conversations yet")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.5))

                    Text("Start your first session")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.4))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.white.opacity(0.02))
                )
            } else {
                VStack(spacing: 10) {
                    ForEach(recentConversations.prefix(3)) { conversation in
                        NavigationLink(destination: ConversationDetailView(conversation: conversation)) {
                            CleanConversationRow(conversation: conversation)
                        }
                    }
                }
            }
        }
        .onAppear {
            loadRecentConversations()
        }
    }

    private func loadRecentConversations() {
        let repository = ConversationRepository(modelContext: modelContext)
        recentConversations = repository.fetchRecentConversations(limit: 3)
    }
}

// MARK: - Clean Conversation Row

struct CleanConversationRow: View {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: conversation.mode == .glasses ? "eyeglasses" : "iphone")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white.opacity(0.6))
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.05))
                .cornerRadius(8)

            VStack(alignment: .leading, spacing: 3) {
                Text(conversation.title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(conversation.timestamp.formatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 10))

                    Text("•")
                        .font(.system(size: 10))

                    Text("\(conversation.messageCount) msgs")
                        .font(.system(size: 10))
                }
                .foregroundColor(.white.opacity(0.5))
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.3))
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.white.opacity(0.05), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

#Preview {
    HomeScreenView()
        .environmentObject(WearablesViewModel())
        .modelContainer(for: [Conversation.self, Message.self])
}
