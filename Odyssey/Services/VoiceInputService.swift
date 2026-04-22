import Foundation
import AppKit
import Speech
import AVFoundation
import Observation
import os.log

private let logger = Logger(subsystem: "com.shaycohen.odyssey", category: "VoiceInput")

// @preconcurrency suppresses Sendable conformance errors for Speech types that were
// not annotated before Swift 6. SFSpeechAudioBufferRecognitionRequest is an NSObject
// subclass used from multiple threads by design — safe to treat as @unchecked Sendable.
@preconcurrency import Speech

@MainActor
@Observable
final class VoiceInputService: NSObject {
    // MARK: - Published state
    var isRecording: Bool = false
    var partialTranscript: String = ""
    var audioLevel: Float = 0.0
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
        // Bring Odyssey to front so TCC dialogs appear over other windows.
        NSApplication.shared.activate(ignoringOtherApps: true)

        let speechBefore = SFSpeechRecognizer.authorizationStatus().rawValue
        let micBefore = AVCaptureDevice.authorizationStatus(for: .audio).rawValue
        logger.info("requestPermissions: speech=\(speechBefore) mic=\(micBefore)")

        let speechStatus = await Self.requestSpeechAuthorization()
        logger.info("requestPermissions: speechAfter=\(speechStatus.rawValue)")
        guard speechStatus == .authorized else {
            permissionGranted = false
            let diag = "speech_before=\(speechBefore) mic_before=\(micBefore) speech_result=\(speechStatus.rawValue)"
            try? diag.write(toFile: "/tmp/odyssey_voice_diag.txt", atomically: true, encoding: .utf8)
            error = VoiceInputError.speechDenied(code: speechStatus.rawValue)
            return false
        }

