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

    private static let supportedImageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp", "ico"
    ]

    static func isImageFile(url: URL) -> Bool {
        return supportedImageExtensions.contains(url.pathExtension.lowercased())
    }

    static func loadImageFromPasteboard() -> NSImage? {
        let pb = NSPasteboard.general

        // 1. Check for direct NSImage objects (Safari/Chrome 'Copy Image', Preview, etc.)
        if let images = pb.readObjects(forClasses: [NSImage.self], options: nil) as? [NSImage], let first = images.first {
            return first
        }

        // 2. Check for raw image data types (PNG, TIFF, JPEG, WebP)
        let imageTypes: [NSPasteboard.PasteboardType] = [
            .png,
            .tiff,
            NSPasteboard.PasteboardType("public.png"),
            NSPasteboard.PasteboardType("public.tiff"),
            NSPasteboard.PasteboardType("public.jpeg"),
            NSPasteboard.PasteboardType("org.webmproject.webp"),
            NSPasteboard.PasteboardType("com.compuserve.gif")
        ]
        if let availableTypes = pb.types {
            for type in imageTypes {
                if availableTypes.contains(type), let data = pb.data(forType: type), let img = NSImage(data: data) {
                    return img
                }
            }
        }

        // 3. Check for copied files via NSURL (e.g. copied image file in Finder or Desktop)
        if let nsUrls = pb.readObjects(forClasses: [NSURL.self], options: nil) as? [NSURL] {
            for nsUrl in nsUrls {
                let url = nsUrl as URL
                if isImageFile(url: url), let img = NSImage(contentsOf: url) {
                    return img
                }
            }
        }

        // 4. Check for copied file paths via NSFilenamesPboardType (Finder standard file pasteboard)
        if let filenames = pb.propertyList(forType: NSPasteboard.PasteboardType("NSFilenamesPboardType")) as? [String] {
            for path in filenames {
                let url = URL(fileURLWithPath: path)
                if isImageFile(url: url), let img = NSImage(contentsOfFile: path) {
                    return img
                }
            }
        }

        // 5. Inspect individual NSPasteboardItems
        if let items = pb.pasteboardItems {
            for item in items {
                for type in imageTypes {
                    if let data = item.data(forType: type), let img = NSImage(data: data) {
                        return img
                    }
                }
                if let urlString = item.string(forType: .fileURL), let url = URL(string: urlString) {
                    if isImageFile(url: url), let img = NSImage(contentsOf: url) {
                        return img
                    }
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

/// An AppKit-backed single-line text field for the chat compose box that intercepts
/// paste events (Cmd+V and Edit -> Paste) to automatically stage copied images (screenshots,
/// Finder image files, clipboard bitmaps) while delegating plain text pastes and Enter-to-send.
struct ChatInputField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    @Binding var isFocused: Bool
    var onPasteImage: (NSImage) -> Void
    var onSubmit: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSTextField {
        let textField = CustomPasteTextField()
        textField.isBordered = false
        textField.drawsBackground = false
        textField.focusRingType = .none
        textField.font = .systemFont(ofSize: 13.5, weight: .regular)
        textField.textColor = .labelColor
        textField.placeholderString = placeholder
        textField.delegate = context.coordinator
        textField.coordinator = context.coordinator
        textField.cell?.wraps = false
        textField.cell?.isScrollable = true
        return textField
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        if nsView.stringValue != text {
            nsView.stringValue = text
        }
        if nsView.placeholderString != placeholder {
            nsView.placeholderString = placeholder
        }
        context.coordinator.parent = self

        if isFocused {
            DispatchQueue.main.async {
                if let window = nsView.window,
                   window.firstResponder != nsView,
                   window.firstResponder != nsView.currentEditor() {
                    window.makeFirstResponder(nsView)
                }
            }
        }
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: ChatInputField

        init(_ parent: ChatInputField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            if let field = obj.object as? NSTextField {
                parent.text = field.stringValue
            }
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            parent.isFocused = true
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            parent.isFocused = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            if commandSelector == #selector(NSText.paste(_:)) {
                if let img = ChatImageHelper.loadImageFromPasteboard() {
                    parent.onPasteImage(img)
                    return true
                }
            }
            return false
        }
    }
}

private class CustomPasteTextField: NSTextField {
    weak var coordinator: ChatInputField.Coordinator?

    override var intrinsicContentSize: NSSize {
        var size = super.intrinsicContentSize
        size.height = max(size.height, 22)
        return size
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.intersection([.deviceIndependentFlagsMask]).contains(.command) &&
           (event.charactersIgnoringModifiers?.lowercased() == "v") {
            if let img = ChatImageHelper.loadImageFromPasteboard() {
                coordinator?.parent.onPasteImage(img)
                return true
            }
        }
        return super.performKeyEquivalent(with: event)
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
    @State private var isFieldFocused: Bool = true
    @State private var pasteKeyMonitor: Any? = nil
    @State private var showChannelDescPopover: Bool = false
    private let bottomAnchorId = "chat_bottom_anchor"

    public init(store: MumbleStore, showConnectSheet: Binding<Bool>) {
        self.store = store
        self._showConnectSheet = showConnectSheet
    }

    private var activeChannelName: String {
        switch store.activeChatTab {
        case .server:
            return store.activeBookmark?.name ?? "Server Activity"
        case .channel(let cid):
            if let ch = store.channels.first(where: { $0.id == cid }) {
                return "#\(ch.name)"
            }
            return "#\(store.channelName(for: cid))"
        case .direct(_, let name):
            return "@\(name)"
        }
    }

    private func tabTitle(_ tab: ChatTabTarget) -> String {
        switch tab {
        case .server:
            return store.activeBookmark?.name ?? "Server"
        case .channel(let cid):
            return "#\(store.channelName(for: cid))"
        case .direct(_, let name):
            return "@\(name)"
        }
    }

    private func tabIcon(_ tab: ChatTabTarget) -> String {
        switch tab {
        case .server:
            return "server.rack"
        case .channel(let cid):
            return cid == store.myChannelId ? "speaker.wave.2.fill" : "number"
        case .direct:
            return "person.fill"
        }
    }

    private func messagesForTab(_ tab: ChatTabTarget) -> [ChatMessage] {
        switch tab {
        case .server:
            return store.chatMessages
        case .channel(let cid):
            return store.chatMessages.filter { msg in
                if msg.channelId == cid { return true }
                if msg.senderSession == 0 && (msg.channelId == nil || msg.channelId == cid) { return true }
                return false
            }
        case .direct(let sid, _):
            return store.chatMessages.filter { msg in
                if msg.channelId == nil {
                    if msg.senderSession == sid { return true }
                    if msg.senderSession == (store.mySessionId ?? 0) && msg.recipientSession == sid { return true }
                }
                return false
            }
        }
    }

    private var filteredChatMessages: [ChatMessage] {
        messagesForTab(store.activeChatTab)
    }

    @ViewBuilder
    private func chatStreamView(for tab: ChatTabTarget) -> some View {
        let messages = messagesForTab(tab)
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if messages.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "bubble.left.and.bubble.right")
                                .font(.system(size: 40))
                                .foregroundStyle(.tertiary)
                            Text("No messages in \(tabTitle(tab)) yet")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                            Text("Type a message below to start chatting.")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 60)
                    } else {
                        ForEach(Array(messages.enumerated()), id: \.offset) { index, msg in
                            ChatMessageRow(message: msg, accentTint: store.accentTint)
                                .id("msg_\(index)")
                        }

                        // Explicit anchor at the absolute bottom of the chat stream
                        Color.clear
                            .frame(height: 1)
                            .id(bottomAnchorId)
                    }
                }
                .padding(20)
            }
            .defaultScrollAnchor(.bottom)
            .onChange(of: messages.count) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onChange(of: messages.last?.htmlBody) { _, _ in
                scrollToBottom(proxy: proxy, animated: true)
            }
            .onAppear {
                scrollToBottom(proxy: proxy, animated: false)
            }
        }
    }

    @ViewBuilder
    private func channelDescriptionPopover(ch: ChannelInfo) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(store.accentTint)
                Text(ch.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    showChannelDescPopover = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                RichDescriptionView(rawHtml: ch.description, accentTint: store.accentTint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 520)
        .frame(minHeight: 120, maxHeight: 460)
        .lineLimit(nil)
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
                            Button(action: { showChannelDescPopover.toggle() }) {
                                HStack(spacing: 5) {
                                    Text(cleanChatMessageText(from: ch.description))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)

                                    if containsImages(ch.description) {
                                        Image(systemName: "photo.badge.checkmark")
                                            .font(.caption2)
                                            .foregroundStyle(store.accentTint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help("Click to view full description and images")
                            .popover(isPresented: $showChannelDescPopover) {
                                channelDescriptionPopover(ch: ch)
                            }
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

                // Open Chat Menu Button
                Menu {
                    Section("Channels") {
                        ForEach(store.channels, id: \.id) { ch in
                            Button("#\(ch.name)") {
                                withAnimation {
                                    store.openChannelChat(channelId: ch.id)
                                }
                            }
                        }
                    }

                    let otherUsers = store.users.filter { $0.sessionId != store.mySessionId }
                    if !otherUsers.isEmpty {
                        Section("Direct Messages") {
                            ForEach(otherUsers, id: \.sessionId) { u in
                                Button("@\(u.name)") {
                                    withAnimation {
                                        store.openDirectChat(sessionId: u.sessionId, userName: u.name)
                                    }
                                }
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.bubble.fill")
                            .font(.caption2)
                        Text("Open Chat")
                            .font(.caption.bold())
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .help("Open channel or direct message chat tab")

                // Close active tab button (if not server)
                if store.activeChatTab != .server {
                    Button(action: {
                        withAnimation {
                            store.closeChatTab(store.activeChatTab)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.caption2)
                            Text("Close Tab")
                                .font(.caption)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.secondary.opacity(0.12), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut("w", modifiers: .command)
                    .help("Close current chat tab (⌘W)")
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.6))

            Divider()

            // Native SwiftUI TabView for different chats
            TabView(selection: $store.activeChatTab) {
                ForEach(store.openChatTabs) { tab in
                    chatStreamView(for: tab)
                        .tabItem {
                            Label(tabTitle(tab), systemImage: tabIcon(tab))
                        }
                        .tag(tab)
                        .badge(store.unreadTabCounts[tab.id] ?? 0)
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
                        ChatInputField(
                            text: $composeText,
                            placeholder: stagedImage != nil ? "Add a caption (optional)..." : "Message \(activeChannelName)...",
                            isFocused: $isFieldFocused,
                            onPasteImage: { img in
                                stageImage(img)
                            },
                            onSubmit: {
                                submitMessage()
                            }
                        )
                        .frame(minHeight: 22)

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
        .onAppear {
            setupPasteMonitor()
        }
        .onDisappear {
            removePasteMonitor()
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
                } else if provider.canLoadObject(ofClass: URL.self) {
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in
                        if let url = url, let img = NSImage(contentsOf: url) {
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

    private func setupPasteMonitor() {
        if pasteKeyMonitor == nil {
            pasteKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                // Intercept Cmd+V anywhere in the active window
                if event.modifierFlags.intersection([.deviceIndependentFlagsMask]).contains(.command) &&
                   (event.charactersIgnoringModifiers?.lowercased() == "v") {
                    if let img = ChatImageHelper.loadImageFromPasteboard() {
                        stageImage(img)
                        return nil // Suppress event so text field doesn't beep or drop
                    }
                }
                return event
            }
        }
    }

    private func removePasteMonitor() {
        if let monitor = pasteKeyMonitor {
            NSEvent.removeMonitor(monitor)
            pasteKeyMonitor = nil
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
        isFieldFocused = true
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

        switch store.activeChatTab {
        case .server:
            let targetChId = store.selectedChannelId ?? store.myChannelId
            store.sendChatMessage(channelId: targetChId, message: finalMessage)
        case .channel(let cid):
            store.sendChatMessage(channelId: cid, message: finalMessage)
        case .direct(let sid, _):
            store.sendUserMessage(sessionId: sid, message: finalMessage)
        }

        composeText = ""
        stagedImage = nil
        stagedImageDimensions = ""
        isFieldFocused = true
    }

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool = true) {
        guard !filteredChatMessages.isEmpty else { return }
        // Initial immediate dispatch
        DispatchQueue.main.async {
            if animated {
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        }
        // Follow-up pass to guarantee scroll position after SwiftUI view measuring and image rendering
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            if animated {
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo(bottomAnchorId, anchor: .bottom)
                }
            } else {
                proxy.scrollTo(bottomAnchorId, anchor: .bottom)
            }
        }
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

/// In-memory cache for remote chat images
final class ImageCache: @unchecked Sendable {
    nonisolated(unsafe) static let shared = NSCache<NSURL, NSImage>()
}

/// Loads and renders remote HTTP/HTTPS images with fallback card, tap-to-preview, and context actions.
struct RemoteChatImageView: View {
    let url: URL
    let onSelect: (NSImage) -> Void

    @State private var loadedImage: NSImage? = nil
    @State private var isLoading: Bool = true
    @State private var loadFailed: Bool = false

    var body: some View {
        Group {
            if let img = loadedImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 260)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                    .shadow(color: Color.black.opacity(0.12), radius: 4, x: 0, y: 2)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(img)
                    }
                    .help("Click to view full size")
                    .contextMenu {
                        Button("View Full Size") {
                            onSelect(img)
                        }
                        Button("Copy Image") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.writeObjects([img])
                        }
                        Button("Save Image As...") {
                            ChatImageHelper.saveImageToDisk(img)
                        }
                        Divider()
                        Button("Open in Browser") {
                            NSWorkspace.shared.open(url)
                        }
                    }
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Loading image...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "photo.badge.exclamationmark")
                        .foregroundStyle(.secondary)
                    Link(url.lastPathComponent.isEmpty ? (url.host ?? url.absoluteString) : url.lastPathComponent, destination: url)
                        .font(.caption)
                        .lineLimit(1)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .task(id: url) {
            await fetchImage()
        }
    }

    private func fetchImage() async {
        if let cached = ImageCache.shared.object(forKey: url as NSURL) {
            self.loadedImage = cached
            self.isLoading = false
            return
        }

        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Swimble/1.0", forHTTPHeaderField: "User-Agent")
        request.setValue("image/webp,image/png,image/jpeg,image/*;q=0.8,*/*;q=0.5", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
               let img = NSImage(data: data) {
                ImageCache.shared.setObject(img, forKey: url as NSURL)
                self.loadedImage = img
                self.isLoading = false
            } else {
                self.loadFailed = true
                self.isLoading = false
            }
        } catch {
            self.loadFailed = true
            self.isLoading = false
        }
    }
}

/// Compact, elegant pill for server system events (e.g. "You joined #Channel", "You moved User to #Channel")
struct SystemEventPillView: View {
    let message: ChatMessage
    let accentTint: Color

    private var timeString: String {
        let date = Date(timeIntervalSince1970: Double(message.timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private var iconName: String {
        let text = message.htmlBody
        if text.contains("Unable to Enter") {
            return "lock.fill"
        } else if text.contains("Connection rejected") {
            return "xmark.octagon.fill"
        } else if text.contains("Permission denied") || text.contains("denied") || text.contains("Denied:") {
            return "hand.raised.fill"
        } else if text.contains("banned") {
            return "person.crop.circle.badge.xmark"
        } else if text.contains("kicked") {
            return "person.fill.xmark"
        } else if text.contains("Server connection closed") {
            return "wifi.slash"
        } else if text.contains("Connected to server") {
            return "wifi"
        } else if text.contains("priority speaker") {
            return "star.fill"
        } else if text.contains("recording") {
            return "record.circle.fill"
        } else if text.contains("registered") {
            return "checkmark.seal.fill"
        } else if text.contains("avatar") {
            return "person.crop.circle.fill"
        } else if text.contains("comment") {
            return "text.bubble.fill"
        } else if text.contains("Channel '") {
            return "number"
        } else if text.contains("You joined") || text.contains("joined the channel") {
            return "arrow.right.circle.fill"
        } else if text.contains("moved") {
            return "arrow.turn.down.right"
        } else if text.contains("disconnected") {
            return "person.badge.minus"
        } else if text.contains("connected") {
            return "person.badge.plus"
        } else if text.contains("muted") {
            return text.contains("unmuted") ? "mic.fill" : "mic.slash.fill"
        } else if text.contains("deafened") {
            return text.contains("undeafened") ? "speaker.wave.2.fill" : "speaker.slash.fill"
        } else {
            return "info.circle.fill"
        }
    }

    private var iconColor: Color {
        let text = message.htmlBody
        if text.contains("Unable to Enter") || text.contains("Connection rejected") || text.contains("Permission denied") || text.contains("denied") || text.contains("Denied:") || text.contains("banned") {
            return .red
        } else if text.contains("kicked") || text.contains("moved") {
            return .orange
        } else if text.contains("priority speaker") {
            return .yellow
        } else if text.contains("recording") {
            return .red
        } else if text.contains("registered") || text.contains("Connected to server") {
            return .green
        } else if text.contains("disconnected") || text.contains("Server connection closed") {
            return .secondary
        } else if text.contains("connected") {
            return .green
        } else if text.contains("muted") {
            return text.contains("unmuted") ? .green : .red
        } else if text.contains("deafened") {
            return text.contains("undeafened") ? .green : .red
        } else {
            return accentTint
        }
    }

    private var textForegroundColor: Color {
        let text = message.htmlBody
        if text.contains("Unable to Enter") || text.contains("Connection rejected") || text.contains("Permission denied") || text.contains("Denied:") || text.contains("banned") {
            return .red
        } else if text.contains("kicked") {
            return .orange
        } else {
            return .primary
        }
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(timeString)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(.tertiary)

            Image(systemName: iconName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(iconColor)

            Text(cleanChatMessageText(from: message.htmlBody))
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(textForegroundColor)
                .textSelection(.enabled)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
        .background {
            Capsule(style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.6))
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.03), radius: 3, x: 0, y: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 2)
    }
}

/// Formatted server welcome message card rendering Markdown with active links and Liquid Glass styling.
struct ServerWelcomeCardView: View {
    let message: ChatMessage
    let accentTint: Color

    private var timeString: String {
        let date = Date(timeIntervalSince1970: Double(message.timestamp) / 1000.0)
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }

    private var isPreformatted: Bool {
        message.htmlBody.contains("<pre") ||
        message.htmlBody.contains("<code") ||
        message.htmlBody.contains("<tt") ||
        message.htmlBody.contains("Courier") ||
        message.htmlBody.contains("Menlo") ||
        message.htmlBody.contains("Consolas") ||
        message.htmlBody.contains("monospace") ||
        message.htmlBody.contains("font-family") ||
        message.htmlBody.contains("╔") ||
        message.htmlBody.contains("║") ||
        message.htmlBody.contains("╚") ||
        message.htmlBody.contains("═") ||
        message.htmlBody.contains("┌") ||
        message.htmlBody.contains("─") ||
        message.htmlBody.contains("│") ||
        message.htmlBody.contains("└") ||
        message.htmlBody.contains(".----.") ||
        message.htmlBody.contains(".--.") ||
        message.htmlBody.contains("---") ||
        message.htmlBody.contains("___") ||
        message.htmlBody.contains("===") ||
        message.htmlBody.contains("/\\") ||
        message.htmlBody.contains("\\/") ||
        message.htmlBody.contains("  ")
    }

    private var parsedWelcomeText: AttributedString {
        parseChatMessageBody(cleanChatMessageText(from: message.htmlBody), isPreformatted: isPreformatted)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Header Bar
            HStack(spacing: 8) {
                Image(systemName: "server.rack")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(accentTint)

                Text("Server Welcome Message")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.primary)

                Text("SERVER")
                    .font(.system(size: 9, weight: .heavy))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(accentTint.opacity(0.18), in: Capsule())
                    .foregroundStyle(accentTint)

                Spacer()

                Text(timeString)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Divider()

            // Preformatted / Rich Welcome Message
            if isPreformatted {
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(parsedWelcomeText)
                        .font(.system(size: 12.5, design: .monospaced))
                        .multilineTextAlignment(.leading)
                        .lineSpacing(1)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 2)
                }
            } else {
                Text(parsedWelcomeText)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.65))
                .overlay {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(accentTint.opacity(0.25), lineWidth: 0.8)
                }
                .shadow(color: Color.black.opacity(0.04), radius: 4, x: 0, y: 1)
        }
        .padding(.vertical, 4)
    }
}

/// Single chat message row supporting system event pills, server welcome cards, and user messages.
struct ChatMessageRow: View {
    let message: ChatMessage
    let accentTint: Color
    @State private var previewImageItem: IdentifiableImage? = nil

    private var isSystemMessage: Bool {
        (message.senderSession == 0 && message.senderName == "System") ||
        message.htmlBody.contains("Permission denied") ||
        message.htmlBody.contains("Unable to Enter") ||
        message.htmlBody.contains("Connection rejected:") ||
        message.htmlBody.contains("Denied:")
    }

    private var isServerWelcome: Bool {
        message.senderSession == 0 && message.senderName == "Server" && !message.htmlBody.contains("Permission denied")
    }

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
        let stripped = cleanChatMessageText(from: message.htmlBody)
        return parseChatMessageBody(stripped)
    }

    var body: some View {
        if isSystemMessage {
            SystemEventPillView(message: message, accentTint: accentTint)
        } else if isServerWelcome {
            ServerWelcomeCardView(message: message, accentTint: accentTint)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(message.senderName)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(accentTint)

                    Text(timeString)
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }

                if !cleanAttributedText.characters.isEmpty {
                    Text(cleanAttributedText)
                        .font(.system(size: 13.5, weight: .regular))
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }

                // Inline Base64 Data URI Images (from classic Mumble & Swimble users)
                if !dataUriImages.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(dataUriImages.enumerated()), id: \.offset) { _, nsImg in
                            Image(nsImage: nsImg)
                                .resizable()
                                .scaledToFit()
                                .frame(maxHeight: 260)
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
                            RemoteChatImageView(url: url) { selectedImg in
                                previewImageItem = IdentifiableImage(image: selectedImg)
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
    }
}

func cleanChatMessageText(from text: String) -> String {
    return text
        // Remove full <img> tags
        .replacingOccurrences(of: #"(?i)<img\b[^>]*>"#, with: "", options: .regularExpression)
        // Remove markdown images
        .replacingOccurrences(of: #"!\[.*?\]\([^\)]+\)"#, with: "", options: .regularExpression)
        // Remove <a> tags that wrap data: URIs
        .replacingOccurrences(of: #"(?i)<a\b[^>]*?\bhref=["\']data:image\/[^"\']+["\'][^>]*>.*?<\/a>"#, with: "", options: .regularExpression)
        // Remove raw data:image URIs that might remain in chat
        .replacingOccurrences(of: #"(?i)data:image\/[^;,]+(?:;[^;,]+)*;base64,[A-Za-z0-9+\/=\s%]+"#, with: "", options: .regularExpression)
        // Remove empty <a> tags
        .replacingOccurrences(of: #"(?i)<a\b[^>]*?>\s*<\/a>"#, with: "", options: .regularExpression)
        // Remove trailing line breaks
        .replacingOccurrences(of: #"(?i)<br\s*\/?>\s*$"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .newlines)
}

func parseChatMessageBody(_ raw: String, isPreformatted: Bool? = nil) -> AttributedString {
    guard !raw.isEmpty else { return AttributedString("") }

    let preformatted = isPreformatted ?? (
        raw.contains("<pre") ||
        raw.contains("<code") ||
        raw.contains("<tt") ||
        raw.contains("Courier") ||
        raw.contains("Menlo") ||
        raw.contains("Consolas") ||
        raw.contains("monospace") ||
        raw.contains("╔") ||
        raw.contains("║") ||
        raw.contains("╚") ||
        raw.contains("═") ||
        raw.contains("┌") ||
        raw.contains("─") ||
        raw.contains("│") ||
        raw.contains("└") ||
        raw.contains(".----.") ||
        raw.contains(".--.")
    )

    // Plain text messages (no HTML tags) render directly with native typography
    if !raw.contains("<") || !raw.contains(">") {
        if preformatted {
            var attr = AttributedString(raw)
            attr.font = .system(size: 12.5, design: .monospaced)
            attr.foregroundColor = .primary
            return attr
        }
        if let md = try? AttributedString(markdown: raw) {
            return md
        }
        return AttributedString(raw)
    }

    let fontDeclaration: String
    let whiteSpaceDeclaration: String
    let lineHeight: String

    if preformatted {
        fontDeclaration = "font-family: Menlo, Monaco, Consolas, \"Courier New\", monospace !important;"
        whiteSpaceDeclaration = "white-space: pre !important;"
        lineHeight = "line-height: 1.2;"
    } else {
        fontDeclaration = "font-family: -apple-system, BlinkMacSystemFont, \"SF Pro Text\", \"SF Pro\", \"Helvetica Neue\", Helvetica, Arial, sans-serif;"
        whiteSpaceDeclaration = "white-space: pre-wrap !important;"
        lineHeight = "line-height: 1.35;"
    }

    let styledHtml = """
    <!DOCTYPE html><html><head><meta charset="utf-8"><style>
    body {
        \(fontDeclaration)
        \(whiteSpaceDeclaration)
        \(lineHeight)
        font-size: 12.5px;
        margin: 0;
        padding: 0;
    }
    pre, code, tt, kbd, samp {
        font-family: Menlo, Monaco, Consolas, "Courier New", monospace !important;
        white-space: pre !important;
    }
    </style></head><body>\(raw)</body></html>
    """

    guard let data = styledHtml.data(using: .utf8),
          let nsAttr = try? NSMutableAttributedString(
            data: data,
            options: [
                .documentType: NSAttributedString.DocumentType.html,
                .characterEncoding: String.Encoding.utf8.rawValue
            ],
            documentAttributes: nil
          ) else {
        if preformatted {
            var attr = AttributedString(raw)
            attr.font = .system(size: 12.5, design: .monospaced)
            return attr
        }
        return (try? AttributedString(markdown: raw)) ?? AttributedString(raw)
    }

    // Sanitize fonts and preserve colors from HTML
    nsAttr.enumerateAttributes(in: NSRange(location: 0, length: nsAttr.length)) { attrs, range, _ in
        if let font = attrs[.font] as? NSFont {
            let isBold = font.fontDescriptor.symbolicTraits.contains(.bold)
            let isItalic = font.fontDescriptor.symbolicTraits.contains(.italic)
            let isMono = preformatted ||
                         font.isFixedPitch ||
                         font.fontDescriptor.symbolicTraits.contains(.monoSpace) ||
                         font.fontName.lowercased().contains("courier") ||
                         font.fontName.lowercased().contains("menlo") ||
                         font.fontName.lowercased().contains("mono")
            let weight: NSFont.Weight = isBold ? .bold : .regular
            let pointSize: CGFloat = font.pointSize > 0 ? font.pointSize : 12.5

            var newFont: NSFont
            if isMono {
                if let menlo = NSFont(name: "Menlo", size: pointSize) {
                    if isBold {
                        let boldDesc = menlo.fontDescriptor.withSymbolicTraits(.bold)
                        newFont = NSFont(descriptor: boldDesc, size: pointSize) ?? menlo
                    } else {
                        newFont = menlo
                    }
                } else if let courier = NSFont(name: "Courier New", size: pointSize) {
                    if isBold {
                        let boldDesc = courier.fontDescriptor.withSymbolicTraits(.bold)
                        newFont = NSFont(descriptor: boldDesc, size: pointSize) ?? courier
                    } else {
                        newFont = courier
                    }
                } else {
                    newFont = NSFont.monospacedSystemFont(ofSize: pointSize, weight: weight)
                }
            } else {
                newFont = NSFont.systemFont(ofSize: pointSize, weight: weight)
            }
            if isItalic {
                let italicDesc = newFont.fontDescriptor.withSymbolicTraits(.italic)
                newFont = NSFont(descriptor: italicDesc, size: pointSize) ?? newFont
            }
            nsAttr.addAttribute(.font, value: newFont, range: range)
        }

        // Preserve colors from HTML: if no color or if near-black in dark mode, use dynamic labelColor
        if let fg = attrs[.foregroundColor] as? NSColor {
            if let rgb = fg.usingColorSpace(.sRGB) {
                if rgb.redComponent < 0.08 && rgb.greenComponent < 0.08 && rgb.blueComponent < 0.08 {
                    nsAttr.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
                }
            }
        } else {
            nsAttr.addAttribute(.foregroundColor, value: NSColor.labelColor, range: range)
        }
        nsAttr.removeAttribute(.strokeColor, range: range)
        nsAttr.removeAttribute(.strokeWidth, range: range)
    }

    // Trim leading and trailing newlines added by HTML block elements (<p>, <div>, etc.)
    while nsAttr.string.hasPrefix("\n") || nsAttr.string.hasPrefix("\r") {
        nsAttr.deleteCharacters(in: NSRange(location: 0, length: 1))
    }
    while nsAttr.string.hasSuffix("\n") || nsAttr.string.hasSuffix("\r") {
        nsAttr.deleteCharacters(in: NSRange(location: nsAttr.length - 1, length: 1))
    }

    var swiftUiAttr = AttributedString(nsAttr)
    for run in swiftUiAttr.runs {
        if let appKitFont = run.appKit.font {
            swiftUiAttr[run.range].font = Font(appKitFont)
        }
        if let appKitColor = run.appKit.foregroundColor {
            swiftUiAttr[run.range].foregroundColor = Color(nsColor: appKitColor)
        }
    }

    return swiftUiAttr
}

func extractDataUriImages(from text: String) -> [NSImage] {
    // Matches data:image/...;base64,<base64data> in src="...", src='...', src=..., href="...", or raw
    let pattern = #"(?:data:image\/[^;,]+(?:;[^;,]+)*;base64,)([A-Za-z0-9+\/=\s%]+)"#
    guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
        return []
    }
    let nsString = text as NSString
    let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsString.length))

    var seenHashes = Set<Int>()
    return matches.compactMap { match in
        guard match.numberOfRanges > 1 else { return nil }
        var rawB64 = nsString.substring(with: match.range(at: 1))

        // Stop at any HTML tag delimiter, attribute quote, or parenthesis
        if let termIdx = rawB64.firstIndex(where: { "\"'<>)".contains($0) }) {
            rawB64 = String(rawB64[..<termIdx])
        }

        // Percent-decode if URL-encoded
        if rawB64.contains("%"), let decoded = rawB64.removingPercentEncoding {
            rawB64 = decoded
        }

        // Strip ALL whitespaces, newlines, tabs, and carriage returns (fixes Qt 80-col line wrapping)
        let cleanB64 = rawB64.components(separatedBy: .whitespacesAndNewlines).joined()
        guard !cleanB64.isEmpty else { return nil }

        let hash = cleanB64.hashValue
        guard seenHashes.insert(hash).inserted else { return nil }

        guard let data = Data(base64Encoded: cleanB64, options: .ignoreUnknownCharacters),
              let img = NSImage(data: data) else {
            return nil
        }
        return img
    }
}

func extractRemoteImageUrls(from text: String) -> [URL] {
    var urls: [URL] = []

    // Pattern A: <img ... src="url" ...> or <img ... src='url' ...>
    let imgTagPattern = #"(?i)<img\b[^>]*?\bsrc\s*=\s*["\'](https?:\/\/[^"\']+)["\']"#
    if let imgRegex = try? NSRegularExpression(pattern: imgTagPattern) {
        let ns = text as NSString
        let matches = imgRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches where m.numberOfRanges > 1 {
            if let u = URL(string: ns.substring(with: m.range(at: 1))) {
                urls.append(u)
            }
        }
    }

    // Pattern B: Markdown image: ![...](https://...)
    let mdPattern = #"!\[.*?\]\((https?:\/\/[^\s\)]+)\)"#
    if let mdRegex = try? NSRegularExpression(pattern: mdPattern) {
        let ns = text as NSString
        let matches = mdRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches where m.numberOfRanges > 1 {
            if let u = URL(string: ns.substring(with: m.range(at: 1))) {
                urls.append(u)
            }
        }
    }

    // Pattern C: Standalone image URLs ending with image extensions (plus optional query string)
    let urlPattern = #"(?i)https?:\/\/[^\s"'<>]+\.(?:png|jpg|jpeg|gif|webp|heic|bmp)(?:\?[^\s"'<>]*)?"#
    if let urlRegex = try? NSRegularExpression(pattern: urlPattern) {
        let ns = text as NSString
        let matches = urlRegex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        for m in matches {
            if let u = URL(string: ns.substring(with: m.range)) {
                urls.append(u)
            }
        }
    }

    // Deduplicate preserving order
    var seen = Set<String>()
    return urls.filter { seen.insert($0.absoluteString).inserted }
}
