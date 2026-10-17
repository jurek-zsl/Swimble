import SwiftUI
import AppKit

/// Native Audio Output configuration tab tailored for macOS 26 CoreAudio & Apple Silicon.
public struct AudioOutputSettingsTab: View {
    @Bindable public var store: MumbleStore
    @Bindable public var state: SettingsState = SettingsState.shared
    private var deviceManager = CoreAudioDeviceManager.shared

    public init(store: MumbleStore) {
        self.store = store
    }

    private var isLoopbackActive: Bool {
        store.audioEngine?.isLoopbackTestEnabled == true
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Output Hardware
                SettingsCard {
                    SettingsSectionHeader(
                        "Output Device",
                        systemImage: "speaker.wave.3.fill",
                        subtitle: "Configure speaker or headphone output hardware."
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Output Device")
                            .font(.subheadline.bold())
                        Picker("Device", selection: $state.audioOutputDevice) {
                            Text("Default Device").tag("")
                            ForEach(deviceManager.outputDevices) { dev in
                                Text(dev.name).tag(dev.name)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }
                }

                // 2. Volume & Jitter Buffer
                SettingsCard {
                    SettingsSectionHeader(
                        "Playback & Buffering",
                        systemImage: "waveform.path.ecg",
                        subtitle: "Network jitter buffering and master listening volume."
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Master Output Volume:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(state.outputVolumePercent))%")
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(store.accentTint)
                        }
                        Slider(value: $state.outputVolumePercent, in: 0.0...200.0, step: 1.0)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Default Jitter Buffer:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(state.defaultJitterBufferMs)) ms")
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(store.accentTint)
                        }
                        Slider(value: $state.defaultJitterBufferMs, in: 10.0...100.0, step: 5.0)

                        Text("Higher values cushion against network packet jitter at the expense of slight latency.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                // 3. Audio Ducking
                SettingsCard {
                    SettingsSectionHeader(
                        "Audio Ducking",
                        systemImage: "speaker.badge.waveform.fill",
                        subtitle: "Automatically lower background applications when participants speak."
                    )

                    SettingsToggleRow(
                        "Duck Background Audio During Calls",
                        subtitle: "Uses macOS VoiceProcessingIO to automatically quiet background music, videos, and games while voice is being spoken.",
                        isOn: $state.audioDuckingEnabled
                    )
                }

                // 4. Local Loopback Microphone Test
                SettingsCard {
                    SettingsSectionHeader(
                        "Local Loopback Test",
                        systemImage: "arrow.triangle.2.circlepath",
                        subtitle: "Listen to your own voice to calibrate microphone clarity and volume."
                    )

                    HStack(alignment: .center) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(isLoopbackActive ? "Loopback Test Active" : "Loopback Test Inactive")
                                .font(.subheadline.bold())
                                .foregroundStyle(isLoopbackActive ? .green : .primary)
                            Text("Directly routes your microphone audio back to your headphones with zero server latency.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(action: toggleLoopback) {
                            HStack(spacing: 6) {
                                if isLoopbackActive {
                                    Image(systemName: "waveform")
                                        .symbolEffect(.variableColor.iterative)
                                    Text("Stop Test")
                                } else {
                                    Image(systemName: "play.fill")
                                    Text("Start Test")
                                }
                            }
                            .frame(minWidth: 100)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isLoopbackActive ? .red : store.accentTint)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    private func toggleLoopback() {
        if isLoopbackActive {
            state.loopbackMode = .none
            store.audioEngine?.isLoopbackTestEnabled = false
        } else {
            state.loopbackMode = .local
            store.audioEngine?.isLoopbackTestEnabled = true
        }
    }
}
