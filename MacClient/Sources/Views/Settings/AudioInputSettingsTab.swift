import SwiftUI
import AppKit

/// Native Audio Input configuration tab tailored for macOS 26 CoreAudio & Apple Silicon.
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

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                AudioQualitySettings()
                // 1. Interface
                SettingsCard {
                    SettingsSectionHeader(
                        "Input Device",
                        systemImage: "mic.fill",
                        subtitle: "Select your hardware microphone and configure Bluetooth audio protection."
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Microphone")
                            .font(.subheadline.bold())
                        Picker("Microphone", selection: $state.audioInputDevice) {
                            Text("Default Device").tag("")
                            ForEach(deviceManager.inputDevices) { dev in
                                Text(dev.name).tag(dev.uid)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }

                    Divider()

                    SettingsToggleRow(
                        "AirPods & Bluetooth High-Quality Audio Lock",
                        subtitle: "Locks microphone input to the Mac's built-in mic when Bluetooth headphones are active, preventing macOS from degrading stereo game/music audio into 16kHz Hands-Free mono.",
                        isOn: $state.airPodsAudioLockEnabled
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
                                let norm = min(max((db + 60.0) / 60.0, 0.0), 1.0)
                                let silNorm = CGFloat((state.silenceBelowDb + 60.0) / 60.0)
                                let spkNorm = CGFloat((state.speechAboveDb + 60.0) / 60.0)

                                ZStack(alignment: .leading) {
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

                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text("Release Hold Time:")
                                        .font(.caption)
                                    Spacer()
                                    Text(String(format: "%.2f s", state.pttHoldTime))
                                        .font(.caption.monospacedDigit())
                                }
                                Slider(value: $state.pttHoldTime, in: 0.0...0.5, step: 0.01)
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

                // 3. Audio Processing
                SettingsCard {
                    SettingsSectionHeader(
                        "Audio Processing",
                        systemImage: "wand.and.stars",
                        subtitle: "Hardware DSP filters including Echo Cancellation, Voice Isolation, and Gain."
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Microphone Amplification (Gain):")
                                .font(.subheadline.bold())
                            Spacer()
                            Text(String(format: "%.1fx", state.maxAmplification))
                                .font(.subheadline.monospacedDigit().bold())
                                .foregroundStyle(store.accentTint)
                        }
                        Slider(value: $state.maxAmplification, in: 1.0...5.0, step: 0.1)
                    }

                    Divider()

                    SettingsToggleRow(
                        "Hardware Echo Cancellation (VoiceProcessingIO)",
                        subtitle: "Apple Silicon hardware VoiceProcessing eliminates speaker playback and room echo from your microphone.",
                        isOn: $state.echoCancellation
                    )
                }

                // 4. Misc & Inactivity
                SettingsCard {
                    SettingsSectionHeader(
                        "Notifications & Idle Automation",
                        systemImage: "ellipsis.circle.fill",
                        subtitle: "Mute cues, speaking indicator glow, and automatic AFK timeout."
                    )

                    SettingsToggleRow(
                        "Mute Microphone Cue",
                        subtitle: "Play an audible chime when toggling self-mute on or off.",
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
                                if state.muteCuePath.isEmpty { NSSound(named: "Basso")?.play() }
                                else { SoundManager.shared.playSound(filePath: state.muteCuePath) }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    Divider()

                    SettingsToggleRow(
                        "Highlight Microphone Icon When Mic is Open",
                        subtitle: "Glows the speaking orb whenever your microphone is transmitting audio.",
                        isOn: $state.highlightMicIconWhenOpen
                    )

                    Divider()

                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Idle Action Timer")
                                .font(.subheadline.bold())
                            Text("Automatically trigger an action after inactivity.")
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
                        subtitle: "Automatically unmute and resume when keyboard or mouse activity is detected.",
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
