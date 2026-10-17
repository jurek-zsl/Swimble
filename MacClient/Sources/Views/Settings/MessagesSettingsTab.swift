import SwiftUI
import AppKit

/// Native Messages & Notifications configuration tab with 4-channel event routing.
public struct MessagesSettingsTab: View {
    @Bindable public var store: MumbleStore
    @Bindable public var state: SettingsState = SettingsState.shared

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Events Matrix
                SettingsCard {
                    SettingsSectionHeader(
                        "Events Matrix",
                        systemImage: "checklist",
                        subtitle: "Configure notification methods per server and user event."
                    )

                    VStack(spacing: 0) {
                        // Header
                        HStack(spacing: 8) {
                            Text("Event")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("Console")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 58, alignment: .center)

                            Text("Notification")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 76, alignment: .center)

                            Text("TTS")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 48, alignment: .center)

                            Text("Sound")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 54, alignment: .center)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))

                        Divider()

                        // Events Rows
                        ForEach($state.eventsMatrix) { $ev in
                            HStack(spacing: 8) {
                                Text(ev.eventName)
                                    .font(.system(size: 12.5, weight: .medium))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Toggle("", isOn: $ev.console)
                                    .labelsHidden()
                                    .frame(width: 58, alignment: .center)

                                Toggle("", isOn: $ev.notification)
                                    .labelsHidden()
                                    .frame(width: 76, alignment: .center)

                                Toggle("", isOn: $ev.tts)
                                    .labelsHidden()
                                    .frame(width: 48, alignment: .center)

                                Toggle("", isOn: $ev.soundfile)
                                    .labelsHidden()
                                    .frame(width: 54, alignment: .center)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)

                            Divider()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
                    }
                }

                // 2. Sound Cues
                SettingsCard {
                    SettingsSectionHeader(
                        "Sound Cues",
                        systemImage: "speaker.wave.2.circle.fill",
                        subtitle: "Configure default synthesized chimes or a custom audio sound file."
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 24) {
                            ForEach(SoundfileMode.allCases) { mode in
                                HStack(spacing: 6) {
                                    Image(systemName: state.soundfileMode == mode ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(state.soundfileMode == mode ? store.accentTint : .secondary)
                                    Text(mode.rawValue)
                                        .font(.body)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    state.soundfileMode = mode
                                }
                            }
                        }

                        if state.soundfileMode == .customSound {
                            HStack(spacing: 12) {
                                TextField("Sound file path...", text: $state.customSoundFilePath)
                                    .textFieldStyle(.roundedBorder)

                                Button("Browse...") {
                                    pickSoundFile { path in state.customSoundFilePath = path }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button("Preview") {
                                    SoundManager.shared.playPermissionDenied()
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                }

                // 3. Text-To-Speech Options
                SettingsCard {
                    SettingsSectionHeader(
                        "Text-To-Speech Options",
                        systemImage: "person.wave.2.fill",
                        subtitle: "Synthesize chat messages and activity using macOS Speech Synthesizer."
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("TTS Volume:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(state.ttsVolumePercent))%")
                                .font(.subheadline.monospacedDigit().bold())
                        }
                        Slider(value: $state.ttsVolumePercent, in: 0.0...100.0, step: 5.0)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Length Threshold")
                                .font(.subheadline.bold())
                            Text("Skip TTS reading for messages longer than this character count.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Stepper("\(state.ttsLengthThreshold) Characters", value: $state.ttsLengthThreshold, in: 50...500, step: 25)
                            .font(.caption.monospacedDigit())
                    }

                    Divider()

                    SettingsToggleRow(
                        "Read Message Text Instead of Event Name",
                        subtitle: "Speaks the body content of incoming text messages rather than a generic alert.",
                        isOn: $state.ttsReadMessageText
                    )
                }

                // 4. Chat Log History
                SettingsCard {
                    SettingsSectionHeader(
                        "Chat Log History",
                        systemImage: "bubble.left.and.bubble.right.fill",
                        subtitle: "Message buffer limits preserved in client memory."
                    )

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Max Message Count")
                                .font(.subheadline.bold())
                            Text("Maximum number of chat lines retained in memory before older entries are pruned.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Stepper("\(state.maxChatBlockCount) Lines", value: $state.maxChatBlockCount, in: 500...20000, step: 500)
                            .font(.caption.monospacedDigit())
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private func pickSoundFile(completion: @escaping (String) -> Void) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.audio, .mp3, .wav, .aiff]
        if panel.runModal() == .OK, let url = panel.url {
            completion(url.path)
        }
    }
}
