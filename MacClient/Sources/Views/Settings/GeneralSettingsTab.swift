import SwiftUI

/// General application preferences including Startup, Audio Cues (sound effects),
/// Liquid Glass accent tints, and Game Overlay preferences.
public struct GeneralSettingsTab: View {
    @Bindable public var store: MumbleStore
    @State private var audioCuesEnabled: Bool = SoundManager.shared.isAudioCuesEnabled
    @State private var muteCueEnabled: Bool = SoundManager.shared.isMuteCueEnabled
    @State private var userActivityCueEnabled: Bool = SoundManager.shared.isUserActivityCueEnabled
    @State private var whisperCueEnabled: Bool = SoundManager.shared.isWhisperCueEnabled
    @State private var messageCueEnabled: Bool = SoundManager.shared.isMessageCueEnabled

    private let accentColors: [(name: String, color: Color)] = [
        ("Cyan", .cyan),
        ("Emerald", .green),
        ("Sapphire", .blue),
        ("Amethyst", .purple),
        ("Amber", .orange),
        ("Ruby", .red)
    ]

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 1. Startup & Connectivity
                SettingsCard {
                    SettingsSectionHeader(
                        "Startup & Connectivity",
                        systemImage: "bolt.fill",
                        subtitle: "Configure automatic connection behavior on application launch."
                    )

                    SettingsToggleRow(
                        "Auto-Connect to Favorite Server",
                        subtitle: "Automatically connects to your favorite server bookmark when Swimble launches.",
                        isOn: $store.autoReconnectOnLaunch
                    )
                }

                // 2. Audio Cues & Sound Alerts
                SettingsCard {
                    HStack {
                        SettingsSectionHeader(
                            "Audio Cues & Sound Alerts",
                            systemImage: "bell.badge.fill",
                            subtitle: "Play subtle audio chimes for voice actions and incoming messages."
                        )
                        Spacer()
                        Toggle("", isOn: $audioCuesEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: audioCuesEnabled) { _, newValue in
                                SoundManager.shared.isAudioCuesEnabled = newValue
                            }
                    }

                    if audioCuesEnabled {
                        VStack(alignment: .leading, spacing: 14) {
                            SettingsToggleRow(
                                "Mute & Deafen Chimes",
                                subtitle: "Play chimes when self or global mute/deafen status changes.",
                                isOn: Binding(
                                    get: { muteCueEnabled },
                                    set: {
                                        muteCueEnabled = $0
                                        SoundManager.shared.isMuteCueEnabled = $0
                                    }
                                )
                            )

                            SettingsToggleRow(
                                "User Join & Leave Chimes",
                                subtitle: "Play sound effect when other users connect, disconnect, or switch channels.",
                                isOn: Binding(
                                    get: { userActivityCueEnabled },
                                    set: {
                                        userActivityCueEnabled = $0
                                        SoundManager.shared.isUserActivityCueEnabled = $0
                                    }
                                )
                            )

                            SettingsToggleRow(
                                "Incoming Whisper Alert",
                                subtitle: "Play unique notification tone when receiving a direct voice whisper.",
                                isOn: Binding(
                                    get: { whisperCueEnabled },
                                    set: {
                                        whisperCueEnabled = $0
                                        SoundManager.shared.isWhisperCueEnabled = $0
                                    }
                                )
                            )

                            SettingsToggleRow(
                                "Incoming Chat Message Ping",
                                subtitle: "Play subtle message chime when text chat arrives in your channel.",
                                isOn: Binding(
                                    get: { messageCueEnabled },
                                    set: {
                                        messageCueEnabled = $0
                                        SoundManager.shared.isMessageCueEnabled = $0
                                    }
                                )
                            )

                            Divider()

                            HStack(spacing: 8) {
                                Text("Preview Cues:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button {
                                    SoundManager.shared.playMute(isMuted: true)
                                } label: {
                                    Label("Mute", systemImage: "mic.slash.fill")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    SoundManager.shared.playUserJoined()
                                } label: {
                                    Label("Join", systemImage: "person.badge.plus")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    SoundManager.shared.playWhisper()
                                } label: {
                                    Label("Whisper", systemImage: "bubble.left.fill")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)

                                Button {
                                    SoundManager.shared.playMessageReceived()
                                } label: {
                                    Label("Ping", systemImage: "bell.fill")
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .font(.subheadline)
                        .padding(.top, 4)
                    }
                }

                // 3. Liquid Glass Appearance
                SettingsCard {
                    SettingsSectionHeader(
                        "Liquid Glass Appearance",
                        systemImage: "paintpalette.fill",
                        subtitle: "Tints speaking orbs, active VAD meters, and interactive Liquid Glass buttons."
                    )

                    HStack(spacing: 16) {
                        Text("Accent Tint:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 12) {
                            ForEach(accentColors, id: \.name) { item in
                                Button(action: {
                                    store.accentColorName = item.name
                                }) {
                                    Circle()
                                        .fill(item.color)
                                        .frame(width: 26, height: 26)
                                        .overlay {
                                            if store.accentColorName == item.name {
                                                Circle()
                                                    .strokeBorder(Color.white, lineWidth: 2.5)
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .shadow(color: item.color.opacity(store.accentColorName == item.name ? 0.4 : 0.1), radius: 4)
                                }
                                .buttonStyle(.plain)
                                .help(item.name)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }

                // 4. Game Overlay HUD
                SettingsCard {
                    HStack(alignment: .center) {
                        SettingsSectionHeader(
                            "Full-Screen Game Overlay",
                            systemImage: "rectangle.inset.filled.and.cursorarrow",
                            subtitle: "Displays a compact, always-on-top speaking HUD overlay over full-screen games."
                        )
                        Spacer()
                        Button(FloatingOverlayManager.shared.isVisible ? "Hide Overlay" : "Show Overlay") {
                            FloatingOverlayManager.shared.toggle(store: store)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                    }
                }
            }
            .padding(.horizontal, 36)
            .padding(.vertical, 24)
        }
    }
}
