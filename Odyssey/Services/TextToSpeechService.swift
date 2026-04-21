import Foundation
import AVFoundation
import Observation

@MainActor
@Observable
final class TextToSpeechService: NSObject {
    // MARK: - Published state
    var isSpeaking: Bool = false
    var currentMessageId: UUID? = nil  // which bubble is currently being spoken

    // MARK: - Settings (read from AppStorage — passed in from caller)
    // Voice and rate are applied per-utterance from UserDefaults directly

    // MARK: - Private
    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    // MARK: - Public API
    func speak(_ text: String, messageId: UUID) {
        // Cancel any in-flight speech first
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }

        let utterance = AVSpeechUtterance(string: text)

        // Apply user's voice preference
        let voiceIdentifier = UserDefaults.standard.string(forKey: "voice.voiceIdentifier")
        if let id = voiceIdentifier, let voice = AVSpeechSynthesisVoice(identifier: id) {
            utterance.voice = voice
        }

        // Apply user's rate preference (stored as Float, default to 0.5 = normal)
        let rate = UserDefaults.standard.object(forKey: "voice.speakingRate") as? Float ?? AVSpeechUtteranceDefaultSpeechRate
        utterance.rate = max(AVSpeechUtteranceMinimumSpeechRate, min(AVSpeechUtteranceMaximumSpeechRate, rate))

        currentMessageId = messageId
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        // delegate didFinish/didCancel will update isSpeaking and currentMessageId
    }
}

// MARK: - AVSpeechSynthesizerDelegate
extension TextToSpeechService: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = false
            self?.currentMessageId = nil
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor [weak self] in
            self?.isSpeaking = false
            self?.currentMessageId = nil
        }
    }
}
