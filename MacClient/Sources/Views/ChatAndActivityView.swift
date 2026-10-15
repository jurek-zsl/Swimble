import SwiftUI
import AppKit

/// Helper for image resizing, compression, clipboard handling, and saving to disk.
struct ChatImageHelper {
    static func prepareImageForMumble(image: NSImage, maxDimension: CGFloat = 800, maxBytes: Int = 80_000) -> String? {
        let origSize = image.size
        guard origSize.width > 0 && origSize.height > 0 else { return nil }

        var newWidth = origSize.width
        var newHeight = origSize.height
        if newWidth > maxDimension || newHeight > maxDimension {
            let ratio = min(maxDimension / newWidth, maxDimension / newHeight)
            newWidth = max(1, origSize.width * ratio)
            newHeight = max(1, origSize.height * ratio)
        }
        let targetSize = NSSize(width: newWidth, height: newHeight)

        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(targetSize.width),
            pixelsHigh: Int(targetSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }
        rep.size = targetSize

        NSGraphicsContext.saveGraphicsState()
        let context = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current = context
        image.draw(
            in: NSRect(origin: .zero, size: targetSize),
            from: NSRect(origin: .zero, size: origSize),
            operation: .copy,
            fraction: 1.0
        )
        NSGraphicsContext.restoreGraphicsState()

        var quality: Float = 0.8
        var jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        while let data = jpegData, data.count > maxBytes && quality > 0.3 {
            quality -= 0.15
            jpegData = rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        }
        guard let finalData = jpegData else { return nil }
        return finalData.base64EncodedString()
    }

    static func loadImageFromPasteboard() -> NSImage? {
        let pb = NSPasteboard.general
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let first = images.first {
            return first
        }
        if let types = pb.types {
            for type in [NSPasteboard.PasteboardType.png, .tiff] {
                if types.contains(type), let data = pb.data(forType: type), let img = NSImage(data: data) {
                    return img
                }
            }
        }
        return nil
    }

    @MainActor
    static func pickImageFile() -> NSImage? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.image, .png, .jpeg, .gif, .webP, .heic]
        if panel.runModal() == .OK, let url = panel.url, let img = NSImage(contentsOf: url) {
            return img
        }
        return nil
    }

    @MainActor
    static func saveImageToDisk(_ image: NSImage) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.jpeg, .png]
        panel.nameFieldStringValue = "mumble-image-\(Int(Date().timeIntervalSince1970)).jpg"
        if panel.runModal() == .OK, let url = panel.url {
            if let tiff = image.tiffRepresentation,
               let rep = NSBitmapImageRep(data: tiff),
               let data = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9]) {
                try? data.write(to: url)
            }
        }
    }
}

