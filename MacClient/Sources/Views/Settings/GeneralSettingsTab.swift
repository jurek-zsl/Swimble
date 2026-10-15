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
                VStack(alignment: .leading, spacing: 12) {
                    Text("Startup & Connectivity")
                        .font(.headline)

                    Toggle(isOn: $store.autoReconnectOnLaunch) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Connect to Favorite Server")
                                .font(.subheadline.bold())
                            Text("Automatically connects to your favorite server bookmark when Swimble launches.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .toggleStyle(.switch)
                }
                .padding(16)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                // 2. Audio Cues & Sound Alerts
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Audio Cues & Sound Alerts")
                            .font(.headline)
                        Spacer()
                        Toggle("", isOn: $audioCuesEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .onChange(of: audioCuesEnabled) { _, newValue in
                                SoundManager.shared.isAudioCuesEnabled = newValue
                            }
                    }

                    if audioCuesEnabled {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("Mute & Deafen Chimes", isOn: $muteCueEnabled)
                                .onChange(of: muteCueEnabled) { _, newValue in
                                    SoundManager.shared.isMuteCueEnabled = newValue
                                }

                            Toggle("User Join & Leave Chimes", isOn: $userActivityCueEnabled)
                                .onChange(of: userActivityCueEnabled) { _, newValue in
                                    SoundManager.shared.isUserActivityCueEnabled = newValue
                                }

                            Toggle("Incoming Whisper Alert", isOn: $whisperCueEnabled)
                                .onChange(of: whisperCueEnabled) { _, newValue in
                                    SoundManager.shared.isWhisperCueEnabled = newValue
                                }

                            Toggle("Incoming Chat Message Ping", isOn: $messageCueEnabled)
                                .onChange(of: messageCueEnabled) { _, newValue in
                                    SoundManager.shared.isMessageCueEnabled = newValue
                                }

                            Divider()

                            HStack {
                                Text("Preview System Cues:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                Button("Mute") { SoundManager.shared.playMute(isMuted: true) }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                Button("Join") { SoundManager.shared.playUserJoined() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                Button("Whisper") { SoundManager.shared.playWhisper() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                Button("Ping") { SoundManager.shared.playMessageReceived() }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                            }
                        }
                        .font(.subheadline)
                    }
                }
                .padding(16)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                // 3. Liquid Glass Accent Theme
                VStack(alignment: .leading, spacing: 12) {
                    Text("Liquid Glass Appearance")
                        .font(.headline)

                    HStack(spacing: 12) {
                        Text("Accent Tint:")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)

                        HStack(spacing: 10) {
                            ForEach(accentColors, id: \.name) { item in
                                Button(action: {
                                    store.accentColorName = item.name
                                }) {
                                    Circle()
                                        .fill(item.color)
                                        .frame(width: 22, height: 22)
                                        .overlay {
                                            if store.accentColorName == item.name {
                                                Circle()
                                                    .strokeBorder(Color.white, lineWidth: 2)
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 10, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                }
                                .buttonStyle(.plain)
                                .help(item.name)
                            }
                        }
                    }

                    Text("Tints speaking orbs, VAD active indicators, and interactive Liquid Glass buttons.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(16)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                // 4. Game Overlay
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Full-Screen Game Overlay")
                                .font(.headline)
                            Text("Displays a compact, always-on-top Liquid Glass pill showing who is speaking in full-screen games.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(FloatingOverlayManager.shared.isVisible ? "Hide Overlay" : "Show Overlay") {
                            FloatingOverlayManager.shared.toggle(store: store)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                }
                .padding(16)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding(24)
        }
    }
}
