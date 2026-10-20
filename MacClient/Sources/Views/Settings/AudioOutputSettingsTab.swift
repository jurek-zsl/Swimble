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

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                PositionalAudioSettings(store: store)
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
                                Text(dev.name).tag(dev.uid)
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

                SettingsCard {
                    SettingsSectionHeader("Spatial Audio", systemImage: "spatialaudio",
                                          subtitle: "Stereo headphones or speakers are required.")
                    SettingsToggleRow("Spatial Placement of Channel Speakers",
                                      subtitle: "Assigns each speaker a stable position across the stereo field.",
                                      isOn: $state.spatialAudioEnabled)
                    SettingsToggleRow("Mumble Link Game Positioning",
                                      subtitle: "Shares your avatar position and game identity with the server. Compatible native games use /MumbleLink.<uid>; matching game contexts receive 3D direction and distance audio. No head tracking.",
                                      isOn: $state.mumbleLinkEnabled)
                }

                // 3. Audio Ducking
                SettingsCard {
                    SettingsSectionHeader(
                        "Audio Ducking",
                        systemImage: "speaker.badge.waveform.fill",
                        subtitle: "Automatically lower background applications when participants speak."
                    )

                    SettingsToggleRow(
                        "Duck Background Audio When Someone Speaks",
                        subtitle: "Uses macOS voice processing to lower other audio during local or remote speech, then restore it during silence. This enables voice processing.",
                        isOn: $state.audioDuckingEnabled
                    )
                }

                SettingsCard {
                    Picker("Microphone test", selection: $state.loopbackMode) {
                        ForEach(LoopbackMode.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .onChange(of: state.loopbackMode) { _, mode in
                        store.client.setLoopbackMode(mode: mode == .server ? 2 : mode == .local ? 1 : 0)
                    }
                    Text("Server test requires a connection and uses Mumble's loopback voice target. Local test also works offline.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

}
