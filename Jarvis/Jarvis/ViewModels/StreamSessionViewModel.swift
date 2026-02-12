import Foundation
import Combine
import SwiftUI
import MWDATCore
import MWDATCamera

/// ViewModel for streaming session management
///
/// Manages UI state for:
/// - Video streaming (glasses or iPhone)
/// - Current video frames for display
/// - Photo capture flow
/// - Mode switching
@MainActor
class StreamSessionViewModel: ObservableObject {

    // MARK: - Published Properties

    /// Current video frame from glasses (30 FPS)
    @Published var currentVideoFrame: UIImage?

    /// Current streaming state
    @Published var streamingState: StreamSessionState = .stopped

    /// Whether first frame has been received
    @Published var hasReceivedFirstFrame: Bool = false

    /// Current streaming mode
    @Published var streamingMode: StreamingMode = .glasses

    /// Latest captured photo
    @Published var capturedPhoto: UIImage?

    /// Error message to display
    @Published var errorMessage: String?

    /// Whether to show error alert
    @Published var showError: Bool = false

    // MARK: - Callbacks

    /// Called when a frame should be sent to LLM (throttled to ~1-2 FPS)
    var onFrameForLLM: ((UIImage) -> Void)?

    /// Called when a photo is captured and should be described by AI
    var onPhotoCaptured: ((UIImage) -> Void)?

    /// Called when streaming state changes
    var onStateChange: ((StreamSessionState) -> Void)?

    // MARK: - Private Properties

    private let streamingService: StreamingService
    private let wearablesService: WearablesService
    private var iPhoneCameraManager: IPhoneCameraManager?

    // MARK: - Computed Properties

    /// Whether currently streaming
    var isStreaming: Bool {
        streamingState == .streaming
    }

    /// Whether waiting for device
    var isWaitingForDevice: Bool {
        streamingState == .waitingForDevice
    }

    /// Whether streaming can be started
    var canStartStreaming: Bool {
        streamingMode == .iPhone || wearablesService.hasActiveDevice
    }

    // MARK: - Initialization

    init(
        streamingService: StreamingService? = nil,
        wearablesService: WearablesService? = nil
    ) {
        self.streamingService = streamingService ?? StreamingService()
        self.wearablesService = wearablesService ?? WearablesService()

        setupCallbacks()
    }

    // MARK: - Streaming Control

    /// Start streaming session
    func startStreaming() async {
        guard canStartStreaming else {
            showError("No device available. Please connect your glasses or switch to iPhone mode.")
            return
        }

        errorMessage = nil

        switch streamingMode {
        case .glasses:
            await startGlassesStreaming()
        case .iPhone:
            await startIPhoneStreaming()
        }
    }

    /// Stop streaming session
    func stopStreaming() async {
        switch streamingMode {
        case .glasses:
            await streamingService.stop()
        case .iPhone:
            iPhoneCameraManager?.stopCapture()
        }

        currentVideoFrame = nil
        hasReceivedFirstFrame = false
    }

    // Note: Pause/resume not supported by DAT SDK v0.4.0
    // Use stop() and start() if needed

    // MARK: - Mode Switching

    /// Switch between glasses and iPhone mode
    func switchMode(to mode: StreamingMode) async {
        let wasStreaming = isStreaming

        // Stop current streaming
        if wasStreaming {
            await stopStreaming()
        }

        // Update mode
        streamingMode = mode

        // Restart if was streaming
        if wasStreaming {
            await startStreaming()
        }
    }

    // MARK: - Photo Capture

    /// Capture a photo from current stream
    func capturePhoto() {
        guard isStreaming else {
            showError("Cannot capture photo - not streaming")
            return
        }

        switch streamingMode {
        case .glasses:
            streamingService.capturePhoto()
        case .iPhone:
            if let frame = currentVideoFrame {
                capturedPhoto = frame
                onPhotoCaptured?(frame)
                print("[StreamSessionViewModel] 📸 iPhone photo captured and sent for AI description")
            }
        }
    }

    // MARK: - Error Handling

    func showError(_ message: String) {
        errorMessage = message
        showError = true
        print("[StreamSessionViewModel] ❌ Error: \(message)")
    }

    func dismissError() {
        showError = false
        errorMessage = ""
    }

    // MARK: - Private Setup

