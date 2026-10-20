import SwiftUI
import AVFoundation

/// Step-by-step Audio Setup Wizard configuring output, microphone, voice activation, and DSP.
public struct AudioWizardModal: View {
    @Bindable public var store: MumbleStore
    @Environment(\.dismiss) private var dismiss

    @State private var currentStep: Int = 1
    @State private var isPlayingTone: Bool = false
    private let totalSteps = 4

    private var audioEngine: MacAudioEngine {
        store.audioEngine
    }

    private var globalPTT: GlobalPTT {
        store.globalPTT
    }

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "wand.and.stars")
                        .font(.title2)
                        .foregroundStyle(store.accentTint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Audio Configuration Wizard")
                            .font(.headline.bold())
                        Text("Step \(currentStep) of \(totalSteps): \(stepTitle)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))

            Divider()

            // Step Content
            VStack(spacing: 20) {
                switch currentStep {
                case 1:
                    step1OutputView
                case 2:
                    step2InputView
                case 3:
                    step3ActivationView
                case 4:
                    step4ProcessingView
                default:
                    EmptyView()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            // Footer Navigation
            HStack {
                if currentStep > 1 {
                    Button("Back") {
                        currentStep -= 1
                    }
                    .buttonStyle(.bordered)
                }

                Spacer()

                if currentStep < totalSteps {
                    Button("Next") {
                        currentStep += 1
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(store.accentTint)
                } else {
                    Button("Finish Setup") {
                        dismiss()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.green)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))
        }
        .frame(width: 520, height: 480)
        .onAppear { store.audioEngine.beginPreview() }
        .onDisappear { store.audioEngine.endPreview() }
    }

    private var stepTitle: String {
        switch currentStep {
        case 1: return "Audio Output & Headphones"
        case 2: return "Microphone & Sensitivity"
        case 3: return "Transmission Mode (VAD / PTT)"
        case 4: return "Echo Cancellation & Protection"
        default: return ""
        }
    }

    // MARK: - Step 1: Output
    @ViewBuilder
    private var step1OutputView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Verify that you can hear audio clearly through your speakers or headphones.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 10) {
                Text("Sound Test")
                    .font(.subheadline.bold())

                HStack {
                    Button(action: {
                        toggleTestTone()
                    }) {
                        Label(isPlayingTone ? "Stop Test Sound" : "Play Test Tone (440 Hz)", systemImage: isPlayingTone ? "stop.fill" : "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(isPlayingTone ? .orange : store.accentTint)

                    if isPlayingTone {
                        Text("Playing harmonic chime...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

            Text("Tip: Headphones or headsets are strongly recommended for the best experience and to prevent microphone feedback.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: - Step 2: Input
    @ViewBuilder
    private var step2InputView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Speak into your microphone. The meter below should dance smoothly into the green zone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Microphone Level")
                        .font(.subheadline.bold())
                    Spacer()
                    Text(String(format: "%.1f dB", audioEngine.inputLevelDb))
                        .font(.caption.monospacedDigit().bold())
                        .foregroundStyle(audioEngine.isTransmitting ? Color.green : Color.secondary)
                }

                // Level meter
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 3)
                            .fill(Color(NSColor.darkGray).opacity(0.4))

                        let levelFrac = max(0.0, min(1.0, Double((audioEngine.inputLevelDb + 80.0) / 80.0)))
                        RoundedRectangle(cornerRadius: 3)
                            .fill(audioEngine.isTransmitting ? Color.green : Color.green.opacity(0.5))
                            .frame(width: geo.size.width * CGFloat(levelFrac))
                    }
                }
                .frame(height: 16)

                HStack {
                    Text("-80 dB (Silent)")
                    Spacer()
                    Text("0 dB (Clipping)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
            .padding(14)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    // MARK: - Step 3: Activation
    @ViewBuilder
    private var step3ActivationView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Picker("Mode", selection: Binding(
                get: { audioEngine.isPushToTalk ? 1 : 0 },
                set: { audioEngine.isPushToTalk = ($0 == 1) }
            )) {
                Text("Voice Activity (VAD)").tag(0)
                Text("Push-to-Talk (PTT)").tag(1)
            }
            .pickerStyle(.segmented)

            if !audioEngine.isPushToTalk {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text("VAD Sensitivity Threshold")
                            .font(.subheadline.bold())
                        Spacer()
                        Text("\(Int(audioEngine.vadThresholdDb)) dB")
                            .font(.caption.monospacedDigit().bold())
                    }

                    Slider(value: Binding(
                        get: { Double(audioEngine.vadThresholdDb) },
                        set: { audioEngine.vadThresholdDb = Float($0) }
                    ), in: -60.0...(-20.0), step: 1.0)

                    Text("Drag the red gate marker so your voice triggers transmission, but background room noise does not.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Global Push-to-Talk Keybind")
                        .font(.subheadline.bold())

                    Button(action: {
                        globalPTT.isRecordingKeybind.toggle()
                    }) {
                        Text(globalPTT.isRecordingKeybind ? globalPTT.recordingPreviewString(for: .ptt) : "Keybind: \(globalPTT.currentKeybind.displayString)")
                            .font(.body.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(globalPTT.isRecordingKeybind ? .orange : store.accentTint)

                    Text("Works globally in games and full-screen applications via macOS CGEvent.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    // MARK: - Step 4: Processing
    @ViewBuilder
    private var step4ProcessingView: some View {
        VStack(alignment: .leading, spacing: 14) {
            SettingsToggleRow(
                "Hardware Echo Cancellation (AEC)",
                subtitle: "Apple VoiceProcessingIO removes speaker audio from your mic.",
                isOn: Binding(
                    get: { audioEngine.isVoiceProcessingEnabled },
                    set: { audioEngine.isVoiceProcessingEnabled = $0 }
                )
            )

            Divider()

            SettingsToggleRow(
                "Lower Other Applications (Ducking)",
                subtitle: "Keep disabled to hear background Spotify / game audio at 100% volume.",
                isOn: Binding(
                    get: { audioEngine.isAudioDuckingEnabled },
                    set: { audioEngine.isAudioDuckingEnabled = $0 }
                )
            )

            Divider()

            SettingsToggleRow(
                "AirPods / Bluetooth High-Quality Lock",
                subtitle: "Locks mic to built-in mic so Bluetooth game audio never drops to 16kHz.",
                isOn: Binding(
                    get: { audioEngine.isAirPodsAudioLockEnabled },
                    set: { audioEngine.isAirPodsAudioLockEnabled = $0 }
                )
            )
        }
        .padding(16)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }

    private func toggleTestTone() {
        if isPlayingTone {
            isPlayingTone = false
        } else {
            isPlayingTone = true
            store.audioEngine.playTestTone()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                self.isPlayingTone = false
            }
        }
    }
}
