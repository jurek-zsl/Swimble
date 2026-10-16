import SwiftUI

/// Server Information dialog displaying connection latency, encryption status, bandwidth, and server metadata.
public struct ServerInformationModal: View {
    @Bindable public var store: MumbleStore
    @Environment(\.dismiss) private var dismiss

    public init(store: MumbleStore) {
        self.store = store
    }

    private var info: ServerConnectionInfo? {
        store.connectionInfo
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.title2)
                        .foregroundStyle(store.accentTint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(store.activeBookmark?.name ?? "Server Information")
                            .font(.headline.bold())
                        Text(store.activeBookmark != nil ? "\(store.activeBookmark!.host):\(store.activeBookmark!.port)" : "Connected Server")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))

            Divider()

            ScrollView {
                VStack(spacing: 16) {
                    // 1. Connection & Performance
                    InfoSectionCard(title: "Connection & Latency", systemImage: "antenna.radiowaves.left.and.right") {
                        InfoRow(label: "Connection Status", value: store.connectionStatus == .connected ? "Connected" : "Disconnected", highlight: store.connectionStatus == .connected)
                        InfoRow(label: "TCP Ping (Control)", value: String(format: "%.1f ms", store.tcpPingMs))
                        InfoRow(label: "UDP Ping (Voice)", value: String(format: "%.1f ms", store.udpPingMs))
                        InfoRow(label: "Transport Mode", value: store.usingUdpTunnel ? "TCP Tunnel (Fallback)" : "Direct UDP (Low Latency)")
                    }

                    // 2. Audio & Cryptography
                    InfoSectionCard(title: "Audio & Security", systemImage: "lock.shield.fill") {
                        InfoRow(label: "Voice Codec", value: "Opus 48,000 Hz Mono")
                        InfoRow(label: "UDP Encryption", value: "OCB2-AES128")
                        InfoRow(label: "TLS Cipher", value: info?.tlsCipher.isEmpty == false ? info!.tlsCipher : "TLS 1.3 / AES-GCM")
                        InfoRow(label: "Server Max Bandwidth", value: "\(info?.maxBandwidthKbps ?? 48) kbit/s")
                    }

                    // 3. Server Specifications
                    InfoSectionCard(title: "Server Details", systemImage: "info.circle") {
                        InfoRow(label: "Users Online", value: "\(store.users.count) / \(info?.maxUsers ?? 100)")
                        InfoRow(label: "Channels", value: "\(store.channels.count)")
                        if let sInfo = info {
                            if !sInfo.serverVersion.isEmpty {
                                InfoRow(label: "Server Version", value: sInfo.serverVersion)
                            }
                            if !sInfo.serverOs.isEmpty {
                                InfoRow(label: "Server Host OS", value: "\(sInfo.serverOs) \(sInfo.serverOsVersion)")
                            }
                        }
                    }

                    // 4. Welcome Message preview
                    if let welcome = info?.welcomeText, !welcome.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        InfoSectionCard(title: "Server Welcome Message", systemImage: "envelope.fill") {
                            Text(welcome.replacingOccurrences(of: #"(?i)<[^>]+>"#, with: " ", options: .regularExpression))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 520, height: 560)
    }
}

private struct InfoSectionCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.subheadline.bold())
            }

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var highlight: Bool = false

    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().bold())
                .foregroundStyle(highlight ? Color.green : Color.primary)
        }
    }
}
