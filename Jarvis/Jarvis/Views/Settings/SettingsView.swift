import SwiftUI

/// Main settings view
///
/// Provides access to:
/// - Device management
/// - Voice settings
/// - Data management
/// - About information
struct SettingsView: View {
    @EnvironmentObject private var wearablesViewModel: WearablesViewModel
    @Environment(\.dismiss) private var dismiss

    @State private var showDisconnectConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                // Device Section
                Section("Device") {
                    if wearablesViewModel.isRegistered {
                        HStack {
                            Text("Status")
                            Spacer()
                            Text(wearablesViewModel.hasActiveDevice ? "Connected" : "Disconnected")
                                .foregroundColor(.secondary)
                        }

                        if !wearablesViewModel.devices.isEmpty {
                            ForEach(wearablesViewModel.devices, id: \.self) { device in
                                HStack {
                                    Image(systemName: "eyeglasses")
                                    Text(wearablesViewModel.deviceName(for: device))
                                    Spacer()
                                    if wearablesViewModel.isDeviceCompatible(device) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundColor(.green)
                                    }
                                }
                            }
                        }

                        Button("Disconnect Glasses", role: .destructive) {
                            showDisconnectConfirmation = true
                        }
                    } else {
                        Button("Connect Glasses") {
                            wearablesViewModel.connectGlasses()
                            dismiss()
                        }
                    }
                }

                // Features Section
                Section("Features") {
                    NavigationLink("Voice Settings") {
                        VoiceSettingsView()
                    }

                    Toggle("Enable iPhone Fallback", isOn: .constant(Constants.Features.enableIPhoneFallback))
                        .disabled(true) // Read-only, set in Constants
                }

                // Data Section
                Section("Data & Storage") {
                    NavigationLink("Conversation History") {
                        ConversationHistoryView()
                    }

                    Button("Export All Conversations") {
                        exportAllConversations()
                    }

                    Button("Clear Old Data (>90 days)", role: .destructive) {
                        clearOldData()
                    }
                }

                // About Section
                Section("About") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    Link("Developer Documentation", destination: URL(string: "https://wearables.developer.meta.com")!)

                    Link("Privacy Policy", destination: URL(string: "https://example.com/privacy")!)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .confirmationDialog("Disconnect Glasses?", isPresented: $showDisconnectConfirmation) {
                Button("Disconnect", role: .destructive) {
                    wearablesViewModel.disconnectGlasses()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You can reconnect anytime from Settings.")
            }
        }
    }

    // MARK: - Actions

    private func exportAllConversations() {
        // TODO: Implement bulk export
        print("[Settings] Export all conversations")
    }

    private func clearOldData() {
        // TODO: Implement data cleanup
        print("[Settings] Clear old data")
    }
}

// MARK: - Voice Settings View

struct VoiceSettingsView: View {
    @AppStorage("voiceSpeed") private var voiceSpeed: Double = 1.0
    @AppStorage("preferredLanguage") private var preferredLanguage: String = "en-US"

    var body: some View {
        Form {
            Section("Speech") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Speed")
                        Spacer()
                        Text("\(voiceSpeed, specifier: "%.1f")x")
                            .foregroundColor(.secondary)
                    }
                    Slider(value: $voiceSpeed, in: 0.5...2.0, step: 0.1)
                }
            }

            Section("Language") {
                Picker("Language", selection: $preferredLanguage) {
                    Text("English (US)").tag("en-US")
                    Text("Spanish").tag("es-ES")
                    Text("French").tag("fr-FR")
                    Text("German").tag("de-DE")
                    Text("Japanese").tag("ja-JP")
                }
            }

            Section("About") {
                Text("AI powered by Claude with vision support")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("Voice Settings")
    }
}

#Preview {
    SettingsView()
        .environmentObject(WearablesViewModel())
}
