import SwiftUI
import AppKit

/// Detail view displaying the active channel's header, rich chat stream, and compose field.
public struct ChatAndActivityView: View {
    @Bindable public var store: MumbleStore
    @Binding public var showConnectSheet: Bool
    @State private var composeText: String = ""
    @State private var showPingPopover: Bool = false
    @FocusState private var isMessageFocused: Bool

    public init(store: MumbleStore, showConnectSheet: Binding<Bool>) {
        self.store = store
        self._showConnectSheet = showConnectSheet
    }

    private var activeChannelName: String {
        if let selId = store.selectedChannelId,
           let ch = store.channels.first(where: { $0.id == selId }) {
            return "#\(ch.name)"
        }
        return "Chat"
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(activeChannelName)
                        .font(.title3.bold())

                    if let selId = store.selectedChannelId,
                       let ch = store.channels.first(where: { $0.id == selId }),
                       !ch.description.isEmpty {
                        Text(ch.description)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Live Ping Popover Button
                Button(action: { showPingPopover.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                            .foregroundStyle(store.usingUdpTunnel ? Color.orange : Color.green)

                        Text("\(Int(store.tcpPingMs)) ms")
                            .font(.caption.monospacedDigit().bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showPingPopover) {
                    PingStatsPopover(store: store)
                }

                // Server Favorites / Connect Sheet Button
                Button(action: { showConnectSheet = true }) {
                    Image(systemName: "server.rack")
                        .font(.body)
                }
                .buttonStyle(.bordered)
                .help("Manage Servers & Bookmarks")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.6))

            Divider()

            // Chat Message Stream
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        if store.chatMessages.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 36))
                                    .foregroundStyle(.tertiary)
                                Text("No messages yet")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 60)
                        } else {
                            ForEach(store.chatMessages, id: \.self) { msg in
                                ChatMessageRow(message: msg)
                                    .id(msg.timestamp)
                            }
                        }
                    }
                    .padding(20)
                }
                .onChange(of: store.chatMessages.count) { _, _ in
                    if let last = store.chatMessages.last {
                        withAnimation {
                            proxy.scrollTo(last.timestamp, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Docked Voice Controls & Compose Field
            VStack(spacing: 12) {
                // Docked Voice HUD centered cleanly above the compose bar
                FloatingVoiceHUD(store: store)
                    .frame(maxWidth: .infinity, alignment: .center)

                // Message Compose Field
                HStack(spacing: 12) {
                    TextField("Message \(activeChannelName)...", text: $composeText)
                        .textFieldStyle(.plain)
                        .focused($isMessageFocused)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                        .onSubmit {
                            submitMessage()
                        }

                    Button(action: submitMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 24))
                            .foregroundStyle(composeText.isEmpty ? Color.secondary : Color.accentColor)
                    }
                    .buttonStyle(.plain)
                    .disabled(composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
        }
    }

    private func submitMessage() {
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        store.sendChatMessage(channelId: store.selectedChannelId, message: text)
        composeText = ""
        isMessageFocused = true
    }
}

/// Popover presenting classic Mumble Connection Information dialog.
struct PingStatsPopover: View {
    let store: MumbleStore

    private var info: ServerConnectionInfo? {
        store.connectionInfo
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "info.circle.fill")
                    .foregroundStyle(Color.accentColor)
                Text("Connection Information")
                    .font(.headline)
            }

            Divider()

            // Server Specs
            Group {
                HStack {
                    Text("Server Version:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(info?.serverVersion ?? "Unknown")
                        .bold()
                }

                HStack {
                    Text("Server OS:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    let os = [info?.serverOs, info?.serverOsVersion]
                        .compactMap { $0 }
                        .filter { !$0.isEmpty }
                        .joined(separator: " ")
                    Text(os.isEmpty ? "Unknown" : os)
                        .foregroundStyle(.primary)
                }

                HStack {
                    Text("Encryption (TLS):")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(info?.tlsCipher ?? "TLS 1.3")
                        .font(.caption.monospaced())
                }

                HStack {
                    Text("Audio Bandwidth:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("\(info?.maxBandwidthKbps ?? 64) kbps")
                        .bold()
                }
            }

            Divider()

            // Real-Time Transport Stats
            Group {
                HStack {
                    Text("Voice Transport:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(store.usingUdpTunnel ? "TCP UDPTunnel" : "Encrypted UDP (OCB2)")
                        .font(.caption.bold())
                        .foregroundStyle(store.usingUdpTunnel ? Color.orange : Color.green)
                }

                HStack {
                    Text("TCP / UDP Latency:")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f ms / %.1f ms", store.tcpPingMs, store.udpPingMs))
                        .bold()
                }
            }

            Divider()

            // Packet Quality & Counts
            Group {
                Text("Packet Statistics")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 4) {
                    GridRow {
                        Text("Good:").foregroundStyle(.secondary)
                        Text("\(info?.goodPackets ?? 0)").bold().foregroundStyle(.green)
                        Text("Late:").foregroundStyle(.secondary)
                        Text("\(info?.latePackets ?? 0)").bold().foregroundStyle(.yellow)
                    }
                    GridRow {
                        Text("Lost:").foregroundStyle(.secondary)
                        Text("\(info?.lostPackets ?? 0)").bold().foregroundStyle(.red)
                        Text("Resync:").foregroundStyle(.secondary)
                        Text("\(info?.resyncPackets ?? 0)").bold().foregroundStyle(.orange)
                    }
                    GridRow {
                        Text("UDP Sent:").foregroundStyle(.secondary)
                        Text("\(info?.udpPacketsSent ?? 0)").foregroundStyle(.primary)
                        Text("TCP Sent:").foregroundStyle(.secondary)
                        Text("\(info?.tcpPacketsSent ?? 0)").foregroundStyle(.primary)
                    }
                }
                .font(.caption)
            }
        }
        .padding(14)
        .frame(width: 320)
    }
}

/// Single chat message row with sanitized HTML/Markdown and inline image preview.
struct ChatMessageRow: View {
    let message: ChatMessage

    private var timeString: String {
        let date = Date(timeIntervalSince1970: Double(message.timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var attributedText: AttributedString {
        parseBody(message.htmlBody)
    }

    private var imageUrls: [URL] {
        extractImageUrls(from: message.htmlBody)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(message.senderName)
                    .font(.subheadline.bold())
                    .foregroundStyle(Color.accentColor)

                Text(timeString)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Text(attributedText)
                .font(.body)
                .textSelection(.enabled)

            if !imageUrls.isEmpty {
                HStack(spacing: 10) {
                    ForEach(imageUrls, id: \.self) { url in
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 180)
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                            case .failure:
                                EmptyView()
                            case .empty:
                                ProgressView()
                                    .frame(width: 60, height: 60)
                            @unknown default:
                                EmptyView()
                            }
                        }
                    }
                }
                .padding(.top, 4)
            }
        }
    }

    private func parseBody(_ raw: String) -> AttributedString {
        if let data = raw.data(using: .utf8),
           let nsAttr = try? NSAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
           ) {
            return AttributedString(nsAttr)
        }
        return (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }

    private func extractImageUrls(from text: String) -> [URL] {
        let pattern = #"https?://[^\s"'<>]+\.(?:png|jpg|jpeg|gif|webp)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap {
            let urlString = nsString.substring(with: $0.range)
            return URL(string: urlString)
        }
    }
}
