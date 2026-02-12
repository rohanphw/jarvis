import Foundation
import AVFoundation
import UIKit

/// Manages iPhone camera capture for fallback mode
///
/// When Meta Ray-Ban glasses are not available, this class provides
/// video streaming from the iPhone's camera at a similar rate.
class IPhoneCameraManager: NSObject {

    // MARK: - Callbacks

    /// Called when a new frame is captured
    var onFrameCaptured: ((UIImage) -> Void)?

    /// Called when an error occurs
    var onError: ((Error) -> Void)?

    // MARK: - Private Properties

    private let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.jarvis.camera")
    private var videoOutput: AVCaptureVideoDataOutput?
    private var isCapturing = false

    // Frame throttling to match glasses FPS
    private var lastFrameTime: Date = .distantPast
    private let frameInterval: TimeInterval

    // MARK: - Initialization

    override init() {
        // Match glasses streaming FPS
        self.frameInterval = 1.0 / Double(Constants.Video.streamingFPS)
        super.init()
    }

    // MARK: - Public Methods

    /// Start camera capture
    func startCapture() throws {
        guard !isCapturing else {
            print("[IPhoneCameraManager] ⚠️ Already capturing")
            return
        }

        // Request camera permission if needed
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        guard status == .authorized else {
            if status == .notDetermined {
                // Request permission asynchronously
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    if granted {
                        try? self?.setupCaptureSession()
                    } else {
                        let error = CameraError.permissionDenied
                        self?.onError?(error)
                    }
                }
                return
            } else {
                throw CameraError.permissionDenied
            }
        }

        try setupCaptureSession()
    }

    /// Stop camera capture
    func stopCapture() {
        guard isCapturing else { return }

        sessionQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            self?.isCapturing = false
            print("[IPhoneCameraManager] ⏹️ Capture stopped")
        }
    }

    // MARK: - Private Setup

    private func setupCaptureSession() throws {
        sessionQueue.async { [weak self] in
            guard let self else { return }

            // Configure session
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .medium  // Balance quality and performance

            // Add camera input
            do {
                guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                    throw CameraError.cameraNotAvailable
                }

                let input = try AVCaptureDeviceInput(device: camera)

                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                } else {
                    throw CameraError.cannotAddInput
                }

                // Configure camera settings
                try camera.lockForConfiguration()
                if camera.isFocusModeSupported(.continuousAutoFocus) {
                    camera.focusMode = .continuousAutoFocus
                }
                if camera.isExposureModeSupported(.continuousAutoExposure) {
                    camera.exposureMode = .continuousAutoExposure
                }
                camera.unlockForConfiguration()

            } catch {
                print("[IPhoneCameraManager] ❌ Failed to setup camera input: \(error)")
                self.onError?(error)
                self.captureSession.commitConfiguration()
                return
            }

            // Add video output
            let output = AVCaptureVideoDataOutput()
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
            ]
            output.alwaysDiscardsLateVideoFrames = true
            output.setSampleBufferDelegate(self, queue: self.sessionQueue)

            if self.captureSession.canAddOutput(output) {
                self.captureSession.addOutput(output)
                self.videoOutput = output
            } else {
                print("[IPhoneCameraManager] ❌ Cannot add video output")
                self.onError?(CameraError.cannotAddOutput)
                self.captureSession.commitConfiguration()
                return
            }

            self.captureSession.commitConfiguration()

            // Start running
            self.captureSession.startRunning()
            self.isCapturing = true
            print("[IPhoneCameraManager] ✅ Capture started at \(Constants.Video.streamingFPS) FPS")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

extension IPhoneCameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Throttle frames to match target FPS
        let now = Date()
        guard now.timeIntervalSince(lastFrameTime) >= frameInterval else {
            return
        }
        lastFrameTime = now

        // Convert to UIImage
        guard let image = imageFromSampleBuffer(sampleBuffer) else {
            return
        }

        // Notify on main thread
        DispatchQueue.main.async { [weak self] in
            self?.onFrameCaptured?(image)
        }
    }

    func captureOutput(
        _ output: AVCaptureOutput,
        didDrop sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Log dropped frames in debug builds
        #if DEBUG
        print("[IPhoneCameraManager] ⚠️ Dropped frame")
        #endif
    }

    // MARK: - Image Conversion

    private func imageFromSampleBuffer(_ sampleBuffer: CMSampleBuffer) -> UIImage? {
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }

        CVPixelBufferLockBaseAddress(imageBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(imageBuffer, .readOnly) }

        let baseAddress = CVPixelBufferGetBaseAddress(imageBuffer)
        let bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer)
        let width = CVPixelBufferGetWidth(imageBuffer)
        let height = CVPixelBufferGetHeight(imageBuffer)

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return nil
        }

        guard let cgImage = context.makeImage() else {
            return nil
        }

        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .right)
    }
}

// MARK: - Errors

enum CameraError: LocalizedError {
    case permissionDenied
    case cameraNotAvailable
    case cannotAddInput
    case cannotAddOutput

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Camera permission denied. Please enable camera access in Settings."
        case .cameraNotAvailable:
            return "Camera is not available on this device."
        case .cannotAddInput:
            return "Failed to add camera input to capture session."
        case .cannotAddOutput:
            return "Failed to add video output to capture session."
        }
    }
}
