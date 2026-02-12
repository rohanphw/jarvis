import Foundation
import Combine
import SwiftUI
import MWDATCore

/// ViewModel for Meta Ray-Ban glasses registration and device management
///
/// Manages UI state for:
/// - Registration flow (connect/disconnect glasses)
/// - Device discovery and status
/// - Error presentation
@MainActor
class WearablesViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Current registration state
    @Published var registrationState: RegistrationState

    /// Available devices
    @Published var devices: [DeviceIdentifier]

    /// Whether at least one compatible device is available
    @Published var hasActiveDevice: Bool

    /// Error message to display in UI
    @Published var errorMessage: String = ""

    /// Whether to show error alert
    @Published var showError: Bool = false

    /// Whether to show "Getting Started" sheet after registration
    @Published var showGettingStartedSheet: Bool = false

    // MARK: - Private Properties

    private let service: WearablesService

    /// Expose the service for sharing with other components
    var wearablesService: WearablesService {
        service
    }

    // MARK: - Computed Properties

    /// Whether the user is currently registered
    var isRegistered: Bool {
        registrationState == .registered
    }

    /// Whether registration is in progress
    var isRegistering: Bool {
        registrationState == .registering
    }

    // MARK: - Initialization

    init(service: WearablesService? = nil) {
        let svc = service ?? WearablesService()
        self.service = svc

        // Initialize with service state
        self.registrationState = svc.registrationState
        self.devices = svc.devices
        self.hasActiveDevice = svc.hasActiveDevice

        // Observe service changes
        setupObservation()
    }

    // MARK: - Actions

    /// Start registration flow - opens Meta AI app
    func connectGlasses() {
        guard registrationState != .registering else {
            print("[WearablesViewModel] Already registering")
            return
        }

        Task {
            do {
                try await service.startRegistration()
            } catch let error as RegistrationError {
                showError(error.description)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    /// Disconnect glasses - unregister from SDK
    func disconnectGlasses() {
        Task {
            do {
                try await service.startUnregistration()
            } catch let error as UnregistrationError {
                showError(error.description)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    /// Handle URL callback from Meta AI app
    func handleCallback(url: URL) {
        Task {
            do {
                try await service.handleCallback(url: url)
            } catch let error as RegistrationError {
                showError(error.description)
            } catch {
                showError(error.localizedDescription)
            }
        }
    }

    /// Check camera permission status
    func checkCameraPermission() async -> PermissionStatus? {
        do {
            return try await service.checkCameraPermission()
        } catch {
            showError("Failed to check camera permission: \(error.localizedDescription)")
            return nil
        }
    }

    /// Request camera permission (opens Meta AI app)
    func requestCameraPermission() async -> PermissionStatus? {
        do {
            return try await service.requestCameraPermission()
        } catch {
            showError("Permission request failed: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Device Info

    /// Get human-readable device name
    func deviceName(for identifier: DeviceIdentifier) -> String {
        service.deviceName(for: identifier)
    }

    /// Check if device is compatible
    func isDeviceCompatible(_ identifier: DeviceIdentifier) -> Bool {
        service.isDeviceCompatible(identifier)
    }

    // MARK: - Error Handling

    func showError(_ message: String) {
        errorMessage = message
        showError = true
        print("[WearablesViewModel] ❌ Error: \(message)")
    }

    func dismissError() {
        showError = false
        errorMessage = ""
    }

    // MARK: - Private Methods

    private func setupObservation() {
        // Observe service properties using Combine
        Task {
            for await _ in AsyncStream<Void> { continuation in
                Timer.publish(every: 0.1, on: .main, in: .common)
                    .autoconnect()
                    .sink { _ in
                        continuation.yield(())
                    }
                    .store(in: &cancellables)
            } {
                // Update local state from service
                if self.registrationState != self.service.registrationState {
                    let previous = self.registrationState
                    self.registrationState = self.service.registrationState

                    // Show getting started sheet when registration completes
                    if self.registrationState == .registered &&
                        previous == .registering &&
                        !self.showGettingStartedSheet {
                        self.showGettingStartedSheet = true
                    }
                }

                if self.devices != self.service.devices {
                    self.devices = self.service.devices
                }

                if self.hasActiveDevice != self.service.hasActiveDevice {
                    self.hasActiveDevice = self.service.hasActiveDevice
                }

                // Sync error message
                if let serviceError = self.service.errorMessage,
                   !serviceError.isEmpty,
                   self.errorMessage != serviceError {
                    self.showError(serviceError)
                }
            }
        }
    }

    private var cancellables = Set<AnyCancellable>()
}