    private func setupCallbacks() {
        // StreamingService callbacks (for glasses mode)
        streamingService.onFrameForLLM = { [weak self] image in
            guard let self else { return }
            Task { @MainActor in
                self.onFrameForLLM?(image)
            }
        }

        streamingService.onStateChange = { [weak self] state in
            guard let self else { return }
            Task { @MainActor in
                self.streamingState = state
                self.onStateChange?(state)
            }
        }

        streamingService.onError = { [weak self] error in
            guard let self else { return }
            Task { @MainActor in
                self.showError(self.formatStreamingError(error))
            }
        }

        // Observe service state changes using Combine publishers (much more efficient than polling)
        streamingService.$currentFrame
            .receive(on: DispatchQueue.main)
            .assign(to: &$currentVideoFrame)

        streamingService.$hasReceivedFirstFrame
            .receive(on: DispatchQueue.main)
            .assign(to: &$hasReceivedFirstFrame)

        streamingService.$streamingState
            .receive(on: DispatchQueue.main)
            .assign(to: &$streamingState)

        streamingService.$capturedPhoto
            .receive(on: DispatchQueue.main)
            .compactMap { $0 }
            .sink { [weak self] photo in
                guard let self = self else { return }
                self.capturedPhoto = photo
                self.onPhotoCaptured?(photo)
                print("[StreamSessionViewModel] ✅ Photo received from service and sent for AI description")
            }
            .store(in: &cancellables)
    }

    // MARK: - Private Streaming Methods

    private func startGlassesStreaming() async {
        print("[StreamSessionViewModel] ▶️ Starting glasses streaming...")

        // Check and request camera permission first
        do {
            let status = try await wearablesService.checkCameraPermission()
            print("[StreamSessionViewModel] 📹 Camera permission status: \(status)")

            if status != .granted {
                print("[StreamSessionViewModel] 📹 Requesting camera permission...")
                let newStatus = try await wearablesService.requestCameraPermission()

                if newStatus != .granted {
                    showError("Camera permission denied. Please grant permission in the Meta AI app and try again.")
                    return
                }
            }
        } catch {
            print("[StreamSessionViewModel] ❌ Permission check failed: \(error)")
            // Continue anyway - let streaming service handle the error
        }

        await streamingService.start()
    }

    private func startIPhoneStreaming() async {
        print("[StreamSessionViewModel] ▶️ Starting iPhone streaming...")

        // Initialize iPhone camera manager if needed
        if iPhoneCameraManager == nil {
            iPhoneCameraManager = IPhoneCameraManager()
        }

        guard let cameraManager = iPhoneCameraManager else {
            showError("Failed to initialize iPhone camera")
            return
        }

        // Setup callback for frames
        cameraManager.onFrameCaptured = { [weak self] image in
            guard let self else { return }
            Task { @MainActor in
                self.currentVideoFrame = image

                if !self.hasReceivedFirstFrame {
                    self.hasReceivedFirstFrame = true
                    print("[StreamSessionViewModel] ✅ First iPhone frame received")
                }

                // Throttle and send to LLM
                if self.shouldSendFrameToLLM() {
                    self.onFrameForLLM?(image)
                }
            }
        }

        // Start capture
        do {
            try cameraManager.startCapture()
            streamingState = .streaming
            print("[StreamSessionViewModel] ✅ iPhone streaming started")
        } catch {
            showError("Failed to start iPhone camera: \(error.localizedDescription)")
        }
    }

    // MARK: - Frame Throttling

    private var lastFrameSentTime: Date = .distantPast

    private func shouldSendFrameToLLM() -> Bool {
        let now = Date()
        let interval = 1.0 / Constants.Video.llmThrottleFPS

        guard now.timeIntervalSince(lastFrameSentTime) >= interval else {
            return false
        }

        lastFrameSentTime = now
        return true
    }

    // MARK: - Error Formatting

    private func formatStreamingError(_ error: StreamSessionError) -> String {
        switch error {
        case .internalError:
            return "Internal streaming error occurred"
        case .deviceNotFound:
            return "Device not found. Ensure glasses are connected."
        case .deviceNotConnected:
            return "Device not connected. Check Bluetooth connection."
        case .timeout:
            return "Streaming timeout. Please try again."
        case .videoStreamingError:
            return "Video streaming failed. Please restart."
        case .audioStreamingError:
            return "Audio streaming failed."
        case .permissionDenied:
            return "Camera permission denied. Grant permission in Meta AI app."
        case .hingesClosed:
            return "Glasses hinges are closed. Open them to stream."
        @unknown default:
            return "Unknown streaming error occurred"
        }
    }

    private var cancellables = Set<AnyCancellable>()
}
