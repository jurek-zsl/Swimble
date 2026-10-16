import SwiftUI
import AVFoundation

/// Text-to-Speech configuration dialog allowing users to have chat messages and channel activity read aloud.
public struct TTSModal: View {
    @Bindable public var store: MumbleStore
    @Environment(\.dismiss) private var dismiss

    private var tts: TTSEngine {
        TTSEngine.shared
    }

    private var availableVoices: [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices().filter { $0.language.starts(with: "en") }
    }

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "speaker.wave.3.fill")
                        .font(.title2)
                        .foregroundStyle(store.accentTint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Text-to-Speech (TTS)")
                            .font(.headline.bold())
                        Text("Have chat messages and channel activity spoken aloud.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // 1. Master Toggle Card
                    VStack(alignment: .leading, spacing: 12) {
                        SettingsToggleRow(
                            "Enable Text-to-Speech",
                            subtitle: "Uses Apple speech synthesis to speak events in real-time.",
                            isOn: Binding(
                                get: { tts.isEnabled },
                                set: { tts.isEnabled = $0 }
                            )
                        )

                        if tts.isEnabled {
                            Divider()

                            SettingsToggleRow(
                                "Read Incoming Chat Messages",
                                subtitle: "Speaks incoming text messages as they arrive in your channel.",
                                isOn: Binding(
                                    get: { tts.readChatMessages },
                                    set: { tts.readChatMessages = $0 }
                                )
                            )

                            SettingsToggleRow(
                                "Read Channel Join & Leave Events",
                                subtitle: "Announces when users enter or exit your voice channel.",
                                isOn: Binding(
                                    get: { tts.readChannelEvents },
                                    set: { tts.readChannelEvents = $0 }
                                )
                            )
                        }
                    }
                    .padding(14)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                    .overlay {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }

                    // 2. Voice & Controls
                    if tts.isEnabled {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Speech Voice & Speed")
                                .font(.subheadline.bold())

                            // Voice Selector
                            Picker("Voice", selection: Binding(
                                get: { tts.selectedVoiceIdentifier },
                                set: { tts.selectedVoiceIdentifier = $0 }
                            )) {
                                Text("Default System Voice").tag("")
                                ForEach(availableVoices, id: \.identifier) { voice in
                                    Text("\(voice.name) (\(voice.language))").tag(voice.identifier)
                                }
                            }

                            // Speech Rate
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("Speech Rate")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text(String(format: "%.2fx", tts.speechRate * 2))
                                        .font(.caption.monospacedDigit())
                                }
                                Slider(value: Binding(
                                    get: { Double(tts.speechRate) },
                                    set: { tts.speechRate = Float($0) }
                                ), in: 0.25...0.75)
                            }

                            // Volume
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("TTS Volume")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(Int(tts.speechVolume * 100))%")
                                        .font(.caption.monospacedDigit())
                                }
                                Slider(value: Binding(
                                    get: { Double(tts.speechVolume) },
                                    set: { tts.speechVolume = Float($0) }
                                ), in: 0.1...1.0)
                            }

                            Divider()

                            Button {
                                tts.speak("This is a preview of Swimble Text to Speech.")
                            } label: {
                                Label("Play Sample Speech", systemImage: "play.circle.fill")
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(14)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                        .overlay {
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 480, height: 460)
    }
}
