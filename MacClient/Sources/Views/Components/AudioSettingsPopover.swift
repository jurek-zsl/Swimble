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
                                Text(globalPTT.isRecordingKeybind ? "Press any key..." : globalPTT.currentKeybind.displayString)
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

            Divider()

            // 4. Bluetooth / AirPods High-Quality Audio Lock
            VStack(alignment: .leading, spacing: 6) {
                Toggle(isOn: Binding(
                    get: { audioEngine.isAirPodsAudioLockEnabled },
                    set: { audioEngine.isAirPodsAudioLockEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("AirPods / Bluetooth High-Quality Lock")
                            .font(.subheadline.bold())
                        Text("Locks mic to Mac's built-in mic so macOS never degrades Bluetooth stereo game audio into 16kHz Hands-Free mode.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.switch)
            }

            Divider()

            // 5. Hardware Echo Cancellation & Voice Isolation Info
            HStack(spacing: 8) {
                Image(systemName: "waveform.and.person.filled")
                    .foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Hardware VoiceProcessingIO Active")
                        .font(.caption.bold())
                    Text("48,000 Hz Mono • Acoustic Echo Cancellation • macOS Voice Isolation")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(18)
        .frame(width: 380)
    }
}
