import SwiftUI
import AppKit

/// Comprehensive Network settings tab matching official Mumble specs.
public struct NetworkSettingsTab: View {
    @Bindable public var store: MumbleStore
    @Bindable public var state: SettingsState = SettingsState.shared

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Connection
                SettingsCard {
                    SettingsSectionHeader(
                        "Connection",
                        systemImage: "network",
                        subtitle: "Protocol tunneling, QoS prioritization, and reconnection behavior."
                    )

                    SettingsToggleRow(
                        "Use TCP Compatibility Mode",
                        subtitle: "Tunnel voice over TCP (useful on restrictive firewalls or hotel WiFi).",
                        isOn: $state.useTcpCompatibilityMode
                    )

                    SettingsToggleRow(
                        "Use QoS to Prioritize Packets",
                        subtitle: "Mark voice packets with Quality of Service tags (DSCP) on your router.",
                        isOn: $state.useQosPrioritizePackets
                    )

                    Divider()

                    SettingsToggleRow(
                        "Reconnect Automatically",
                        subtitle: "Attempt to reconnect when an active connection drops unexpectedly.",
                        isOn: $state.reconnectAutomatically
                    )

                    SettingsToggleRow(
                        "Auto-connect to Last Used Server",
                        subtitle: "Automatically connect to your most recent server on application launch.",
                        isOn: $state.autoConnectLastUsedServer
                    )

                    SettingsToggleRow(
                        "Suppress Certificate and Password Warnings",
                        subtitle: "Bypass self-signed certificate prompts and password dialogs.",
                        isOn: $state.suppressCertPasswordWarnings
                    )
                }

                // 2. Proxy
                SettingsCard {
                    SettingsSectionHeader(
                        "Proxy",
                        systemImage: "shield.lefthalf.filled",
                        subtitle: "Route server connections through an intermediate proxy."
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Proxy Type")
                            .font(.subheadline.bold())
                        Picker("Proxy Type", selection: $state.proxyType) {
                            ForEach(ProxyType.allCases) { t in
                                Text(t.rawValue).tag(t)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: .infinity)
                    }

                    if state.proxyType != .direct {
                        Divider()

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Hostname")
                                    .font(.caption.bold())
                                TextField("proxy.example.com", text: $state.proxyHostname)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Port")
                                    .font(.caption.bold())
                                TextField("1080", value: $state.proxyPort, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                            }
                        }

                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Username (optional)")
                                    .font(.caption.bold())
                                TextField("Username", text: $state.proxyUsername)
                                    .textFieldStyle(.roundedBorder)
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                Text("Password (optional)")
                                    .font(.caption.bold())
                                SecureField("Password", text: $state.proxyPassword)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                }

                // 3. Image Download
                SettingsCard {
                    SettingsSectionHeader(
                        "Image Download",
                        systemImage: "photo.stack.fill",
                        subtitle: "Limit bandwidth and dimensions for inline channel and user chat images."
                    )

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Max Image Size (KB)")
                                .font(.caption.bold())
                            TextField("0 = Unlimited", value: $state.maxImageSizeKb, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Max Width (px)")
                                .font(.caption.bold())
                            TextField("0 = Unlimited", value: $state.maxImageWidthPx, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Max Height (px)")
                                .font(.caption.bold())
                            TextField("0 = Unlimited", value: $state.maxImageHeightPx, format: .number)
                                .textFieldStyle(.roundedBorder)
                        }
                    }

                    Text("Setting a limit of 0 allows images of any size and dimension.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // 4. Privacy
                SettingsCard {
                    SettingsSectionHeader(
                        "Privacy",
                        systemImage: "lock.shield.fill",
                        subtitle: "Local data persistence, external image loading, and server anonymity."
                    )

                    SettingsToggleRow(
                        "Do Not Embed External Image Data",
                        subtitle: "Blocks automatic fetching of remote HTTP/HTTPS images.",
                        isOn: $state.doNotEmbedExternalImages
                    )

                    SettingsToggleRow(
                        "Clear User Comments on Exit",
                        subtitle: "Removes your personal comment/bio when disconnecting from a server.",
                        isOn: $state.clearUserCommentsOnExit
                    )

                    SettingsToggleRow(
                        "Clear Chat Window on Exit",
                        subtitle: "Wipes chat logs and activity streams from memory on disconnect.",
                        isOn: $state.clearChatWindowOnExit
                    )

                    SettingsToggleRow(
                        "Hide OS Information from Servers",
                        subtitle: "Omits macOS version and system hardware architecture from Version packets.",
                        isOn: $state.hideOsInfoFromServers
                    )
                }

                // 5. Services
                SettingsCard {
                    SettingsSectionHeader(
                        "Services",
                        systemImage: "sparkles",
                        subtitle: "Application updates and official plugin synchronization."
                    )

                    SettingsToggleRow(
                        "Check for Application Updates on Startup",
                        subtitle: "Checks GitHub Releases for new Swimble builds on launch.",
                        isOn: $state.checkForUpdatesOnStartup
                    )

                    SettingsToggleRow(
                        "Download Official Plugins Updates on Startup",
                        subtitle: "Keep positional audio game integration plugins up to date.",
                        isOn: $state.downloadOfficialPluginsUpdates
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}
