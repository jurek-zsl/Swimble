import SwiftUI

/// Floating bottom voice control HUD using native macOS 26 Liquid Glass APIs.
public struct FloatingVoiceHUD: View {
    @Bindable public var store: MumbleStore
    @Namespace private var glassNamespace
    @State private var showSettingsSheet: Bool = false
    @State private var settingsTab: SettingsTab = .audio

    public init(store: MumbleStore) {
        self.store = store
    }

    private var audioEngine: MacAudioEngine {
        store.audioEngine
    }

    public var body: some View {
        GlassEffectContainer(spacing: 14) {
            HStack(spacing: 12) {
                // 0. Live Whisper Indicator
                if store.isWhispering {
                    HStack(spacing: 6) {
                        Image(systemName: "megaphone.fill")
                            .font(.system(size: 13))
                        Text("WHISPERING")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .glassEffect(.regular.tint(.cyan).interactive(), in: .capsule)
                    .glassEffectID("whisperPill", in: glassNamespace)
                }

                // 1. Transmit Mode Pill (VAD meter vs PTT Button)
                if audioEngine.isPushToTalk {
                    Button(action: {
                        settingsTab = .shortcuts
                        showSettingsSheet = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: audioEngine.isTransmitting ? "mic.fill" : "hand.tap.fill")
                                .font(.system(size: 14))
                            Text(audioEngine.isTransmitting ? "TRANSMITTING" : "PTT: \(store.globalPTT.currentKeybind.displayString)")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        .regular.tint(audioEngine.isTransmitting ? .green : nil).interactive(),
                        in: .capsule
                    )
                    .glassEffectID("transmitPill", in: glassNamespace)
                    .simultaneousGesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { _ in
                                audioEngine.setPushToTalkActive(true)
                            }
                            .onEnded { _ in
                                audioEngine.setPushToTalkActive(false)
                            }
                    )
                    .contextMenu {
                        Button("Switch to Voice Activity (VAD)") {
                            audioEngine.isPushToTalk = false
                        }
                        Button("Shortcut Settings...") {
                            settingsTab = .shortcuts
                            showSettingsSheet = true
                        }
                    }
                } else {
                    Button(action: {
                        settingsTab = .audio
                        showSettingsSheet = true
                    }) {
                        HStack(spacing: 8) {
                            Image(systemName: audioEngine.isTransmitting ? "waveform.circle.fill" : "waveform")
                                .foregroundStyle(audioEngine.isTransmitting ? Color.green : Color.primary)
                                .font(.system(size: 14))

                            // Compact live level bar
                            VStack(alignment: .leading, spacing: 2) {
                                Text("VAD")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)

                                let levelFraction = max(0.0, min(1.0, Double((audioEngine.inputLevelDb + 80) / 80)))
                                Capsule()
                                    .fill(audioEngine.isTransmitting ? Color.green : Color.secondary.opacity(0.3))
                                    .frame(width: 44 * CGFloat(levelFraction), height: 4)
                                    .background(Color.secondary.opacity(0.15), in: Capsule())
                                    .frame(width: 44, alignment: .leading)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        .regular.tint(audioEngine.isTransmitting ? .green.opacity(0.4) : nil).interactive(),
                        in: .capsule
                    )
                    .glassEffectID("transmitPill", in: glassNamespace)
                    .help("Voice Activation Meter (Click to Calibrate)")
                    .contextMenu {
                        Button("Switch to Push-to-Talk (PTT)") {
                            audioEngine.isPushToTalk = true
                        }
                        Button("Audio Settings...") {
                            settingsTab = .audio
                            showSettingsSheet = true
                        }
                    }
                }

                // 2. Microphone Mute Button
                Button(action: {
                    store.toggleSelfMute()
                }) {
                    Image(systemName: store.isSelfMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 15))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    .regular.tint(store.isSelfMuted ? .red : nil).interactive(),
                    in: .circle
                )
                .glassEffectID("muteButton", in: glassNamespace)
                .help(store.isSelfMuted ? "Unmute Microphone" : "Mute Microphone")

                // 3. Deafen Button
                Button(action: {
                    store.toggleSelfDeaf()
                }) {
                    Image(systemName: store.isSelfDeafened ? "headphones" : "headphones")
                        .font(.system(size: 15))
                        .overlay {
                            if store.isSelfDeafened {
                                Image(systemName: "slash.circle.fill")
                                    .font(.system(size: 12))
                                    .offset(x: 8, y: 8)
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    .regular.tint(store.isSelfDeafened ? .orange : nil).interactive(),
                    in: .circle
                )
                .glassEffectID("deafenButton", in: glassNamespace)
                .help(store.isSelfDeafened ? "Undeafen Audio" : "Deafen Audio")

                // 4. Audio Settings Gear Button
                Button(action: {
                    settingsTab = .audio
                    showSettingsSheet = true
                }) {
                    Image(systemName: "gearshape.fill")
                        .font(.system(size: 15))
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
                .glassEffect(
                    .regular.interactive(),
                    in: .circle
                )
                .glassEffectID("settingsButton", in: glassNamespace)
                .help("Settings (Audio, Shortcuts, Tokens)")

                // 5. Disconnect Button
                if store.connectionStatus == .connected || store.connectionStatus == .connecting {
                    Button(action: {
                        store.disconnect()
                    }) {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 15))
                            .frame(width: 36, height: 36)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        .regular.tint(.red).interactive(),
                        in: .circle
                    )
                    .glassEffectID("disconnectButton", in: glassNamespace)
                    .help("Disconnect from Server")
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .sheet(isPresented: $showSettingsSheet) {
            SettingsModal(store: store, isPresented: $showSettingsSheet, initialTab: settingsTab)
        }
    }
}