/// Detail view displaying the active channel's header, rich chat stream, and compose field.
public struct ChatAndActivityView: View {
    @Bindable public var store: MumbleStore
    @Binding public var showConnectSheet: Bool
    @State private var composeText: String = ""
    @State private var showPingPopover: Bool = false
    @State private var stagedImage: NSImage? = nil
    @State private var stagedImageDimensions: String = ""
    @State private var isDropTargeted: Bool = false
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
                HStack(spacing: 10) {
                    Image(systemName: store.isViewingCurrentChannel ? "speaker.wave.2.fill" : "number")
                        .foregroundStyle(store.isViewingCurrentChannel ? Color.green : Color.secondary)
                        .font(.title3)

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(activeChannelName)
                                .font(.title3.bold())

                            if store.isViewingCurrentChannel {
                                Text("VOICE CONNECTED")
                                    .font(.system(size: 9, weight: .bold))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.green.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.green)
                            }
                        }

                        if let selId = store.selectedChannelId,
                           let ch = store.channels.first(where: { $0.id == selId }),
                           !ch.description.isEmpty {
                            Text(ch.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                // Join Channel Action if viewing another channel
                if !store.isViewingCurrentChannel, let selId = store.selectedChannelId {
                    Button(action: {
                        withAnimation {
                            store.joinChannel(channelId: selId)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Join Channel")
                                .font(.subheadline.bold())
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(store.accentTint)
                    .help("Join this voice channel")
                }

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
                            VStack(spacing: 10) {
                                Image(systemName: "bubble.left.and.bubble.right")
                                    .font(.system(size: 40))
                                    .foregroundStyle(.tertiary)
                                Text("No messages in \(activeChannelName) yet")
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                Text("Type a message below to start chatting.")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
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

                // Staged image preview card if attached
                if let img = stagedImage {
                    HStack(spacing: 12) {
                        Image(nsImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(store.accentTint.opacity(0.4), lineWidth: 1)
                            )

                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 6) {
                                Image(systemName: "photo.badge.checkmark")
                                    .foregroundStyle(store.accentTint)
                                    .font(.caption)
                                Text("Attached Image")
                                    .font(.subheadline.bold())
                            }
                            Text(stagedImageDimensions.isEmpty ? "Ready to send" : stagedImageDimensions)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(action: {
                            stagedImage = nil
                            stagedImageDimensions = ""
                        }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                        .help("Remove attached image")
                    }
                    .padding(8)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.secondary.opacity(0.1))
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                }

                // Message Compose Field
                HStack(spacing: 10) {
                    // Attachment Menu Button
                    Menu {
                        Button(action: chooseImageFile) {
                            Label("Choose Image File...", systemImage: "photo")
                        }
                        Button(action: pasteImageFromClipboard) {
                            Label("Paste Image from Clipboard", systemImage: "doc.on.clipboard")
                        }
                    } label: {
                        Image(systemName: stagedImage != nil ? "paperclip.circle.fill" : "paperclip")
                            .font(.system(size: 18))
                            .foregroundStyle(stagedImage != nil ? store.accentTint : Color.secondary)
                            .frame(width: 28, height: 28)
                            .contentShape(Rectangle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .help("Attach an image (or drop / paste)")

                    HStack(spacing: 8) {
                        Image(systemName: "text.bubble")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))

                        TextField(stagedImage != nil ? "Add a caption (optional)..." : "Message \(activeChannelName)...", text: $composeText)
                            .textFieldStyle(.plain)
                            .focused($isMessageFocused)
                            .onSubmit {
                                submitMessage()
                            }

                        if !composeText.isEmpty {
                            Button(action: { composeText = "" }) {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                                    .font(.system(size: 13))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                    Button(action: submitMessage) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 26))
                            .foregroundStyle((composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && stagedImage == nil) ? Color.secondary.opacity(0.4) : store.accentTint)
                    }
                    .buttonStyle(.plain)
                    .disabled(composeText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && stagedImage == nil)
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.85))
        }
        .dropDestination(for: URL.self) { urls, _ in
            if let first = urls.first, let img = NSImage(contentsOf: first) {
                stageImage(img)
                return true
            }
            return false
        } isTargeted: { targeted in
            withAnimation(.easeInOut(duration: 0.15)) {
                isDropTargeted = targeted
            }
        }
        .onPasteCommand(of: [.image, .fileURL, .png, .tiff]) { providers in
            for provider in providers {
                if provider.canLoadObject(ofClass: NSImage.self) {
                    _ = provider.loadObject(ofClass: NSImage.self) { image, _ in
                        if let img = image as? NSImage {
                            DispatchQueue.main.async {
                                stageImage(img)
                            }
                        }
                    }
                    return
                }
            }
            if let img = ChatImageHelper.loadImageFromPasteboard() {
                stageImage(img)
            }
        }
        .overlay {
            if isDropTargeted {
                ZStack {
                    Color.black.opacity(0.4)
                    VStack(spacing: 12) {
                        Image(systemName: "photo.badge.plus")
                            .font(.system(size: 48))
                            .foregroundStyle(store.accentTint)
                        Text("Drop Image to Attach")
                            .font(.title3.bold())
                            .foregroundStyle(.white)
                    }
                    .padding(32)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
                .transition(.opacity)
            }
        }
    }

    private func chooseImageFile() {
        if let img = ChatImageHelper.pickImageFile() {
            stageImage(img)
        }
    }

    private func pasteImageFromClipboard() {
        if let img = ChatImageHelper.loadImageFromPasteboard() {
            stageImage(img)
        }
    }

    private func stageImage(_ img: NSImage) {
        stagedImage = img
        stagedImageDimensions = "\(Int(img.size.width)) × \(Int(img.size.height)) px"
        isMessageFocused = true
    }

    private func submitMessage() {
        let text = composeText.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.isEmpty && stagedImage == nil { return }

        var finalMessage = text
        if let img = stagedImage {
            if let b64 = ChatImageHelper.prepareImageForMumble(image: img) {
                let imgTag = "<img src=\"data:image/jpeg;base64,\(b64)\" />"
                if text.isEmpty {
                    finalMessage = imgTag
                } else {
                    finalMessage = "<div>\(text)</div><br/>\(imgTag)"
                }
            }
        }

        store.sendChatMessage(channelId: store.selectedChannelId, message: finalMessage)
        composeText = ""
        stagedImage = nil
        stagedImageDimensions = ""
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

/// Wrapper so NSImage can be presented in .sheet(item:)
struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: NSImage
}

/// Full-size image preview modal with copy and save actions.
struct ImagePreviewModal: View {
    let image: NSImage
    @Environment(\.dismiss) private var dismiss
    @State private var copied: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Image Preview")
                    .font(.headline)
                Spacer()
                Button(action: {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([image])
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                }) {
                    Label(copied ? "Copied!" : "Copy", systemImage: copied ? "checkmark" : "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(action: {
                    ChatImageHelper.saveImageToDisk(image)
                }) {
                    Label("Save...", systemImage: "arrow.down.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            ScrollView([.horizontal, .vertical]) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.opacity(0.85))
        }
        .frame(minWidth: 540, minHeight: 420)
    }
}

/// Single chat message row with sanitized HTML/Markdown, base64 data URI and remote image previews.
struct ChatMessageRow: View {
    let message: ChatMessage
    @State private var previewImageItem: IdentifiableImage? = nil

    private var timeString: String {
        let date = Date(timeIntervalSince1970: Double(message.timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private var dataUriImages: [NSImage] {
        extractDataUriImages(from: message.htmlBody)
    }

    private var remoteImageUrls: [URL] {
        extractRemoteImageUrls(from: message.htmlBody)
    }

    private var cleanAttributedText: AttributedString {
        let stripped = cleanText(from: message.htmlBody)
        return parseBody(stripped)
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

            if !cleanAttributedText.characters.isEmpty {
                Text(cleanAttributedText)
                    .font(.body)
                    .textSelection(.enabled)
            }

            // Inline Base64 Data URI Images (from classic Mumble & Swimble users)
            if !dataUriImages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(dataUriImages.enumerated()), id: \.offset) { _, nsImg in
                        Image(nsImage: nsImg)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 240)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                            .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                previewImageItem = IdentifiableImage(image: nsImg)
                            }
                            .help("Click to view full size")
                            .contextMenu {
                                Button("View Full Size") {
                                    previewImageItem = IdentifiableImage(image: nsImg)
                                }
                                Button("Copy Image") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.writeObjects([nsImg])
                                }
                                Button("Save Image As...") {
                                    ChatImageHelper.saveImageToDisk(nsImg)
                                }
                            }
                    }
                }
                .padding(.top, 2)
            }

            // Remote HTTP(S) Images
            if !remoteImageUrls.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(remoteImageUrls, id: \.self) { url in
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxHeight: 240)
                                    .clipShape(RoundedRectangle(cornerRadius: 10))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10)
                                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                                    )
                                    .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
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
                .padding(.top, 2)
            }
        }
        .sheet(item: $previewImageItem) { item in
            ImagePreviewModal(image: item.image)
        }
    }

    private func cleanText(from text: String) -> String {
        return text
            .replacingOccurrences(of: #"(?i)<img[^>]*>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"!\[.*?\]\([^\)]+\)"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?i)<br\s*/?>\s*$"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseBody(_ raw: String) -> AttributedString {
        guard !raw.isEmpty else { return AttributedString("") }
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

    private func extractDataUriImages(from text: String) -> [NSImage] {
        let pattern = #"(?:src=["\x27]|\()data:image\/[a-zA-Z0-9.+-]+;base64,([A-Za-z0-9+\/=\s]+)(?:["\x27]|\))"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let nsString = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))
        return matches.compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let b64 = nsString.substring(with: match.range(at: 1))
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\r", with: "")
                .trimmingCharacters(in: .whitespaces)
            guard let data = Data(base64Encoded: b64), let img = NSImage(data: data) else {
                return nil
            }
            return img
        }
    }

    private func extractRemoteImageUrls(from text: String) -> [URL] {
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
