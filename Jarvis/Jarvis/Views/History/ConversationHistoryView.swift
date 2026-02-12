import SwiftUI
import SwiftData

/// Full conversation history view
///
/// Features:
/// - Search and filter conversations
/// - Sort by date
/// - Swipe to delete
/// - Bulk actions
struct ConversationHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var repository: ConversationRepository?

    @State private var conversations: [Conversation] = []
    @State private var searchText = ""
    @State private var isSearching = false
    @State private var showExportSheet = false
    @State private var exportURL: URL?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                // Search bar
                SearchBar(text: $searchText, isSearching: $isSearching)
                    .padding()

            if conversations.isEmpty {
                // Empty state
                EmptyConversationsView()
            } else {
                // Conversation list
                List {
                    ForEach(conversations) { conversation in
                        NavigationLink(destination: ConversationDetailView(conversation: conversation)) {
                            ConversationRow(conversation: conversation)
                        }
                    }
                    .onDelete(perform: deleteConversations)
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                }
            }
        }
        .navigationTitle("Conversations")
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarBackground(Color.black, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(action: exportAll) {
                        Label("Export All", systemImage: "square.and.arrow.up")
                    }

                    Button(role: .destructive, action: deleteOldConversations) {
                        Label("Delete Old (>90 days)", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .onAppear {
            setupRepository()
            loadConversations()
        }
        .onChange(of: searchText) { _, newValue in
            searchConversations(query: newValue)
        }
        .sheet(isPresented: $showExportSheet) {
            if let url = exportURL {
                ShareSheet(items: [url])
            }
        }
    }

    // MARK: - Actions

    private func setupRepository() {
        if repository == nil {
            repository = ConversationRepository(modelContext: modelContext)
        }
    }

    private func loadConversations() {
        guard let repo = repository else { return }
        conversations = repo.fetchAllConversations()
    }

    private func searchConversations(query: String) {
        guard let repo = repository else { return }

        if query.isEmpty {
            conversations = repo.fetchAllConversations()
        } else {
            conversations = repo.searchConversations(query: query)
        }
    }

    private func deleteConversations(at offsets: IndexSet) {
        guard let repo = repository else { return }

        let conversationsToDelete = offsets.map { conversations[$0] }
        repo.deleteConversations(conversationsToDelete)

        conversations.remove(atOffsets: offsets)
    }

    private func deleteOldConversations() {
        guard let repo = repository else { return }
        repo.deleteOldConversations(olderThan: 90)
        loadConversations()
    }

    private func exportAll() {
        guard let repo = repository else { return }

        print("[ConversationHistory] Exporting all conversations...")

        // Export as Markdown
        let markdownContent = repo.exportAllConversations()

        // Create temp file
        let tempDir = FileManager.default.temporaryDirectory
        let fileName = "Jarvis_Export_\(Date().ISO8601Format()).md"
        let fileURL = tempDir.appendingPathComponent(fileName)

        do {
            try markdownContent.write(to: fileURL, atomically: true, encoding: .utf8)
            exportURL = fileURL
            showExportSheet = true
            print("[ConversationHistory] ✅ Export successful: \(fileName)")
        } catch {
            print("[ConversationHistory] ❌ Export failed: \(error)")
        }
    }
}

// MARK: - Search Bar

struct SearchBar: View {
    @Binding var text: String
    @Binding var isSearching: Bool

    var body: some View {
        HStack {
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)

                TextField("Search conversations", text: $text)
                    .textFieldStyle(.plain)
                    .autocorrectionDisabled()

                if !text.isEmpty {
                    Button(action: { text = "" }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(8)
            .background(Color(.systemGray6).opacity(0.2))
            .cornerRadius(10)

            if isSearching {
                Button("Cancel") {
                    text = ""
                    isSearching = false
                }
            }
        }
    }
}

// MARK: - Conversation Row

struct ConversationRow: View {
    let conversation: Conversation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Title
            Text(conversation.title)
                .font(.headline)
                .lineLimit(2)

            // Metadata
            HStack(spacing: 12) {
                Label(
                    conversation.timestamp.formatted(date: .abbreviated, time: .shortened),
                    systemImage: "clock"
                )
                .font(.caption)
                .foregroundColor(.secondary)

                Label("\(conversation.messageCount)", systemImage: "message")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if conversation.mode == .glasses {
                    Image(systemName: "eyeglasses")
                        .font(.caption)
                        .foregroundColor(.blue)
                }

                Spacer()

                // Duration
                Text(formatDuration(conversation.duration))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

// MARK: - Empty State

struct EmptyConversationsView: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 64))
                .foregroundColor(.secondary)

            Text("No Conversations Yet")
                .font(.title2.bold())

            Text("Start streaming with your glasses\nto begin a conversation")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding()
    }
}

#Preview {
    NavigationStack {
        ConversationHistoryView()
            .modelContainer(for: [Conversation.self, Message.self])
    }
}
