import Foundation
import AVFoundation
import Accelerate

/// Manager for bidirectional audio streaming with Grok API
///
/// Handles:
/// - Microphone capture (PCM Int16, 16kHz mono)
/// - Speaker playback (PCM Int16, 24kHz mono from Grok)
/// - Real-time resampling and format conversion
/// - Echo cancellation configuration
class AudioManager: NSObject {

    // MARK: - Callbacks

    /// Called when audio is captured from microphone (PCM Int16, 16kHz)
    var onAudioCaptured: ((Data) -> Void)?

    /// Called when an error occurs
    var onError: ((Error) -> Void)?

    // MARK: - Private Properties

    private let audioEngine = AVAudioEngine()
    private let playerNode = AVAudioPlayerNode()
    private var isCapturing = false
    private var isPlaying = false

    // Audio session mode
    private var useIPhoneMode: Bool = false

    // Input format (from microphone)
    private lazy var inputFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Constants.Audio.inputSampleRate,
            channels: AVAudioChannelCount(Constants.Audio.channels),
            interleaved: true
        )!
    }()

    // Output format (from Grok)
    private lazy var outputFormat: AVAudioFormat = {
        AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: Constants.Audio.outputSampleRate,
            channels: AVAudioChannelCount(Constants.Audio.channels),
            interleaved: true
        )!
    }()

    // Audio accumulation for sending in chunks
    private let sendQueue = DispatchQueue(label: "com.jarvis.audio.send")
    private var accumulatedData = Data()
    private let minSendBytes: Int

    // MARK: - Initialization

    override init() {
        self.minSendBytes = Constants.Audio.minSendBytes
        super.init()
        setupAudioSession()
    }

    deinit {
        stopCapture()
        stopPlayback()
    }

    // MARK: - Audio Session Setup

    private func setupAudioSession() {
        do {
            let session = AVAudioSession.sharedInstance()

            // Default to glasses mode (can be changed via setupAudioSession(useIPhoneMode:))
            let mode: AVAudioSession.Mode = .videoChat
            try session.setCategory(.playAndRecord, mode: mode, options: [.defaultToSpeaker, .allowBluetooth])
            try session.setPreferredSampleRate(Constants.Audio.inputSampleRate)
            try session.setActive(true)

            print("[AudioManager] ✅ Audio session configured (\(mode))")
        } catch {
            print("[AudioManager] ❌ Audio session setup failed: \(error)")
            onError?(error)
        }
    }

    /// Configure audio session for specific mode
    func setupAudioSession(useIPhoneMode: Bool) throws {
        self.useIPhoneMode = useIPhoneMode

        let session = AVAudioSession.sharedInstance()

        // .voiceChat = iPhone mode (aggressive echo cancellation)
        // .videoChat = Glasses mode (mic on glasses, speaker on phone)
        let mode: AVAudioSession.Mode = useIPhoneMode ? .voiceChat : .videoChat

        try session.setCategory(.playAndRecord, mode: mode, options: [.defaultToSpeaker, .allowBluetooth])
        try session.setPreferredSampleRate(Constants.Audio.inputSampleRate)
        try session.setActive(true)

        print("[AudioManager] ✅ Audio session configured for \(useIPhoneMode ? "iPhone" : "Glasses") mode")
    }

    // MARK: - Microphone Capture

    /// Start capturing audio from microphone
    func startCapture() throws {
        guard !isCapturing else {
            print("[AudioManager] ⚠️ Already capturing")
            return
        }

        print("[AudioManager] 🎤 Starting microphone capture...")

        // Get input node
        let inputNode = audioEngine.inputNode
        let inputNodeFormat = inputNode.inputFormat(forBus: 0)

        // Install tap to capture audio
        inputNode.installTap(
            onBus: 0,
            bufferSize: Constants.Audio.bufferSize,
            format: inputNodeFormat
        ) { [weak self] buffer, time in
            self?.processInputBuffer(buffer)
        }

        // Start engine
        try audioEngine.start()
        isCapturing = true

        print("[AudioManager] ✅ Microphone capture started")
    }

    /// Stop capturing audio
    func stopCapture() {
        guard isCapturing else { return }

        print("[AudioManager] 🎤 Stopping microphone capture...")

        audioEngine.inputNode.removeTap(onBus: 0)
        audioEngine.stop()
        isCapturing = false

        print("[AudioManager] ✅ Microphone capture stopped")
    }

    // MARK: - Speaker Playback

    /// Play audio received from Grok (PCM Int16, 24kHz)
    func playAudio(data: Data) {
        guard !data.isEmpty else { return }

        // Ensure player node is attached
        if !audioEngine.attachedNodes.contains(playerNode) {
            audioEngine.attach(playerNode)
            audioEngine.connect(playerNode, to: audioEngine.mainMixerNode, format: outputFormat)

            // Start player if not already started
            if !playerNode.isPlaying {
                playerNode.play()
                isPlaying = true
            }
        }

        // Convert Data to AVAudioPCMBuffer
        guard let buffer = createPCMBuffer(from: data, format: outputFormat) else {
            print("[AudioManager] ⚠️ Failed to create PCM buffer for playback")
            return
        }

        // Schedule buffer for playback
        playerNode.scheduleBuffer(buffer, completionCallbackType: .dataPlayedBack) { _ in
            // Buffer played
        }
    }

    /// Stop audio playback
    func stopPlayback() {
        guard isPlaying else { return }

        print("[AudioManager] 🔊 Stopping playback...")

        playerNode.stop()
        if audioEngine.attachedNodes.contains(playerNode) {
            audioEngine.detach(playerNode)
        }
        isPlaying = false

        print("[AudioManager] ✅ Playback stopped")
    }

    // MARK: - Audio Processing

    private func processInputBuffer(_ buffer: AVAudioPCMBuffer) {
        // Convert to Data (PCM Int16)
        guard let audioData = convertBufferToData(buffer) else {
            return
        }

        // Accumulate data and send in chunks
        sendQueue.async { [weak self] in
            guard let self else { return }

            self.accumulatedData.append(audioData)

            // Send when we have enough data (reduces WebSocket overhead)
            if self.accumulatedData.count >= self.minSendBytes {
                let dataToSend = self.accumulatedData
                self.accumulatedData = Data()

                // Resample to 16kHz if needed
                let resampledData = self.resampleIfNeeded(dataToSend, from: buffer.format)

                // Notify callback
                self.onAudioCaptured?(resampledData)
            }
        }
    }

    private func convertBufferToData(_ buffer: AVAudioPCMBuffer) -> Data? {
        guard let channelData = buffer.int16ChannelData else {
            return nil
        }

        let frameLength = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)

        var data = Data(capacity: frameLength * channelCount * MemoryLayout<Int16>.size)
        let samples = UnsafeBufferPointer(start: channelData[0], count: frameLength)

        for sample in samples {
            var value = sample
            data.append(Data(bytes: &value, count: MemoryLayout<Int16>.size))
        }

        return data
    }

    private func resampleIfNeeded(_ data: Data, from sourceFormat: AVAudioFormat) -> Data {
        let sourceSampleRate = sourceFormat.sampleRate
        let targetSampleRate = Constants.Audio.inputSampleRate

        // If already at target rate, no resampling needed
        guard sourceSampleRate != targetSampleRate else {
            return data
        }

        // Perform resampling (simple linear interpolation)
        // For production, consider using vDSP_vgenp for better quality
        let ratio = targetSampleRate / sourceSampleRate
        let sourceCount = data.count / MemoryLayout<Int16>.size
        let targetCount = Int(Double(sourceCount) * ratio)

        var sourceArray = [Int16](repeating: 0, count: sourceCount)
        data.withUnsafeBytes { bytes in
            sourceArray.withUnsafeMutableBytes { destBytes in
                destBytes.copyMemory(from: bytes)
            }
        }

        var targetArray = [Int16](repeating: 0, count: targetCount)
        for i in 0..<targetCount {
            let sourceIndex = Double(i) / ratio
            let lowerIndex = Int(sourceIndex)
            let upperIndex = min(lowerIndex + 1, sourceCount - 1)
            let fraction = sourceIndex - Double(lowerIndex)

            let lower = Double(sourceArray[lowerIndex])
            let upper = Double(sourceArray[upperIndex])
            targetArray[i] = Int16(lower + (upper - lower) * fraction)
        }

        return Data(bytes: targetArray, count: targetCount * MemoryLayout<Int16>.size)
    }

    private func createPCMBuffer(from data: Data, format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let frameCount = data.count / MemoryLayout<Int16>.size / Int(format.channelCount)

        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frameCount)) else {
            return nil
        }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        guard let channelData = buffer.int16ChannelData else {
            return nil
        }

        data.withUnsafeBytes { bytes in
            let source = bytes.bindMemory(to: Int16.self)
            channelData[0].update(from: source.baseAddress!, count: frameCount)
        }

        return buffer
    }
}
