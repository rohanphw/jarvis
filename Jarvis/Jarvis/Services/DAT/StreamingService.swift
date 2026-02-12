import Foundation
import Combine
import UIKit
import MWDATCore
import MWDATCamera

/// Thread-safe atomic counter
private class Atomic<T> {
    private var value: T
    private let lock = NSLock()

    init(_ value: T) {
        self.value = value
    }

    func increment() -> Int where T == Int {
        lock.lock()
        defer { lock.unlock() }
        value += 1
        return value
    }
}

/// Service managing video streaming from Meta Ray-Ban glasses
///
/// Handles:
/// - 30 FPS video streaming via DAT SDK
/// - Frame throttling for LLM (1-2 FPS)
/// - Photo capture
/// - Error handling and state management
@MainActor
class StreamingService: ObservableObject {

    // MARK: - Published Properties

    /// Current video frame from glasses (30 FPS)
    @Published var currentFrame: UIImage?

    /// Whether first frame has been received
    @Published var hasReceivedFirstFrame: Bool = false

    /// Current streaming state
    @Published var streamingState: StreamSessionState = .stopped

    /// Latest captured photo
    @Published var capturedPhoto: UIImage?

    /// Current error (if any)
    @Published var errorMessage: String?

    // MARK: - Callbacks

    /// Called when a frame should be sent to LLM (throttled to ~1-2 FPS)
    var onFrameForLLM: ((UIImage) -> Void)?

    /// Called when streaming state changes
    var onStateChange: ((StreamSessionState) -> Void)?

    /// Called when an error occurs
    var onError: ((StreamSessionError) -> Void)?

    // MARK: - Private Properties

    private let wearables: WearablesInterface
    private let deviceSelector: AutoDeviceSelector
    private var streamSession: StreamSession

    private var stateListenerToken: AnyListenerToken?
    private var videoFrameListenerToken: AnyListenerToken?
    private var errorListenerToken: AnyListenerToken?
    private var photoDataListenerToken: AnyListenerToken?

    // Frame throttling
    private var lastFrameSentTime: Date = .distantPast
    private let frameInterval: TimeInterval

    // MARK: - Initialization

    init(wearables: WearablesInterface = Wearables.shared) {
        self.wearables = wearables
        self.deviceSelector = AutoDeviceSelector(wearables: wearables)

        // Calculate frame interval from FPS setting
        self.frameInterval = 1.0 / Constants.Video.llmThrottleFPS

        // Configure streaming session
        let config = StreamSessionConfig(
            videoCodec: .raw,
            resolution: .low,  // Low resolution for AI processing
            frameRate: UInt(Constants.Video.streamingFPS)
        )

        self.streamSession = StreamSession(
            streamSessionConfig: config,
            deviceSelector: deviceSelector
        )

        print("[StreamingService] Initialized with \(Constants.Video.streamingFPS) FPS, throttling to \(Constants.Video.llmThrottleFPS) FPS for LLM")

        setupListeners()
    }

    // Listener tokens are automatically cancelled when deallocated
    // deinit not needed as AnyListenerToken handles cleanup

    // MARK: - Streaming Control

    /// Start streaming session
    func start() async {
        print("[StreamingService] ▶️ Starting stream...")
        errorMessage = nil
        await streamSession.start()
    }

    /// Stop streaming session
    func stop() async {
        print("[StreamingService] ⏹️ Stopping stream...")
        await streamSession.stop()
        currentFrame = nil
        hasReceivedFirstFrame = false
        lastFrameSentTime = .distantPast
    }

    // Note: StreamSession does not support pause/resume in DAT SDK v0.4.0
    // Use stop() and start() instead if needed

    // MARK: - Photo Capture

    /// Capture a photo from glasses
    func capturePhoto() {
        guard streamingState == .streaming else {
            print("[StreamingService] ⚠️ Cannot capture photo - not streaming")
            return
        }

        print("[StreamingService] 📸 Capturing photo...")
        streamSession.capturePhoto(format: .jpeg)
    }

