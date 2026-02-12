import SwiftUI
import MWDATCore

/// First-time registration and onboarding view
///
/// Guides users through:
/// - Connecting Meta Ray-Ban glasses
/// - OAuth flow via Meta AI app
/// - Initial permissions setup
struct RegistrationView: View {
    @EnvironmentObject private var viewModel: WearablesViewModel

    @State private var showPermissionAlert = false
    @State private var permissionAlertMessage = ""

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Spacer()

                // App Icon / Logo
                Image(systemName: "eyeglasses")
                    .font(.system(size: 80))
                    .foregroundStyle(.blue.gradient)

                // Title
                VStack(spacing: 8) {
                    Text("Welcome to Jarvis")
                        .font(.largeTitle.bold())

                    Text("Your AI Assistant for Meta Ray-Ban Glasses")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Spacer()

                // Registration State
                VStack(spacing: 16) {
                    if viewModel.isRegistering {
                        // Connecting state
                        ProgressView()
                            .scaleEffect(1.5)
                            .padding(.bottom, 8)

                        Text("Opening Meta AI app...")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Text("Please approve the connection")
                            .font(.caption)
                            .foregroundColor(.secondary)

                    } else {
                        // Ready to connect
                        Button(action: connectGlasses) {
                            HStack {
                                Image(systemName: "link")
                                Text("Connect My Glasses")
                            }
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue.gradient)
                            .cornerRadius(12)
                        }
                        .disabled(viewModel.isRegistering)
                        .padding(.horizontal, 32)

                        // Skip option (iPhone mode)
                        if Constants.Features.enableIPhoneFallback {
                            Button("Skip and use iPhone camera") {
                                // TODO: Navigate to home without registration
                            }
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                // Info footer
                VStack(spacing: 4) {
                    Text("Requires Meta AI app with Developer Mode")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Link("Learn more", destination: URL(string: "https://wearables.developer.meta.com")!)
                        .font(.caption2)
                }
                .padding(.bottom, 32)
            }
            .navigationBarHidden(true)
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK") {
                    viewModel.dismissError()
                }
            } message: {
                Text(viewModel.errorMessage)
            }
            .alert("Permission Required", isPresented: $showPermissionAlert) {
                Button("Open Settings", action: openSettings)
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(permissionAlertMessage)
            }
            .onChange(of: viewModel.isRegistered) { _, isRegistered in
                if isRegistered {
                    // Registration successful - check permissions
                    checkPermissions()
                }
            }
        }
    }

    // MARK: - Actions

    private func connectGlasses() {
        viewModel.connectGlasses()
    }

    private func checkPermissions() {
        Task {
            // Check camera permission
            let cameraStatus = await viewModel.checkCameraPermission()

            if cameraStatus != .granted {
                permissionAlertMessage = "Camera permission is required for video streaming from your glasses."
                showPermissionAlert = true
            }
        }
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    RegistrationView()
        .environmentObject(WearablesViewModel())
}
