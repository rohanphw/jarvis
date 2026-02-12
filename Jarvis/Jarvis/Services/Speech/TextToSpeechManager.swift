import Foundation
import AVFoundation
import Combine

/// Manager for iOS text-to-speech
///
/// Handles:
/// - Speaking text responses
/// - Voice configuration
/// - Playback control
class TextToSpeechManager: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {

    // MARK: - Published Properties

    /// Whether currently speaking
    @Published var isSpeaking: Bool = false

    // MARK: - Callbacks

    /// Called when speech starts
    var onSpeechStart: (() -> Void)?

    /// Called when speech finishes
    var onSpeechFinish: (() -> Void)?

    // MARK: - Private Properties

    private let synthesizer = AVSpeechSynthesizer()
    private var speechRate: Float = 0.52 // Slightly faster for natural conversation
    private var selectedVoice: AVSpeechSynthesisVoice?

    // MARK: - Initialization

    override init() {
        super.init()
        synthesizer.delegate = self

        // Try to use premium female voices for better quality
        // Priority: Premium British female > Premium US female > Enhanced US female > Default
        if let premiumVoice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-GB.Serena") {
            selectedVoice = premiumVoice
            print("[TextToSpeech] ✅ Using premium British female voice: Serena")
        } else if let premiumUSVoice = AVSpeechSynthesisVoice(identifier: "com.apple.voice.premium.en-US.Zoe") {
            selectedVoice = premiumUSVoice
            print("[TextToSpeech] ✅ Using premium US female voice: Zoe")
        } else if let enhancedVoice = AVSpeechSynthesisVoice(identifier: "com.apple.ttsbundle.Samantha-compact") {
            selectedVoice = enhancedVoice
            print("[TextToSpeech] ✅ Using enhanced US female voice: Samantha")
        } else {
            // Fallback to best available en-US female voice
            selectedVoice = AVSpeechSynthesisVoice(language: "en-US")
            print("[TextToSpeech] ℹ️ Using standard US female voice")
        }

        print("[TextToSpeech] Initialized")
    }

    // MARK: - Speak

    /// Speak text
    func speak(_ text: String) {
        // Stop any current speech
        stop()

        // Configure audio session for playback
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
            try audioSession.setActive(true)
        } catch {
            print("[TextToSpeech] ⚠️ Audio session error: \(error)")
        }

        // Create utterance
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = selectedVoice
        utterance.rate = speechRate
        utterance.pitchMultiplier = 0.95 // Slightly lower pitch for more authoritative tone
        utterance.volume = 1.0
        utterance.preUtteranceDelay = 0.1 // Small delay for natural pacing

        // Speak
        synthesizer.speak(utterance)

        print("[TextToSpeech] 🔊 Speaking: \(text)")
    }

    /// Stop speaking
    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            print("[TextToSpeech] ⏹️ Stopped")
        }
    }

    /// Pause speaking
    func pause() {
        if synthesizer.isSpeaking {
            synthesizer.pauseSpeaking(at: .immediate)
            print("[TextToSpeech] ⏸️ Paused")
        }
    }

    /// Resume speaking
    func resume() {
        if synthesizer.isPaused {
            synthesizer.continueSpeaking()
            print("[TextToSpeech] ▶️ Resumed")
        }
    }

    // MARK: - Configuration

    /// Set speech rate (0.0 = slowest, 1.0 = fastest)
    func setSpeechRate(_ rate: Float) {
        speechRate = max(0.0, min(1.0, rate))
        print("[TextToSpeech] ⚙️ Speech rate: \(speechRate)")
    }

    // MARK: - AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = true
            onSpeechStart?()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
            onSpeechFinish?()
            print("[TextToSpeech] ✅ Finished")
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            isSpeaking = false
        }
    }
}
