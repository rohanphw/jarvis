import Foundation
import Speech
import AVFoundation
import Combine

/// Manager for iOS speech recognition
///
/// Handles:
/// - Real-time speech-to-text
/// - Voice activity detection
/// - Microphone access
class SpeechRecognitionManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    /// Whether currently listening
    @Published var isListening: Bool = false

    /// Current recognized text (real-time)
    @Published var recognizedText: String = ""

    // MARK: - Callbacks

    /// Called when speech recognition starts
    var onSpeechStart: (() -> Void)?

    /// Called with partial transcription updates
    var onTranscriptUpdate: ((String) -> Void)?

    /// Called when speech recognition ends with final transcript
    var onSpeechEnd: ((String) -> Void)?

    /// Called on error
    var onError: ((Error) -> Void)?

    // MARK: - Private Properties

    private let speechRecognizer: SFSpeechRecognizer
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    private var silenceTimer: Timer?
    private let silenceThreshold: TimeInterval = 1.5 // 1.5s of silence = end

    // MARK: - Initialization

    override init() {
        // Use device locale or fallback to English
        self.speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US")) ?? SFSpeechRecognizer()!
        super.init()

        print("[SpeechRecognition] Initialized with locale: \(speechRecognizer.locale.identifier)")
    }

    // MARK: - Permission

    /// Request speech recognition permission
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                let granted = (status == .authorized)
                print("[SpeechRecognition] Permission: \(granted ? "✅ Granted" : "❌ Denied")")
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Start/Stop Listening

    /// Start listening for speech
    func startListening() throws {
        // Cancel any existing task
        stopListening()

        guard speechRecognizer.isAvailable else {
            throw SpeechError.recognizerNotAvailable
        }

        // Configure audio session
        let audioSession = AVAudioSession.sharedInstance()
        try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)

        // Create recognition request
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        guard let recognitionRequest = recognitionRequest else {
            throw SpeechError.unableToCreateRequest
        }

        recognitionRequest.shouldReportPartialResults = true
        recognitionRequest.requiresOnDeviceRecognition = false // Use server for better accuracy

        // Configure audio engine
        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        try audioEngine.start()

        // Start recognition task
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { [weak self] result, error in
            guard let self = self else { return }

            if let result = result {
                let transcript = result.bestTranscription.formattedString

                Task { @MainActor in
                    self.recognizedText = transcript
                    self.onTranscriptUpdate?(transcript)

                    // Reset silence timer on new speech
                    self.resetSilenceTimer()

                    // Notify speech start on first word
                    if !self.isListening {
                        self.isListening = true
                        self.onSpeechStart?()
                        print("[SpeechRecognition] 🎤 Speech started")
                    }
                }

                // If result is final, stop
                if result.isFinal {
                    Task { @MainActor in
                        self.stopListening()
                        self.onSpeechEnd?(transcript)
                        print("[SpeechRecognition] ✅ Final: \(transcript)")
                    }
                }
            }

            if let error = error {
                print("[SpeechRecognition] ❌ Error: \(error.localizedDescription)")
                Task { @MainActor in
                    self.onError?(error)
                    self.stopListening()
                }
            }
        }

        print("[SpeechRecognition] 🎤 Listening started")
    }

    /// Stop listening
    func stopListening() {
        silenceTimer?.invalidate()
        silenceTimer = nil

        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)

        recognitionRequest?.endAudio()
        recognitionRequest = nil

        recognitionTask?.cancel()
        recognitionTask = nil

        isListening = false

        print("[SpeechRecognition] ⏹️ Listening stopped")
    }

    // MARK: - Silence Detection

    private func resetSilenceTimer() {
        silenceTimer?.invalidate()

        silenceTimer = Timer.scheduledTimer(withTimeInterval: silenceThreshold, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            Task { @MainActor in
                let finalText = self.recognizedText
                self.stopListening()
                self.onSpeechEnd?(finalText)
                print("[SpeechRecognition] 🔇 Silence detected, final: \(finalText)")
            }
        }
    }
}

// MARK: - Errors

enum SpeechError: LocalizedError {
    case recognizerNotAvailable
    case unableToCreateRequest
    case permissionDenied

    var errorDescription: String? {
        switch self {
        case .recognizerNotAvailable:
            return "Speech recognizer not available"
        case .unableToCreateRequest:
            return "Unable to create recognition request"
        case .permissionDenied:
            return "Speech recognition permission denied"
        }
    }
}
