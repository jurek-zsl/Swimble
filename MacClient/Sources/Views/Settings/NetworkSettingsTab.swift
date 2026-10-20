import SwiftUI
import AppKit

/// Native Network settings tab focused on TCP/UDP connectivity, automatic recovery, and privacy.
public struct NetworkSettingsTab: View {
    @Bindable public var store: MumbleStore
    @Bindable public var state: SettingsState = SettingsState.shared

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Connection & Protocol
                SettingsCard {
                    SettingsSectionHeader(
                        "Connection & Protocol",
                        systemImage: "network",
                        subtitle: "Protocol tunneling, reconnection routines, and certificate policies."
                    )

                    SettingsToggleRow(
                        "Use TCP Compatibility Mode",
                        subtitle: "Tunnel voice over TCP (useful on restrictive firewalls, corporate networks, or hotel Wi-Fi that block UDP port 64738).",
                        isOn: $state.useTcpCompatibilityMode
                    )

                    Divider()

                    SettingsToggleRow(
                        "Reconnect Automatically",
                        subtitle: "Automatically attempt to reconnect if an active connection drops unexpectedly.",
                        isOn: $state.reconnectAutomatically
                    )

                    SettingsToggleRow(
                        "Auto-connect to Last Used Server",
                        subtitle: "Automatically connect to your most recent server bookmark on application launch.",
                        isOn: $state.autoConnectLastUsedServer
                    )

                    Label("Server Identity Verification Enabled", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                    Text("Certificates are checked against macOS trust and the requested hostname. Private certificates require explicit fingerprint approval. Changed saved certificates block the connection until reviewed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                }

                // 2. Privacy & Anonymity
                SettingsCard {
                    SettingsSectionHeader(
                        "Privacy & Anonymity",
                        systemImage: "lock.shield.fill",
                        subtitle: "Local data persistence, external image loading, and server metadata."
                    )

                    SettingsToggleRow(
                        "Block External Remote Images",
                        subtitle: "Blocks automatic fetching of remote HTTP/HTTPS images in chat or channel descriptions to prevent IP tracking.",
                        isOn: $state.doNotEmbedExternalImages
                    )

                    SettingsToggleRow(
                        "Clear User Comments on Exit",
                        subtitle: "Removes your personal comment/bio when disconnecting from a server.",
                        isOn: $state.clearUserCommentsOnExit
                    )

                    SettingsToggleRow(
                        "Clear Chat Window on Exit",
                        subtitle: "Wipes chat history and message logs from memory upon disconnecting.",
                        isOn: $state.clearChatWindowOnExit
                    )

                    SettingsToggleRow(
                        "Hide OS Information from Servers",
                        subtitle: "Omits macOS build version and system hardware architecture from client Version packets.",
                        isOn: $state.hideOsInfoFromServers
                    )
                }

                // 3. Application Updates
                SettingsCard {
                    SettingsSectionHeader(
                        "Software Updates",
                        systemImage: "sparkles",
                        subtitle: "Automated version verification on launch."
                    )

                    Button("Check for Updates Now") { Task { await UpdateChecker.shared.check() } }
                        .disabled(UpdateChecker.shared.checking)
                    if !UpdateChecker.shared.status.isEmpty { Text(UpdateChecker.shared.status).font(.caption) }
                    SettingsToggleRow(
                        "Check for Application Updates on Startup",
                        subtitle: "Checks GitHub Releases for new Swimble builds on launch.",
                        isOn: $state.checkForUpdatesOnStartup
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}
