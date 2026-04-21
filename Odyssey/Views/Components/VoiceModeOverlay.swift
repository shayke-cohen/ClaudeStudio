import SwiftUI

struct VoiceModeOverlay: View {
    @Environment(AppState.self) private var appState

    // Hold gesture state
    @State private var isHolding: Bool = false

    var statusText: String {
        if appState.voiceInput.isRecording { return "🔴 Recording…" }
        if appState.tts.isSpeaking { return "🔊 Speaking…" }
        return "Hold 🎤 to speak"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Banner strip
            HStack(spacing: 10) {
                // Voice mode chip
                Text("🎙 Voice Mode")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.accentColor.opacity(0.2))
                    .overlay(RoundedRectangle(cornerRadius: 20).stroke(Color.accentColor.opacity(0.35), lineWidth: 1))
                    .cornerRadius(20)

                // Level bars
                LevelBarsView(audioLevel: appState.voiceInput.audioLevel, isActive: appState.voiceInput.isRecording || appState.tts.isSpeaking)
                    .frame(maxWidth: .infinity)

                // Status text
                Text(statusText)
                    .font(.system(size: 11))
                    .foregroundStyle(Color.accentColor)
                    .frame(minWidth: 110, alignment: .trailing)

                // Exit button
                Button("✕ Exit") {
                    appState.isVoiceModeActive = false
                    if appState.voiceInput.isRecording {
                        Task { await appState.voiceInput.stopRecording() }
                    }
                    appState.tts.stop()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityIdentifier("voiceMode.exitButton")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.accentColor.opacity(0.06))
            .overlay(Rectangle().frame(height: 1).foregroundStyle(Color.accentColor.opacity(0.2)), alignment: .bottom)
            .accessibilityIdentifier("voiceMode.banner")

            // Partial transcript while recording
            if appState.voiceInput.isRecording, !appState.voiceInput.partialTranscript.isEmpty {
                Text(appState.voiceInput.partialTranscript)
                    .font(.system(size: 13))
                    .italic()
                    .foregroundStyle(Color.accentColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            }

            // Centered large mic button
            HStack {
                Spacer()
                Button {} label: {
                    Image(systemName: appState.voiceInput.isRecording ? "waveform" : "mic")
                        .font(.system(size: 28))
                        .foregroundStyle(appState.voiceInput.isRecording ? Color.red : (appState.tts.isSpeaking ? Color.secondary : Color.primary))
                        .frame(width: 56, height: 56)
                        .background(Circle().fill(appState.voiceInput.isRecording ? Color.red.opacity(0.12) : Color.primary.opacity(0.06)))
                        .overlay(Circle().stroke(appState.voiceInput.isRecording ? Color.red.opacity(0.5) : Color.secondary.opacity(0.3), lineWidth: 1.5))
                }
                .buttonStyle(.plain)
                .disabled(appState.tts.isSpeaking)
                .simultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            guard !appState.voiceInput.isRecording, !appState.tts.isSpeaking else { return }
                            Task { await appState.voiceInput.startRecording() }
                        }
                        .onEnded { _ in
                            guard appState.voiceInput.isRecording else { return }
                            Task {
                                // In voice mode: auto-send on release
                                let transcript = await appState.voiceInput.stopRecording()
                                if !transcript.isEmpty {
                                    // Signal ChatView to send via a notification since
                                    // VoiceModeOverlay doesn't have access to sendMessage()
                                    NotificationCenter.default.post(
                                        name: .voiceModeAutoSend,
                                        object: nil,
                                        userInfo: ["transcript": transcript]
                                    )
                                }
                            }
                        }
                )
                .accessibilityIdentifier("voiceMode.micButton")
                .accessibilityLabel("Hold to record, release to send")
                Spacer()
            }
            .padding(.vertical, 12)

            Text(appState.tts.isSpeaking ? "Listening to response — mic ready when done" : "Hold to record · Release to send automatically")
                .font(.system(size: 10))
                .foregroundStyle(Color.secondary)
                .padding(.bottom, 8)
        }
    }
}

// MARK: - Level Bars
private struct LevelBarsView: View {
    let audioLevel: Float
    let isActive: Bool

    var body: some View {
        TimelineView(.animation) { timeline in
            let phase = isActive ? timeline.date.timeIntervalSinceReferenceDate * 3.0 : 0
            HStack(alignment: .center, spacing: 2) {
                ForEach(0..<10, id: \.self) { i in
                    let offsets: [Double] = [0, 0.63, 1.26, 1.89, 0.31, 0.94, 1.57, 2.20, 0.47, 1.10]
                    let wave = sin(phase + offsets[i]) * 0.5 + 0.5
                    let base: CGFloat = 3
                    let maxH: CGFloat = 18
                    let level = isActive ? CGFloat(max(audioLevel, 0.15)) : 0
                    let height = base + (maxH - base) * level * CGFloat(wave)
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(isActive ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 3, height: max(base, height))
                }
            }
        }
    }
}

// MARK: - Notification name
extension Notification.Name {
    static let voiceModeAutoSend = Notification.Name("odyssey.voiceModeAutoSend")
}