        let micGranted = await Self.requestMicrophoneAccess()
        logger.info("requestPermissions: micAfter=\(micGranted)")
        if !micGranted {
            let diag = "speech_ok mic_before=\(micBefore) mic_result=false"
            try? diag.write(toFile: "/tmp/odyssey_voice_diag.txt", atomically: true, encoding: .utf8)
            error = VoiceInputError.micDenied
        }
        permissionGranted = micGranted
        return micGranted
    }

    private nonisolated static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private nonisolated static func requestMicrophoneAccess() async -> Bool {
        // Use AVAudioApplication on macOS 14+ (recommended for audio recording).
        if #available(macOS 14.0, *) {
            return await withCheckedContinuation { continuation in
                AVAudioApplication.requestRecordPermission { granted in
                    continuation.resume(returning: granted)
                }
            }
        }
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    // MARK: - Recording
    func startRecording() async {
        logger.info("startRecording: isRecording=\(self.isRecording) permissionGranted=\(self.permissionGranted)")
        guard !isRecording else { return }

        if !permissionGranted {
            logger.info("startRecording: requesting permissions")
            let granted = await requestPermissions()
            guard granted else {
                logger.error("startRecording: permission denied — \(self.error?.localizedDescription ?? "unknown")")
                // error already set by requestPermissions()
                return
            }
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            logger.error("startRecording: recognizer unavailable")
            self.error = VoiceInputError.recognizerUnavailable
            return
        }

        logger.info("startRecording: starting audio engine")
        do {
            try await startAudioEngine(recognizer: recognizer)
            logger.info("startRecording: audio engine started, isRecording=\(self.isRecording)")
        } catch {
            logger.error("startRecording: audio engine error: \(error.localizedDescription)")
            self.error = error
        }
    }

    func stopRecording() async -> String {
        logger.info("stopRecording: isRecording=\(self.isRecording) transcript='\(self.partialTranscript)'")
        guard isRecording else { return partialTranscript }

        audioEngine.stop()
        if tapInstalled {
            audioEngine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
            logger.debug("stopRecording: tap removed")
        }
        // Signal end of audio — recognizer will deliver a final result asynchronously
        recognitionRequest?.endAudio()

        // Wait briefly for the recognition callback to set partialTranscript with the
        // final result. Without this, stopRecording() reads partialTranscript before
        // the callback fires and returns empty string.
        try? await Task.sleep(for: .milliseconds(400))

        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isRecording = false
        audioLevel = 0.0

        let result = partialTranscript
        logger.info("stopRecording: done, returning '\(result)'")
        // Don't clear partialTranscript here — ChatView reads it to inject into text field
        return result
    }

    // MARK: - Private implementation
    private func startAudioEngine(recognizer: SFSpeechRecognizer) async throws {
        logger.debug("startAudioEngine: resetting state")
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
        logger.info("startAudioEngine: format sampleRate=\(recordingFormat.sampleRate) channels=\(recordingFormat.channelCount)")

        guard recordingFormat.sampleRate > 0 else {
            logger.error("startAudioEngine: no microphone input (sampleRate=0)")
            throw VoiceInputError.audioFormatUnavailable
        }

        // @Sendable updater: safe to call from any thread — dispatches to main actor
        let levelUpdater: @Sendable (Float) -> Void = { [weak self] level in
            Task { @MainActor [weak self] in self?.audioLevel = level }
        }

        // CRITICAL: The tap block MUST be created in a nonisolated context.
        // In Swift 6, any closure defined inside a @MainActor function is inferred as
        // @MainActor-isolated — the compiler inserts swift_task_isCurrentExecutorWithFlagsImpl
        // at the start. AVFAudio calls the tap on a realtime audio thread which is NOT the
        // main actor, so the executor check fires → EXC_BREAKPOINT (_dispatch_assert_queue_fail).
        // Solution: create the block via a nonisolated static method so it has no actor context.
        tapInstalled = true
        logger.debug("startAudioEngine: installing tap")
        inputNode.installTap(
            onBus: 0,
            bufferSize: 1024,
            format: recordingFormat,
            block: Self.makeTapBlock(request: request, levelUpdater: levelUpdater)
        )

        audioEngine.prepare()
        try audioEngine.start()
        isRecording = true
        logger.info("startAudioEngine: engine started")

        recognitionTask = recognizer.recognitionTask(with: request) { result, error in
            // This callback can arrive on any thread. We only schedule work on @MainActor
            // via Task — we do NOT touch self directly here to avoid actor isolation issues.
            if let result {
                let text = result.bestTranscription.formattedString
                Task { @MainActor [weak self] in
                    self?.partialTranscript = text
                }
            }
            if let error {
                let nsError = error as NSError
                // Log the exact domain+code so we can identify all lifecycle errors
                logger.info("startAudioEngine: recognition error domain='\(nsError.domain)' code=\(nsError.code) msg='\(nsError.localizedDescription)'")
                // Suppress ALL speech/assistant recognition lifecycle errors — these are
                // expected (no speech, cancelled, timeout) and the user just tries again.
                // Only surface errors from outside the speech recognition stack.
                let speechDomains: Set<String> = [
                    "kAFAssistantErrorDomain",
                    "com.apple.SFSpeechRecognitionError",
                    "SFSpeechRecognitionErrorDomain"
                ]
                guard !speechDomains.contains(nsError.domain) else { return }
                Task { @MainActor [weak self] in self?.error = error }
            }
        }
    }

    // nonisolated static: the closure returned here is created in a nonisolated context.
    // Swift 6 does NOT attach @MainActor isolation to it, so AVFAudio's realtime thread
    // can invoke it without triggering swift_task_isCurrentExecutorWithFlagsImpl.
    private nonisolated static func makeTapBlock(
        request: SFSpeechAudioBufferRecognitionRequest,
        levelUpdater: @escaping @Sendable (Float) -> Void
    ) -> AVAudioNodeTapBlock {
        return { buffer, _ in
            request.append(buffer)
            guard let channelData = buffer.floatChannelData?[0] else { return }
            let frameCount = Int(buffer.frameLength)
            guard frameCount > 0 else { return }
            var rms: Float = 0.0
            for i in 0..<frameCount {
                rms += channelData[i] * channelData[i]
            }
            rms = sqrt(rms / Float(frameCount))
            levelUpdater(min(rms * 10.0, 1.0))
        }
    }
}

// MARK: - Errors
enum VoiceInputError: LocalizedError {
    case permissionDenied
    case speechDenied(code: Int)
    case micDenied
    case recognizerUnavailable
    case audioFormatUnavailable

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Voice permission denied. Check System Settings → Privacy & Security."
        case .speechDenied(let code):
            return "Speech recognition denied (status=\(code), 0=notDetermined 1=denied 2=restricted 3=authorized). Enable Odyssey in System Settings → Privacy & Security → Speech Recognition."
        case .micDenied:
            return "Microphone access denied. Enable Odyssey in System Settings → Privacy & Security → Microphone."
        case .recognizerUnavailable:
            return "Speech recognition is not available on this device."
        case .audioFormatUnavailable:
            return "No microphone input is available. Please connect a microphone and try again."
        }
    }
}
