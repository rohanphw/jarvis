import SwiftUI
import SwiftData

/// Root coordinator view for the entire app
///
/// Manages navigation between:
/// - Registration flow (if not registered)
/// - Home screen (if registered but not streaming)
/// - Streaming session (when active)
struct MainAppView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var wearablesViewModel = WearablesViewModel()

    var body: some View {
        Group {
            if wearablesViewModel.isRegistered {
                // User has connected their glasses
                HomeScreenView()
                    .environmentObject(wearablesViewModel)
            } else {
                // First-time setup flow
                RegistrationView()
                    .environmentObject(wearablesViewModel)
            }
        }
        .onOpenURL { url in
            // Handle OAuth callback from Meta AI app
            wearablesViewModel.handleCallback(url: url)
        }
    }
}

#Preview {
    MainAppView()
        .modelContainer(for: [Conversation.self, Message.self])
}
