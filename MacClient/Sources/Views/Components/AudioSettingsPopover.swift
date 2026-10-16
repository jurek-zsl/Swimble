import SwiftUI

/// Audio and input settings popover for VAD threshold, Global PTT keybinds, and AirPods Audio Lock.
public struct AudioSettingsPopover: View {
    @Bindable public var store: MumbleStore

    public init(store: MumbleStore) {
        self.store = store
    }

    private var audioEngine: MacAudioEngine {
        store.audioEngine
    }

    private var globalPTT: GlobalPTT {
        store.globalPTT
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            // Header
            HStack {
                Text("Audio & Voice Settings")
                    .font(.headline)
                Spacer()
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(.secondary)
            }

            Divider()

            // 1. Transmit Mode
            VStack(alignment: .leading, spacing: 8) {
                Text("Transmit Mode")
                    .font(.subheadline.bold())

                Picker("Transmit Mode", selection: Binding(
                    get: { audioEngine.isPushToTalk ? 1 : 0 },
                    set: { audioEngine.isPushToTalk = ($0 == 1) }
                )) {
                    Text("Voice Activity (VAD)").tag(0)
                    Text("Push-to-Talk (PTT)").tag(1)
                }
                .pickerStyle(.segmented)
            }

            // 2. VAD Sensitivity (shown if VAD is selected)
            if !audioEngine.isPushToTalk {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("VAD Activation Threshold")
                            .font(.caption.bold())
                        Spacer()
                        Text("\(Int(audioEngine.vadThresholdDb)) dB")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(audioEngine.vadThresholdDb) },
                            set: { audioEngine.vadThresholdDb = Float($0) }
                        ),
                        in: -60.0 ... -20.0,
                        step: 1.0
                    )

                    // Live mic input level vs threshold
                    VStack(alignment: .leading, spacing: 2) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                // Background track
                                Capsule()
                                    .fill(Color.secondary.opacity(0.2))

                                // Current mic level
                                let levelFraction = max(0.0, min(1.0, Double((audioEngine.inputLevelDb + 80) / 80)))
                                Capsule()
                                    .fill(audioEngine.isTransmitting ? Color.green : Color.secondary)
                                    .frame(width: geo.size.width * CGFloat(levelFraction))

                                // Threshold line marker
                                let threshFraction = max(0.0, min(1.0, Double((audioEngine.vadThresholdDb + 80) / 80)))
                                Rectangle()
                                    .fill(Color.red)
                                    .frame(width: 2, height: geo.size.height)
                                    .offset(x: geo.size.width * CGFloat(threshFraction))
                            }
                        }
                        .frame(height: 8)

                        HStack {
                            Text("-80 dB")
                            Spacer()
                            Text("Gate: \(Int(audioEngine.vadThresholdDb)) dB")
                                .foregroundStyle(.red)
                            Spacer()
                            Text("0 dB")
                        }
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    }
                }
            } else {
                // 3. Global Push-to-Talk Keybind & Accessibility
                VStack(alignment: .leading, spacing: 8) {
                    Text("Global Push-to-Talk Shortcut")
                        .font(.caption.bold())

                    HStack {
                        Button(action: {
                            globalPTT.isRecordingKeybind.toggle()
                        }) {
                            HStack {
                                Image(systemName: "keyboard")
                                Text(globalPTT.isRecordingKeybind ? globalPTT.recordingPreviewString(for: .ptt) : globalPTT.currentKeybind.displayString)
                                    .bold()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(globalPTT.isRecordingKeybind ? .orange : .accentColor)

                        if globalPTT.currentKeybind != .defaultGrave {
                            Button("Reset") {
                                globalPTT.currentKeybind = .defaultGrave
                            }
                            .buttonStyle(.bordered)
                        }
                    }

                    // Accessibility Status & Prompt
                    HStack(spacing: 6) {
                        Image(systemName: globalPTT.isAccessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .foregroundStyle(globalPTT.isAccessibilityTrusted ? .green : .orange)

                        Text(globalPTT.isAccessibilityTrusted ? "Global Game PTT: Enabled" : "Background PTT requires Accessibility")
                            .font(.caption2)
                            .foregroundStyle(.secondary)

                        Spacer()

                        if !globalPTT.isAccessibilityTrusted {
                            Button("Grant Access") {
                                globalPTT.requestAccessibility()
                            }
                            .font(.caption2)
                            .buttonStyle(.link)
                        }
                    }
                }
            }

            // 4. Background Audio Ducking
            SettingsToggleRow(
                "Lower Background Audio (Ducking)",
                subtitle: "macOS lowers Spotify and game audio when connected. Kept off for 100% volume.",
                isOn: Binding(
                    get: { audioEngine.isAudioDuckingEnabled },
                    set: { audioEngine.isAudioDuckingEnabled = $0 }
                )
            )

            Divider()

            // 5. Bluetooth / AirPods High-Quality Audio Lock
            SettingsToggleRow(
                "AirPods / Bluetooth High-Quality Lock",
                subtitle: "Locks mic to Mac's built-in mic so macOS never degrades Bluetooth stereo game audio into 16kHz Hands-Free mode.",
                isOn: Binding(
                    get: { audioEngine.isAirPodsAudioLockEnabled },
                    set: { audioEngine.isAirPodsAudioLockEnabled = $0 }
                )
            )

            Divider()

            // 6. Hardware Echo Cancellation & Voice Isolation Info
            HStack(spacing: 8) {
                Image(systemName: audioEngine.isVoiceProcessingEnabled ? "waveform.and.person.filled" : "waveform")
                    .foregroundStyle(audioEngine.isVoiceProcessingEnabled ? .green : .blue)
                VStack(alignment: .leading, spacing: 1) {
                    Text(audioEngine.isVoiceProcessingEnabled ? "Hardware VoiceProcessingIO Active" : "Direct CoreAudio Active")
                        .font(.caption.bold())
                    Text(audioEngine.isVoiceProcessingEnabled ?
                         "48 kHz Mono • AEC • Voice Isolation • \(audioEngine.isAudioDuckingEnabled ? "Ducking On" : "Zero Ducking")" :
                         "48 kHz Mono • Raw Audio • Zero Ducking")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(18)
        .frame(width: 380)
    }
}
