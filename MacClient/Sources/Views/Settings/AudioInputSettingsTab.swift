import SwiftUI
import AppKit

/// Comprehensive Audio Input configuration tab matching official Mumble specs.
public struct AudioInputSettingsTab: View {
    @Bindable public var store: MumbleStore
    @Bindable public var state: SettingsState = SettingsState.shared
    private var deviceManager = CoreAudioDeviceManager.shared

    public init(store: MumbleStore) {
        self.store = store
    }

    private var inputLevelDb: Float {
        store.audioEngine?.inputLevelDb ?? -60.0
    }

    private var totalBandwidthKbps: Double {
        // Audio + Position (approx 16 kbps) + Protocol Overhead (approx 12.8 kbps)
        state.qualityBitrateKbps + 16.0 + 12.8
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Interface
                SettingsCard {
                    SettingsSectionHeader(
                        "Interface",
                        systemImage: "mic.fill",
                        subtitle: "Select the audio subsystem and input hardware microphone."
                    )

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("System")
                                .font(.subheadline.bold())
                            Picker("System", selection: $state.audioInputSystem) {
                                Text("CoreAudio").tag("CoreAudio")
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Device")
                                .font(.subheadline.bold())
                            Picker("Device", selection: $state.audioInputDevice) {
                                Text("Default Device").tag("")
                                ForEach(deviceManager.inputDevices) { dev in
                                    Text(dev.name).tag(dev.name)
                                }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Divider()

                    SettingsToggleRow(
                        "Exclusive Mode",
                        subtitle: "Acquire exclusive hardware ownership of the microphone.",
                        isOn: $state.audioInputExclusiveMode
                    )
                }

                // 2. Transmission
                SettingsCard {
                    SettingsSectionHeader(
                        "Transmission",
                        systemImage: "waveform.badge.magnifyingglass",
                        subtitle: "Configure when and how your voice is transmitted to the server."
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Transmit Mode")
                            .font(.subheadline.bold())
                        Picker("Transmit Mode", selection: $state.transmitMode) {
                            ForEach(TransmitMode.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    if state.transmitMode == .voiceActivity {
                        Divider()

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Voice Activity Detection Method")
                                .font(.subheadline.bold())

                            HStack(spacing: 24) {
                                ForEach(VadMode.allCases) { mode in
                                    HStack(spacing: 6) {
                                        Image(systemName: state.vadMode == mode ? "largecircle.fill.circle" : "circle")
                                            .foregroundStyle(state.vadMode == mode ? store.accentTint : .secondary)
                                        Text(mode.rawValue)
                                            .font(.body)
                                    }
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        state.vadMode = mode
                                    }
                                }
                            }
                        }

                        // Live 3-Zone VAD Meter Bar
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text("Voice Activity Level:")
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(String(format: "%.1f dB", inputLevelDb))
                                    .font(.caption.monospacedDigit().bold())
                                    .foregroundStyle(inputLevelDb >= Float(state.speechAboveDb) ? .green : .secondary)
                            }

                            // 3-Zone Meter: Red (Silence), Yellow (Hold/Margin), Green (Speech)
                            GeometryReader { geo in
                                let width = geo.size.width
                                let db = CGFloat(inputLevelDb)
                                // normalize db from -60 to 0
                                let norm = min(max((db + 60.0) / 60.0, 0.0), 1.0)
                                let silNorm = CGFloat((state.silenceBelowDb + 60.0) / 60.0)
                                let spkNorm = CGFloat((state.speechAboveDb + 60.0) / 60.0)

                                ZStack(alignment: .leading) {
                                    // Background track with 3 zones
                                    HStack(spacing: 0) {
                                        Rectangle()
                                            .fill(Color.red.opacity(0.35))
                                            .frame(width: max(0, silNorm * width))
                                        Rectangle()
                                            .fill(Color.yellow.opacity(0.4))
                                            .frame(width: max(0, (spkNorm - silNorm) * width))
                                        Rectangle()
                                            .fill(Color.green.opacity(0.4))
                                            .frame(width: max(0, (1.0 - spkNorm) * width))
                                    }

                                    // Active Level Bar
                                    Rectangle()
                                        .fill(norm >= spkNorm ? Color.green : (norm >= silNorm ? Color.yellow : Color.red))
                                        .frame(width: max(0, norm * width))
                                        .animation(.linear(duration: 0.05), value: norm)
                                }
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(Color.primary.opacity(0.15), lineWidth: 0.8)
                                }
                            }
                            .frame(height: 18)

                            // Threshold Sliders
                            HStack(spacing: 20) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("Silence Below:")
                                            .font(.caption)
                                        Spacer()
                                        Text("\(Int(state.silenceBelowDb)) dB")
                                            .font(.caption.monospacedDigit())
                                    }
                                    Slider(value: $state.silenceBelowDb, in: -60.0...(-10.0), step: 1.0)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("Speech Above:")
                                            .font(.caption)
                                        Spacer()
                                        Text("\(Int(state.speechAboveDb)) dB")
                                            .font(.caption.monospacedDigit())
                                    }
                                    Slider(value: $state.speechAboveDb, in: -50.0...0.0, step: 1.0)
                                }
                            }
                        }

                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text("Voice Hold:")
                                    .font(.subheadline.bold())
                                Spacer()
                                Text(String(format: "%.2f s", state.voiceHold))
                                    .font(.caption.monospacedDigit())
                            }
                            Slider(value: $state.voiceHold, in: 0.0...1.0, step: 0.05)
                        }
                    }

                    if state.transmitMode == .pushToTalk {
                        Divider()

                        VStack(alignment: .leading, spacing: 12) {
                            Text("Push-to-Talk Tuning")
                                .font(.subheadline.bold())

                            HStack(spacing: 20) {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("DoublePush Time:")
                                            .font(.caption)
                                        Spacer()
                                        Text(String(format: "%.2f s", state.pttDoublePushTime))
                                            .font(.caption.monospacedDigit())
                                    }
                                    Slider(value: $state.pttDoublePushTime, in: 0.0...1.0, step: 0.05)
                                }

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text("Hold Time:")
                                            .font(.caption)
                                        Spacer()
                                        Text(String(format: "%.2f s", state.pttHoldTime))
                                            .font(.caption.monospacedDigit())
                                    }
                                    Slider(value: $state.pttHoldTime, in: 0.0...1.0, step: 0.05)
                                }
                            }

                            SettingsToggleRow(
                                "Audio Cue",
                                subtitle: "Play an audible notification when the microphone opens and closes.",
                                isOn: $state.pttAudioCue
                            )

                            if state.pttAudioCue {
                                HStack(spacing: 12) {
                                    Button("Browse On Sound...") {
                                        pickSoundFile { path in state.pttOnCuePath = path }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Button("Browse Off Sound...") {
                                        pickSoundFile { path in state.pttOffCuePath = path }
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)

                                    Spacer()

                                    Button("Preview Cue") {
                                        SoundManager.shared.playSelfMuted()
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                // 3. Compression
                SettingsCard {
                    SettingsSectionHeader(
                        "Compression",
                        systemImage: "slider.horizontal.2.square.on.square",
                        subtitle: "Tune Opus audio quality, latency, and packet overhead."
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Quality Bitrate:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text(String(format: "%.1f kb/s", state.qualityBitrateKbps))
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(store.accentTint)
                        }
                        Slider(value: $state.qualityBitrateKbps, in: 16.0...192.0, step: 0.5)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Audio per Packet Frame Size:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text("\(state.audioPacketFrameSizeMs) ms")
                                .font(.subheadline.monospacedDigit().bold())
                        }
                        Picker("Frame Size", selection: $state.audioPacketFrameSizeMs) {
                            Text("10 ms").tag(10)
                            Text("20 ms").tag(20)
                            Text("40 ms").tag(40)
                            Text("60 ms").tag(60)
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider()

                    SettingsToggleRow(
                        "Allow Low Delay Mode",
                        subtitle: "Reduces Opus encoder buffering for the lowest possible latency.",
                        isOn: $state.allowLowDelayMode
                    )

                    Divider()

                    // Live Bandwidth Readout
                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Live Bandwidth:")
                                .font(.subheadline.bold())
                            Text(String(format: "Audio: %.1f · Position: 16.0 · Overhead: 12.8", state.qualityBitrateKbps))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(String(format: "%.1f kbit/s", totalBandwidthKbps))
                            .font(.title3.bold().monospacedDigit())
                            .foregroundStyle(store.accentTint)
                    }
                    .padding(10)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                }

                // 4. Audio Processing
                SettingsCard {
                    SettingsSectionHeader(
                        "Audio Processing",
                        systemImage: "wand.and.stars",
                        subtitle: "DSP filters including Echo Cancellation, Noise Suppression, and Gain."
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Max. Amplification:")
                                .font(.subheadline.bold())
                            Spacer()
                            Text(String(format: "%.2f", state.maxAmplification))
                                .font(.subheadline.monospacedDigit().bold())
                        }
                        Slider(value: $state.maxAmplification, in: 1.0...10.0, step: 0.05)
                    }

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Echo Cancellation")
                                .font(.subheadline.bold())
                            Text("Hardware VoiceProcessingIO removes speaker playback from your mic.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Echo Cancellation", selection: $state.echoCancellation) {
                            Text("Disabled").tag(false)
                            Text("Enabled").tag(true)
                        }
                        .labelsHidden()
                        .frame(width: 130)
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Noise Suppression Mode")
                            .font(.subheadline.bold())

                        HStack(spacing: 20) {
                            ForEach(NoiseSuppressionMode.allCases) { mode in
                                HStack(spacing: 6) {
                                    Image(systemName: state.noiseSuppressionMode == mode ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(state.noiseSuppressionMode == mode ? store.accentTint : .secondary)
                                    Text(mode.rawValue)
                                        .font(.body)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    state.noiseSuppressionMode = mode
                                }
                            }
                        }

                        if state.noiseSuppressionMode != .disabled {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Suppression Level:")
                                        .font(.caption)
                                    Spacer()
                                    Text("\(Int(state.noiseSuppressionLevelDb)) dB")
                                        .font(.caption.monospacedDigit())
                                }
                                Slider(value: $state.noiseSuppressionLevelDb, in: -30.0...0.0, step: 1.0)
                            }
                        }
                    }
                }

                // 5. Misc
                SettingsCard {
                    SettingsSectionHeader(
                        "Misc",
                        systemImage: "ellipsis.circle.fill",
                        subtitle: "Mute chime, mic icon highlight, and inactivity idle timers."
                    )

                    SettingsToggleRow(
                        "Mute Microphone Cue",
                        subtitle: "Play an audible chime when toggling mute on/off.",
                        isOn: $state.muteMicrophoneCue
                    )

                    if state.muteMicrophoneCue {
                        HStack(spacing: 12) {
                            Button("Browse Custom Cue...") {
                                pickSoundFile { path in state.muteCuePath = path }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Preview Cue") {
                                SoundManager.shared.playSelfMuted()
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Divider()

                    SettingsToggleRow(
                        "Highlight Microphone Icon When Mic is Open",
                        subtitle: "Glows the speaking orb whenever you are transmitting voice.",
                        isOn: $state.highlightMicIconWhenOpen
                    )

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Idle Action Timer")
                                .font(.subheadline.bold())
                            Text("Automatically trigger an action after 5 minutes of inactivity.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Picker("Idle Action", selection: $state.idleActionType) {
                            ForEach(IdleActionType.allCases) { act in
                                Text(act.rawValue).tag(act)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    SettingsToggleRow(
                        "Undo Idle Action Upon Any Activity",
                        subtitle: "Automatically unmute / resume when keyboard or mouse activity is detected.",
                        isOn: $state.undoIdleActionOnActivity
                    )
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
