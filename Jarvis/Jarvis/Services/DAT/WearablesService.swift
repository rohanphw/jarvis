import Foundation
import Combine
import MWDATCore

/// Service managing Meta Wearables DAT SDK interactions
///
/// Handles:
/// - Device registration (OAuth-like flow via Meta AI app)
/// - Device discovery and monitoring
/// - Compatibility checking
/// - Permission management (camera, microphone)
@MainActor
class WearablesService: ObservableObject {

    // MARK: - Published Properties

    /// Current registration state (.registered, .registering, .unregistered)
    @Published var registrationState: RegistrationState

    /// List of available device identifiers
    @Published var devices: [DeviceIdentifier]

    /// Whether at least one compatible device is available
    @Published var hasActiveDevice: Bool = false

    /// Current error message (if any)
    @Published var errorMessage: String?

    // MARK: - Private Properties

    private let wearables: WearablesInterface
    private var deviceStreamTask: Task<Void, Never>?
    private var registrationTask: Task<Void, Never>?
    private var compatibilityListenerTokens: [DeviceIdentifier: AnyListenerToken] = [:]

    // MARK: - Initialization

    init(wearables: WearablesInterface = Wearables.shared) {
        self.wearables = wearables
        self.registrationState = wearables.registrationState
        self.devices = wearables.devices

        print("[WearablesService] Initialized with state: \(registrationState)")

        // Start monitoring registration state changes
        setupRegistrationStream()

        // Start monitoring device changes
        setupDeviceStream()
    }

    deinit {
        registrationTask?.cancel()
        deviceStreamTask?.cancel()
        // Listener tokens are automatically cancelled when deallocated
    }

    // MARK: - Registration

    /// Start registration flow - opens Meta AI app for user authorization
    func startRegistration() async throws {
        guard registrationState != .registering else {
            print("[WearablesService] ⚠️ Already registering")
            return
        }

        print("[WearablesService] 🔐 Starting registration...")
        errorMessage = nil

        do {
            try await wearables.startRegistration()
            print("[WearablesService] ✅ Registration request sent")
        } catch let error as RegistrationError {
            let message = "Registration failed: \(error.description)"
            print("[WearablesService] ❌ \(message)")
            errorMessage = message
            throw error
        } catch {
            let message = "Registration failed: \(error.localizedDescription)"
            print("[WearablesService] ❌ \(message)")
            errorMessage = message
            throw error
        }
    }

    /// Handle callback URL from Meta AI app
    func handleCallback(url: URL) async throws {
        print("[WearablesService] 📥 Handling callback URL")

        do {
            _ = try await wearables.handleUrl(url)
            print("[WearablesService] ✅ Callback processed successfully")
            errorMessage = nil
        } catch let error as RegistrationError {
            let message = "Callback handling failed: \(error.description)"
            print("[WearablesService] ❌ \(message)")
            errorMessage = message
            throw error
        } catch {
            let message = "Callback handling failed: \(error.localizedDescription)"
            print("[WearablesService] ❌ \(message)")
            errorMessage = message
            throw error
        }
    }

    /// Start unregistration - disconnects from glasses
    func startUnregistration() async throws {
        print("[WearablesService] 🔓 Starting unregistration...")
        errorMessage = nil

        do {
            try await wearables.startUnregistration()
            print("[WearablesService] ✅ Unregistration successful")
        } catch let error as UnregistrationError {
            let message = "Unregistration failed: \(error.description)"
            print("[WearablesService] ❌ \(message)")
            errorMessage = message
            throw error
        } catch {
            let message = "Unregistration failed: \(error.localizedDescription)"
            print("[WearablesService] ❌ \(message)")
            errorMessage = message
            throw error
        }
    }

    // MARK: - Permissions

    /// Check camera permission status
    func checkCameraPermission() async throws -> PermissionStatus {
        let status = try await wearables.checkPermissionStatus(.camera)
        print("[WearablesService] 📹 Camera permission: \(status)")
        return status
    }

    /// Request camera permission (opens Meta AI app)
    func requestCameraPermission() async throws -> PermissionStatus {
        print("[WearablesService] 📹 Requesting camera permission...")
        errorMessage = nil

        do {
            let status = try await wearables.requestPermission(.camera)
            print("[WearablesService] ✅ Camera permission: \(status)")
            return status
        } catch {
            let message = "Permission request failed: \(error.localizedDescription)"
            print("[WearablesService] ❌ \(message)")
            errorMessage = message
            throw error
        }
    }

    // MARK: - Device Information

    /// Get device for a given identifier
    func device(for identifier: DeviceIdentifier) -> Device? {
        wearables.deviceForIdentifier(identifier)
    }

    /// Get human-readable name for device
    func deviceName(for identifier: DeviceIdentifier) -> String {
        guard let device = wearables.deviceForIdentifier(identifier) else {
            return "Unknown Device"
        }
        return device.nameOrId()
    }

    /// Check if device is compatible
    func isDeviceCompatible(_ identifier: DeviceIdentifier) -> Bool {
        guard let device = wearables.deviceForIdentifier(identifier) else {
            return false
        }
        return device.compatibility() == .compatible
    }

    // MARK: - Private Setup Methods

    private func setupRegistrationStream() {
        registrationTask = Task {
            for await state in wearables.registrationStateStream() {
                let previousState = self.registrationState
                self.registrationState = state

                print("[WearablesService] 📊 Registration state: \(previousState) → \(state)")

                // Clear error on successful registration
                if state == .registered && previousState != .registered {
                    self.errorMessage = nil
                }
            }
        }
    }

    private func setupDeviceStream() {
        deviceStreamTask = Task {
            for await deviceList in wearables.devicesStream() {
                self.devices = deviceList
                print("[WearablesService] 📱 Devices updated: \(deviceList.count) device(s)")

                // Update active device status
                self.updateActiveDeviceStatus(deviceList)

                // Monitor device compatibility
                monitorDeviceCompatibility(deviceList)
            }
        }
    }

    private func updateActiveDeviceStatus(_ deviceList: [DeviceIdentifier]) {
        // Check if any device is compatible
        let hasCompatible = deviceList.contains { identifier in
            guard let device = wearables.deviceForIdentifier(identifier) else {
                return false
            }
            return device.compatibility() == .compatible
        }

        if hasActiveDevice != hasCompatible {
            hasActiveDevice = hasCompatible
            print("[WearablesService] 🔌 Active device available: \(hasCompatible)")
        }
    }

    private func monitorDeviceCompatibility(_ deviceList: [DeviceIdentifier]) {
        let deviceSet = Set(deviceList)

        // Remove listeners for devices no longer present
        compatibilityListenerTokens = compatibilityListenerTokens.filter {
            deviceSet.contains($0.key)
        }

        // Add listeners for new devices
        for identifier in deviceList {
            guard compatibilityListenerTokens[identifier] == nil else { continue }
            guard let device = wearables.deviceForIdentifier(identifier) else { continue }

            let deviceName = device.nameOrId()
            let token = device.addCompatibilityListener { [weak self] compatibility in
                guard let self else { return }

                Task { @MainActor in
                    print("[WearablesService] 🔧 Device '\(deviceName)' compatibility: \(compatibility)")

                    if compatibility == .deviceUpdateRequired {
                        self.errorMessage = "Device '\(deviceName)' requires an update"
                    }

                    // Update active device status when compatibility changes
                    self.updateActiveDeviceStatus(self.devices)
                }
            }

            compatibilityListenerTokens[identifier] = token
        }
    }
}