    // MARK: - Private Setup

    private func setupListeners() {
        // State changes
        stateListenerToken = streamSession.statePublisher.listen { [weak self] state in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.streamingState = state
                self.onStateChange?(state)
                print("[StreamingService] 📊 State: \(state)")

                // Reset frame flag when stopped
                if state == .stopped {
                    self.hasReceivedFirstFrame = false
                    self.currentFrame = nil
                }
            }
        }

        // Video frames (30 FPS from glasses) - SIMPLIFIED FOR IMMEDIATE DISPLAY
        // Frame counter for skipping frames (reduce UI overhead)
        let frameCounter = Atomic<Int>(0)

        // Dedicated serial queue for video processing (better performance)
        let videoQueue = DispatchQueue(label: "com.jarvis.video", qos: .userInitiated)

        videoFrameListenerToken = streamSession.videoFramePublisher.listen { [weak self] videoFrame in
            guard let self = self else { return }

            // Skip every other frame for smoother UI (30 FPS → 15 FPS display)
            let count = frameCounter.increment()
            guard count % 2 == 0 else { return }

            // Process on dedicated video queue
            videoQueue.async {
                // Convert to UIImage
                guard let rawImage = videoFrame.makeUIImage() else {
                    print("[StreamingService] ⚠️ Failed to convert frame to UIImage")
                    return
                }

                // Resize for faster rendering (max width: 600px)
                let displayImage = self.resizeForDisplay(rawImage, maxWidth: 600)

                // Update UI on main thread
                Task { @MainActor [weak self] in
                    guard let self = self else { return }
                    self.currentFrame = displayImage

                    if !self.hasReceivedFirstFrame {
                        self.hasReceivedFirstFrame = true
                        print("[StreamingService] ✅ First frame received - optimized 15 FPS")
                    }

                    // Throttle frames sent to LLM (use original size, not resized)
                    self.throttleFrameForLLM(rawImage)
                }
            }
        }

        // Errors
        errorListenerToken = streamSession.errorPublisher.listen { [weak self] error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let message = self.formatError(error)
                self.errorMessage = message
                self.onError?(error)
                print("[StreamingService] ❌ Error: \(message)")
            }
        }

        // Photo capture
        photoDataListenerToken = streamSession.photoDataPublisher.listen { [weak self] photoData in
            Task { @MainActor [weak self] in
                guard let self = self else { return }

                guard let image = UIImage(data: photoData.data) else {
                    print("[StreamingService] ⚠️ Failed to decode captured photo")
                    return
                }

                self.capturedPhoto = image
                print("[StreamingService] ✅ Photo captured: \(photoData.data.count) bytes")
            }
        }
    }

    // MARK: - Frame Throttling

    private func throttleFrameForLLM(_ image: UIImage) {
        let now = Date()
        guard now.timeIntervalSince(lastFrameSentTime) >= frameInterval else {
            return
        }

        lastFrameSentTime = now
        onFrameForLLM?(image)
    }

    // MARK: - Image Optimization

    /// Resize image for faster display rendering
    private func resizeForDisplay(_ image: UIImage, maxWidth: CGFloat) -> UIImage {
        let size = image.size
        guard size.width > maxWidth else { return image }

        let scale = maxWidth / size.width
        let newSize = CGSize(width: maxWidth, height: size.height * scale)

        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: newSize))
        }
    }

    // MARK: - Error Formatting

    private func formatError(_ error: StreamSessionError) -> String {
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
}

// MARK: - StreamSessionState Extension

extension StreamSessionState: CustomStringConvertible {
    public var description: String {
        switch self {
        case .stopped: return "stopped"
        case .waitingForDevice: return "waiting for device"
        case .starting: return "starting"
        case .streaming: return "streaming"
        case .paused: return "paused"
        case .stopping: return "stopping"
        @unknown default: return "unknown"
        }
    }
}
