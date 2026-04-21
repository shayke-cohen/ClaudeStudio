import Foundation
import Speech
import AVFoundation
import Observation

@MainActor
@Observable
final class VoiceInputService: NSObject {
    // MARK: - Published state
    var isRecording: Bool = false
    var partialTranscript: String = ""
    var audioLevel: Float = 0.0   // 0.0–1.0, for waveform animation
    var permissionGranted: Bool = false
    var error: Error?

    // MARK: - Private
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale.current)
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var tapInstalled = false

    // MARK: - Permissions
    func requestPermissions() async -> Bool {
        // Only gate on speech recognition — on macOS the microphone TCC dialog
        // appears automatically when AVAudioEngine.start() is called, so we don't
        // need a separate AVCaptureDevice.requestAccess call here.
        // nonisolated static helper keeps the continuation off @MainActor so the
        // TCC background callback doesn't trigger _dispatch_assert_queue_fail.
        let speechStatus = await Self.requestSpeechAuthorization()
        permissionGranted = (speechStatus == .authorized)
        return permissionGranted
    }

    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    // MARK: - Recording
    func startRecording() async {
        guard !isRecording else { return }

        if !permissionGranted {
            let granted = await requestPermissions()
            guard granted else {
                self.error = VoiceInputError.permissionDenied
                return
            }
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            self.error = VoiceInputError.recognizerUnavailable
            return
        }

        do {
            try await startAudioEngine(recognizer: recognizer)
        } catch {
            self.error = error
        }
    }

    func stopRecording() async -> String {
        guard isRecording else { return partialTranscript }

        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()

        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        audioLevel = 0.0

        let result = partialTranscript
        // Don't clear partialTranscript here — ChatView reads it to inject into text field
        return result
    }

    // MARK: - Private implementation
    private func startAudioEngine(recognizer: SFSpeechRecognizer) async throws {
        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
        recognitionRequest = nil
        recognitionTask?.cancel()
        recognitionTask = nil
        partialTranscript = ""
        error = nil

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = inputNode.outputFormat(forBus: 0)

        guard recordingFormat.sampleRate > 0 else {
            throw VoiceInputError.audioFormatUnavailable
        }

        tapInstalled = true
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            guard let self else { return }
            request.append(buffer)

            // Compute RMS audio level for waveform animation
            let channelData = buffer.floatChannelData?[0]
            let frameCount = Int(buffer.frameLength)
            if let channelData, frameCount > 0 {
                var rms: Float = 0.0
                for i in 0..<frameCount {
                    rms += channelData[i] * channelData[i]
                }
                rms = sqrt(rms / Float(frameCount))
                let normalized = min(rms * 10.0, 1.0)
                Task { @MainActor [weak self] in
                    self?.audioLevel = normalized
                }
            }
        }

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let result {
                    self.partialTranscript = result.bestTranscription.formattedString
                }
                if let error {
                    // Ignore cancellation errors (triggered by stopRecording)
                    let nsError = error as NSError
                    if nsError.domain != "kAFAssistantErrorDomain" || nsError.code != 216 {
                        self.error = error
                    }
                }
            }
        }
    }
}

// MARK: - Errors
enum VoiceInputError: LocalizedError {
    case permissionDenied
    case recognizerUnavailable
    case audioFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone or speech recognition permission was denied."
        case .recognizerUnavailable:
            return "Speech recognition is not available on this device."
        case .audioFormatUnavailable:
            return "No microphone input is available. Please connect a microphone and try again."
        }
    }
}
