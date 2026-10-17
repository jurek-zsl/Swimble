import SwiftUI
import AppKit

/// Comprehensive Audio Output configuration tab matching official Mumble specs.
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
                // 1. Interface
                SettingsCard {
                    SettingsSectionHeader(
                        "Interface",
                        systemImage: "speaker.wave.3.fill",
                        subtitle: "Configure speaker output hardware and buffer delay."
                    )

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("System")
                                .font(.subheadline.bold())
                            Picker("System", selection: $state.audioOutputSystem) {
                                Text("CoreAudio").tag("CoreAudio")
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Device")
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

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Output Delay:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(state.outputDelayMs)) ms")
                                .font(.caption.monospacedDigit().bold())
                        }
                        Slider(value: $state.outputDelayMs, in: 10.0...100.0, step: 1.0)
                    }

                    Divider()

                    SettingsToggleRow(
                        "Exclusive Mode",
                        subtitle: "Acquire exclusive hardware control of the output audio interface.",
                        isOn: $state.audioOutputExclusiveMode
                    )
                }

                // 2. Audio Output & Buffering
                SettingsCard {
                    SettingsSectionHeader(
                        "Audio Output & Buffering",
                        systemImage: "waveform.path.ecg",
                        subtitle: "Network jitter buffering, master volume, and dynamic range."
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Default Jitter Buffer:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(state.defaultJitterBufferMs)) ms")
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(store.accentTint)
                        }
                        Slider(value: $state.defaultJitterBufferMs, in: 10.0...100.0, step: 5.0)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Master Output Volume:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(state.outputVolumePercent)) %")
                                .font(.subheadline.monospacedDigit().bold())
                        }
                        Slider(value: $state.outputVolumePercent, in: 0.0...200.0, step: 1.0)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Minimum Volume:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(state.minVolumePercent)) %")
                                .font(.subheadline.monospacedDigit().bold())
                        }
                        Slider(value: $state.minVolumePercent, in: 0.0...100.0, step: 1.0)
                    }
                }

                // 3. Attenuation (Audio Ducking)
                SettingsCard {
                    SettingsSectionHeader(
                        "Attenuation (Audio Ducking)",
                        systemImage: "speaker.badge.waveform.fill",
                        subtitle: "Lower other applications and games while voice is being spoken."
                    )

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Attenuate By:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(state.attenuateByPercent)) %")
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(store.accentTint)
                        }
                        Slider(value: $state.attenuateByPercent, in: 0.0...100.0, step: 5.0)
                    }

                    Divider()

                    SettingsToggleRow(
                        "While Other Users Talk",
                        subtitle: "Lower system and game audio when other participants are speaking.",
                        isOn: $state.attenuateWhileOthersTalk
                    )

                    SettingsToggleRow(
                        "While You Talk",
                        subtitle: "Lower other audio while your own microphone is open.",
                        isOn: $state.attenuateWhileYouTalk
                    )

                    Divider()

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Ducking Volume:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(state.duckingVolumePercent)) %")
                                .font(.subheadline.monospacedDigit().bold())
                        }
                        Slider(value: $state.duckingVolumePercent, in: 0.0...100.0, step: 5.0)
                    }

                    Divider()

                    SettingsToggleRow(
                        "Only Attenuate 'Same as System' Devices",
                        subtitle: "Limit audio ducking strictly to macOS default system audio hardware.",
                        isOn: $state.onlyAttenuateSameAsSystem
                    )

                    SettingsToggleRow(
                        "Attenuate System Output",
                        subtitle: "Apply hardware audio ducking to all macOS desktop sound output.",
                        isOn: $state.attenuateSystemOutput
                    )
                }

                // 4. Loopback Test
                SettingsCard {
                    SettingsSectionHeader(
                        "Loopback Test",
                        systemImage: "arrow.triangle.2.circlepath",
                        subtitle: "Listen to your own voice to verify microphone levels and simulated network jitter."
                    )

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Loopback Mode")
                                .font(.subheadline.bold())
                            Text("Route your microphone audio back to your headphones.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Loopback Mode", selection: $state.loopbackMode) {
                            ForEach(LoopbackMode.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 140)
                    }

                    if state.loopbackMode != .none {
                        Divider()

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Delay Variance:")
                                    .font(.caption)
                                Spacer()
                                Text("\(Int(state.loopbackDelayVarianceMs)) ms")
                                    .font(.caption.monospacedDigit())
                            }
                            Slider(value: $state.loopbackDelayVarianceMs, in: 0.0...100.0, step: 5.0)
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Packet Loss Simulation:")
                                    .font(.caption)
                                Spacer()
                                Text("\(Int(state.loopbackPacketLossPercent)) %")
                                    .font(.caption.monospacedDigit())
                            }
                            Slider(value: $state.loopbackPacketLossPercent, in: 0.0...50.0, step: 1.0)
                        }
                    }
                }

                // 5. Positional Audio
                SettingsCard {
                    SettingsSectionHeader(
                        "Positional Audio",
                        systemImage: "headphones",
                        subtitle: "3D spatial audio based on participant in-game positions."
                    )

                    SettingsToggleRow(
                        "Headphones Mode",
                        subtitle: "Optimize binaural HRTF 3D spatialization for stereo headphones.",
                        isOn: $state.positionalAudioHeadphones
                    )

                    Divider()

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Minimum Distance:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text(String(format: "%.1f m", state.positionalMinDistanceM))
                                .font(.caption.monospacedDigit())
                        }
                        Slider(value: $state.positionalMinDistanceM, in: 0.5...20.0, step: 0.5)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Maximum Distance:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text(String(format: "%.1f m", state.positionalMaxDistanceM))
                                .font(.caption.monospacedDigit())
                        }
                        Slider(value: $state.positionalMaxDistanceM, in: 1.0...50.0, step: 1.0)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Minimum Volume:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(state.positionalMinVolumePercent)) %")
                                .font(.caption.monospacedDigit())
                        }
                        Slider(value: $state.positionalMinVolumePercent, in: 0.0...100.0, step: 5.0)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text("Bloom Factor:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(Int(state.positionalBloomPercent)) %")
                                .font(.caption.monospacedDigit())
                        }
                        Slider(value: $state.positionalBloomPercent, in: 0.0...300.0, step: 5.0)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}
