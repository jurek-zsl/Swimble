import SwiftUI

/// Floating bottom voice control HUD using native macOS 26 Liquid Glass APIs.
public struct FloatingVoiceHUD: View {
    @Bindable public var store: MumbleStore
    @Namespace private var glassNamespace
    @Environment(\.openSettings) private var openSettings

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
                        store.selectedSettingsTab = .shortcuts
                        openSettings()
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
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                audioEngine.isPushToTalk = false
                            }
                        }
                        Button("Shortcut Settings...") {
                            store.selectedSettingsTab = .shortcuts
                            openSettings()
                        }
                    }
                } else {
                    Button(action: {
                        store.selectedSettingsTab = .audio
                        openSettings()
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

                                Canvas { context, size in
                                    let trackPath = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: size.height / 2)
                                    context.fill(trackPath, with: .color(Color.secondary.opacity(0.15)))

                                    let levelFraction = max(0.0, min(1.0, Double((audioEngine.inputLevelDb + 80) / 80)))
                                    let fillWidth = size.width * CGFloat(levelFraction)
                                    if fillWidth > 0 {
                                        let fillRect = CGRect(x: 0, y: 0, width: fillWidth, height: size.height)
                                        let fillColor = audioEngine.isTransmitting ? Color.green : Color.secondary.opacity(0.3)
                                        context.fill(Path(roundedRect: fillRect, cornerRadius: size.height / 2), with: .color(fillColor))
                                    }
                                }
                                .frame(width: 44, height: 4)
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
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                                audioEngine.isPushToTalk = true
                            }
                        }
                        Button("Audio Settings...") {
                            store.selectedSettingsTab = .audio
                            openSettings()
                        }
                    }
                }

                // 2. Microphone Mute Button
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        store.toggleSelfMute()
                    }
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
                .help(store.isSelfMuted ? "Unmute Microphone (Cmd+Shift+M)" : "Mute Microphone (Cmd+Shift+M)")

                // 3. Deafen Button
                Button(action: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                        store.toggleSelfDeaf()
                    }
                }) {
                    Image(systemName: "headphones")
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
                .help(store.isSelfDeafened ? "Undeafen Audio (Cmd+Shift+D)" : "Deafen Audio (Cmd+Shift+D)")

                // 4. Audio Settings Gear Button
                Button(action: {
                    store.selectedSettingsTab = .general
                    openSettings()
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
                .help("Settings (Cmd+,)")

                // 5. Disconnect Button
                if store.connectionStatus == .connected || store.connectionStatus == .connecting {
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                            store.disconnect()
                        }
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
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: store.isSelfMuted)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: store.isSelfDeafened)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: store.isWhispering)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: audioEngine.isPushToTalk)
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: store.connectionStatus)
    }
}
