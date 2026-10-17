import SwiftUI

/// Interactive button style providing tactile spring press feedback and enforcing
/// a solid hit-test shape across the entire circular frame so no clicks are missed.
public struct HUDCircleButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.75), value: configuration.isPressed)
            .contentShape(Circle())
    }
}

/// Interactive button style for capsule-shaped pills.
public struct HUDCapsuleButtonStyle: ButtonStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.75), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

/// Dedicated subview for live VAD audio level metering.
/// Isolates observation of `audioEngine.inputLevelDb` (~15-30Hz updates) so the parent
/// HUD and its voice control buttons do NOT constantly re-evaluate and abort in-flight clicks.
private struct VadLevelMeterView: View {
    @Bindable var audioEngine: MacAudioEngine

    var body: some View {
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

                // 0b. Live Priority Speaker Indicator
                if store.isMyPrioritySpeaker {
                    Button(action: {
                        store.toggleSelfPrioritySpeaker()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 13))
                            Text("PRIORITY")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(HUDCapsuleButtonStyle())
                    .glassEffect(.regular.tint(.yellow).interactive(), in: .capsule)
                    .glassEffectID("prioritySpeakerPill", in: glassNamespace)
                    .help("Priority Speaker Active (Click to toggle off)")
                }

                // 1. Transmit Mode Pill (VAD meter vs PTT Button)
                if audioEngine.isPushToTalk {
                    Button(action: {}) {
                        HStack(spacing: 8) {
                            Image(systemName: audioEngine.isTransmitting ? "mic.fill" : "hand.tap.fill")
                                .font(.system(size: 14))
                            Text(audioEngine.isTransmitting ? "TRANSMITTING" : "PTT: \(store.globalPTT.currentKeybind.displayString)")
                                .font(.caption.bold())
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(HUDCapsuleButtonStyle())
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

                            // Compact live level bar (isolated from parent HUD invalidations)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("VAD")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.secondary)

                                VadLevelMeterView(audioEngine: audioEngine)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Capsule())
                    }
                    .buttonStyle(HUDCapsuleButtonStyle())
                    .glassEffect(
                        .regular.tint(audioEngine.isTransmitting ? .green.opacity(0.4) : nil).interactive(),
                        in: .capsule
                    )
                    .glassEffectID("transmitPill", in: glassNamespace)
                    .help("Voice Activation Meter (Click for Audio Settings)")
                    .contextMenu {
                        Button("Switch to Push-to-Talk (PTT)") {
                            audioEngine.isPushToTalk = true
                        }
                        Button("Audio Settings...") {
                            store.selectedSettingsTab = .audio
                            openSettings()
                        }
                    }
                }

                // 2. Microphone Mute Button
                let isMicOpenHighlighted = SettingsState.shared.highlightMicIconWhenOpen && audioEngine.isTransmitting
                Button(action: {
                    store.toggleSelfMute()
                }) {
                    Image(systemName: store.isSelfMuted ? "mic.slash.fill" : "mic.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(isMicOpenHighlighted ? Color.green : (store.isSelfMuted ? Color.red : Color.primary))
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .buttonStyle(HUDCircleButtonStyle())
                .glassEffect(
                    .regular.tint(store.isSelfMuted ? .red : (isMicOpenHighlighted ? .green.opacity(0.3) : nil)).interactive(),
                    in: .circle
                )
                .glassEffectID("muteButton", in: glassNamespace)
                .help(store.isSelfMuted ? "Unmute Microphone (Cmd+Shift+M)" : "Mute Microphone (Cmd+Shift+M)")

                // 3. Deafen Button
                Button(action: {
                    store.toggleSelfDeaf()
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
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .buttonStyle(HUDCircleButtonStyle())
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
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .buttonStyle(HUDCircleButtonStyle())
                .glassEffect(
                    .regular.interactive(),
                    in: .circle
                )
                .glassEffectID("settingsButton", in: glassNamespace)
                .help("Settings (Cmd+,)")

                // 5. Disconnect Button
                if store.connectionStatus == .connected || store.connectionStatus == .connecting {
                    Button(action: {
                        store.disconnect()
                    }) {
                        Image(systemName: "phone.down.fill")
                            .font(.system(size: 15))
                            .frame(width: 38, height: 38)
                            .contentShape(Circle())
                    }
                    .buttonStyle(HUDCircleButtonStyle())
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
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: store.isSelfMuted)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: store.isSelfDeafened)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: store.isWhispering)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: audioEngine.isPushToTalk)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: store.connectionStatus)
    }
}
