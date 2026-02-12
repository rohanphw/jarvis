import SwiftUI
import SwiftData

/// Detailed view of a single conversation
///
/// Shows:
/// - Full message transcript
/// - Export and share options
/// - Message timestamps
struct ConversationDetailView: View {
    @Environment(\.modelContext) private var modelContext
    let conversation: Conversation

    @State private var showShareSheet = false
    @State private var exportText = ""

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                // Header info
                VStack(alignment: .leading, spacing: 8) {
                    Text(conversation.title)
                        .font(.title2.bold())

                    HStack(spacing: 12) {
                        Label(
                            conversation.timestamp.formatted(date: .long, time: .shortened),
                            systemImage: "clock"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)

                        Label(formatDuration(conversation.duration), systemImage: "timer")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Label(
                            conversation.mode == .glasses ? "Glasses" : "iPhone",
                            systemImage: conversation.mode == .glasses ? "eyeglasses" : "iphone"
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }

                    if conversation.totalCostUSD > 0 {
                        Text("Cost: $\(conversation.totalCostUSD, specifier: "%.4f")")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color(.systemGray6).opacity(0.2))
                .cornerRadius(12)

                Divider()

                // Messages
                ForEach(conversation.messages) { message in
                    MessageDetailRow(message: message)
                }
                }
                .padding()
            }
        }
        .navigationTitle("Conversation")
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: shareConversation) {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = createShareURL() {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Actions

    private func shareConversation() {
        let repository = ConversationRepository(modelContext: modelContext)
        exportText = repository.exportConversation(conversation)
        showShareSheet = true
    }

    private func createShareURL() -> URL? {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("\(conversation.title).md")

        do {
            try exportText.write(to: fileURL, atomically: true, encoding: .utf8)
            return fileURL
        } catch {
            print("[ConversationDetail] Failed to create temp file: \(error)")
            return nil
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Message Detail Row

struct MessageDetailRow: View {
    let message: Message

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            // Avatar
            Circle()
                .fill(message.role == .user ? Color.blue.gradient : Color.purple.gradient)
                .frame(width: 40, height: 40)
                .overlay {
                    Image(systemName: message.role == .user ? "person.fill" : "brain")
                        .font(.caption)
                        .foregroundColor(.white)
                }

            VStack(alignment: .leading, spacing: 8) {
                // Role and time
                HStack {
                    Text(message.role == .user ? "You" : "Jarvis")
                        .font(.subheadline.bold())

                    Spacer()

                    Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                // Text content
                Text(message.content)
                    .font(.body)
                    .fixedSize(horizontal: false, vertical: true)

                // Audio metadata (if available)
                if let audio = message.audioMetadata {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        Text("\(audio.durationSeconds, specifier: "%.1f")s")
                            .font(.caption2)
                            .foregroundColor(.secondary)

                        if let cost = audio.costUSD {
                            Text("•")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("$\(cost, specifier: "%.4f")")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
            }
        }
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: Conversation.self, Message.self, configurations: config)

    let conversation = Conversation(title: "Sample Conversation", mode: .glasses)
    let message1 = Message(role: .user, content: "What is this building?")
    let message2 = Message(role: .assistant, content: "That appears to be a modern office building with glass facades.")

    message1.conversation = conversation
    message2.conversation = conversation
    conversation.messages = [message1, message2]

    container.mainContext.insert(conversation)

    return NavigationStack {
        ConversationDetailView(conversation: conversation)
            .modelContainer(container)
    }
}
