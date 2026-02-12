import SwiftUI

/// API key setup screen for first launch
struct APIKeySetupView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var apiKey: String = ""
    @State private var isValidating: Bool = false
    @State private var errorMessage: String?
    @State private var showSuccess: Bool = false
    @State private var hasExistingKey: Bool = false
    @State private var showDeleteConfirmation: Bool = false

    var onComplete: () -> Void

    var body: some View {
        ZStack {
            // Background
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.05, blue: 0.12),
                    Color(red: 0.02, green: 0.02, blue: 0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 32) {
                    Spacer()
                        .frame(height: 60)

                    // Minimal branding
                    VStack(spacing: 8) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 36, weight: .ultraLight))
                            .foregroundColor(.white.opacity(0.9))

                        Text(hasExistingKey ? "Manage API Key" : "Setup")
                            .font(.system(size: 24, weight: .medium))
                            .foregroundColor(.white)
                    }

                    // Current key status
                    if hasExistingKey {
                        VStack(spacing: 12) {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundColor(.green)

                                Text("API key is configured")
                                    .font(.system(size: 14))
                                    .foregroundColor(.white.opacity(0.7))
                            }

                            Text("You can change or delete your API key below")
                                .font(.system(size: 12))
                                .foregroundColor(.white.opacity(0.5))
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 40)
                    } else {
                        // Instructions
                        VStack(spacing: 12) {
                            Text("Enter your Anthropic API key to get started")
                                .font(.system(size: 14))
                                .foregroundColor(.white.opacity(0.7))
                                .multilineTextAlignment(.center)

                            Link(destination: URL(string: "https://console.anthropic.com/")!) {
                                HStack(spacing: 6) {
                                    Text("Get your key")
                                        .font(.system(size: 13, weight: .medium))
                                    Image(systemName: "arrow.up.right")
                                        .font(.system(size: 11))
                                }
                                .foregroundColor(.white.opacity(0.6))
                            }
                        }
                        .padding(.horizontal, 40)
                    }

                    // API Key Input
                    VStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("API Key")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(.white.opacity(0.5))
                                .padding(.horizontal, 4)

                            SecureField("sk-ant-api03-...", text: $apiKey)
                                .font(.system(size: 14, design: .monospaced))
                                .foregroundColor(.white)
                                .padding(14)
                                .background(
                                    RoundedRectangle(cornerRadius: 12)
                                        .fill(Color.white.opacity(0.06))
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .strokeBorder(
                                                    errorMessage != nil ? Color.red.opacity(0.5) : Color.white.opacity(0.1),
                                                    lineWidth: 1
                                                )
                                        )
                                )
                                .autocorrectionDisabled()
                                .textCase(.lowercase)
                        }

                        if let error = errorMessage {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.system(size: 12))
                                Text(error)
                                    .font(.system(size: 12))
                            }
                            .foregroundColor(.red.opacity(0.8))
                        }
                    }
                    .padding(.horizontal, 24)

                    // Save Button
                    Button(action: saveAPIKey) {
                        HStack(spacing: 8) {
                            if isValidating {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(0.8)
                            }

                            Text(isValidating ? "Validating..." : (hasExistingKey ? "Update Key" : "Continue"))
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(apiKey.isEmpty ? Color.white.opacity(0.06) : Color.white.opacity(0.15))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
                                )
                        )
                    }
                    .disabled(apiKey.isEmpty || isValidating)
                    .padding(.horizontal, 24)

                    // Delete Button (only if key exists)
                    if hasExistingKey {
                        Button(action: { showDeleteConfirmation = true }) {
                            HStack(spacing: 8) {
                                Image(systemName: "trash")
                                    .font(.system(size: 14))
                                Text("Delete API Key")
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .foregroundColor(.red.opacity(0.9))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(Color.red.opacity(0.1))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .strokeBorder(Color.red.opacity(0.3), lineWidth: 1)
                                    )
                            )
                        }
                        .padding(.horizontal, 24)
                    }

                    Spacer()
                }
            }
            .onAppear {
                checkExistingKey()
            }
            .confirmationDialog("Delete API Key?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    deleteAPIKey()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove your API key from the keychain. You'll need to enter it again to use the app.")
            }

            // Success overlay
            if showSuccess {
                ZStack {
                    Color.black.opacity(0.8)
                        .ignoresSafeArea()

                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.green)

                        Text("API Key Saved")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundColor(.white)
                    }
                }
                .transition(.opacity)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func checkExistingKey() {
        if let key = KeychainManager.shared.getAnthropicKey(), !key.isEmpty {
            hasExistingKey = true
        } else {
            hasExistingKey = false
        }
    }

    private func saveAPIKey() {
        guard !apiKey.isEmpty else { return }

        // Clear any previous error
        errorMessage = nil
        isValidating = true

        // Basic validation
        guard apiKey.hasPrefix("sk-ant-") else {
            isValidating = false
            errorMessage = "Invalid API key format"
            return
        }

        // Save to keychain
        if KeychainManager.shared.saveAnthropicKey(apiKey) {
            // Show success
            withAnimation {
                showSuccess = true
            }

            // Complete after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                onComplete()
            }
        } else {
            isValidating = false
            errorMessage = "Failed to save API key"
        }
    }

    private func deleteAPIKey() {
        if KeychainManager.shared.deleteAnthropicKey() {
            // Show success
            withAnimation {
                showSuccess = true
            }

            // Complete after delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                hasExistingKey = false
                apiKey = ""
                onComplete()
            }
        } else {
            errorMessage = "Failed to delete API key"
        }
    }
}

#Preview {
    APIKeySetupView(onComplete: {})
}
