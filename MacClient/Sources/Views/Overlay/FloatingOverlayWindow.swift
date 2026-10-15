import SwiftUI
import AppKit

/// Speaker model tracking active talkers for the floating game overlay.
public struct SpeakerInfo: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isMe: Bool
    public let talkingState: TalkingState
}

/// Represents an individual member of the active channel for the game overlay.
public struct ChannelMemberOverlayItem: Identifiable, Sendable {
    public let id: UInt32
    public let name: String
    public let isMe: Bool
    public let isTalking: Bool
    public let talkingState: TalkingState
    public let isMuted: Bool
    public let isDeafened: Bool
    public let isPrioritySpeaker: Bool

    public init(
        id: UInt32,
        name: String,
        isMe: Bool,
        isTalking: Bool,
        talkingState: TalkingState,
        isMuted: Bool,
        isDeafened: Bool,
        isPrioritySpeaker: Bool = false
    ) {
        self.id = id
        self.name = name
        self.isMe = isMe
        self.isTalking = isTalking
        self.talkingState = talkingState
        self.isMuted = isMuted
        self.isDeafened = isDeafened
        self.isPrioritySpeaker = isPrioritySpeaker
    }
}

/// Individual member row in the floating game overlay.
public struct ChannelMemberOverlayRow: View {
    public let member: ChannelMemberOverlayItem

    public init(member: ChannelMemberOverlayItem) {
        self.member = member
    }

    public var body: some View {
        HStack(spacing: 7) {
            // Live glowing dot indicator
            SpeakingOrbView(
                isTalking: member.isTalking,
                talkingState: member.talkingState,
                size: 8
            )

            // Member name
            Text(member.name)
                .font(.system(size: 11.5, weight: member.isTalking ? .semibold : .medium))
                .foregroundStyle(
                    member.isTalking
                        ? Color.primary
                        : (member.isMe ? Color.accentColor : Color.primary.opacity(0.85))
                )
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 4)

            // Audio status: Muted, Deafened (no sound), Priority
            HStack(spacing: 3) {
                if member.isPrioritySpeaker {
                    Image(systemName: "star.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(Color.yellow)
                        .help("Priority Speaker")
                }

                if member.isMuted {
                    Image(systemName: "mic.slash.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.red)
                        .help(member.isMe ? "Muted" : "User Muted")
                }

                if member.isDeafened {
                    Image(systemName: "headphones.slash")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.red)
                        .help(member.isMe ? "Deafened" : "User Deafened (No Sound)")
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3.5)
        .background(
            member.isTalking
                ? Color.green.opacity(0.14)
                : (member.isMe ? Color.accentColor.opacity(0.08) : Color.clear),
            in: RoundedRectangle(cornerRadius: 6)
        )
        .animation(.easeInOut(duration: 0.15), value: member.isTalking)
        .animation(.easeInOut(duration: 0.15), value: member.isMuted)
        .animation(.easeInOut(duration: 0.15), value: member.isDeafened)
    }
}

/// PreferenceKey to cleanly bubble up content size to the NSPanel without triggering AppKit Auto Layout loops.
struct OverlayContentSizeKey: PreferenceKey {
    static let defaultValue: CGSize = .zero
    static func reduce(value: inout CGSize, nextValue: () -> CGSize) {
        let next = nextValue()
        if next != .zero {
            value = next
        }
    }
}

/// Compact Liquid Glass "Who's Talking & Channel Members" overlay view for full-screen games.
public struct FloatingOverlayPillView: View {
    @Bindable public var store: MumbleStore
    @State private var isCollapsed: Bool = false

    public init(store: MumbleStore) {
        self.store = store
    }

    private var channelMembers: [ChannelMemberOverlayItem] {
        var items: [ChannelMemberOverlayItem] = []

        let mySessionId = store.mySessionId
        let myChannelId = store.myChannelId

        // 1. Current user
        let meUser = store.users.first(where: { $0.sessionId == mySessionId })
        let myName = meUser?.name ?? "You"
        let myItem = ChannelMemberOverlayItem(
            id: mySessionId ?? 0,
            name: "\(myName) (You)",
            isMe: true,
            isTalking: store.audioEngine.isTransmitting,
            talkingState: store.isWhispering ? .whisper : .talking,
            isMuted: store.isSelfMuted,
            isDeafened: store.isSelfDeafened,
            isPrioritySpeaker: meUser?.isPrioritySpeaker ?? false
        )
        items.append(myItem)

        // 2. Remote users in the same channel
        let others = store.users.filter { user in
            user.sessionId != mySessionId && (myChannelId == nil || user.channelId == myChannelId)
        }

        // Sort remote users: talking users first, then alphabetically
        let sortedOthers = others.sorted { a, b in
            if a.isTalking != b.isTalking {
                return a.isTalking && !b.isTalking
            }
            return a.name.localizedCaseInsensitiveCompare(b.name) == .orderedAscending
        }

        for u in sortedOthers {
            let isLocallyMuted = store.isUserLocallyMuted(sessionId: u.sessionId)
            let isMuted = u.isMuted || u.isSelfMuted || isLocallyMuted
            let isDeafened = u.isDeafened || u.isSelfDeafened

            items.append(ChannelMemberOverlayItem(
                id: u.sessionId,
                name: u.name,
                isMe: false,
                isTalking: u.isTalking,
                talkingState: u.talkingState,
                isMuted: isMuted,
                isDeafened: isDeafened,
                isPrioritySpeaker: u.isPrioritySpeaker
            ))
        }

        return items
    }

    private var activeSpeakers: [ChannelMemberOverlayItem] {
        channelMembers.filter { $0.isTalking }
    }

    private var channelName: String {
        if let ch = store.myChannel {
            return ch.name
        }
        return "Root"
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { _ in
                FloatingOverlayManager.shared.handleDrag()
            }
            .onEnded { _ in
                FloatingOverlayManager.shared.endDrag()
            }
    }

    private var dragHandleView: some View {
        ZStack {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.secondary.opacity(0.6))
            OverlayDragHandle()
        }
        .frame(width: 14, height: 18)
        .contentShape(Rectangle())
        .help("Drag to reposition overlay")
    }

    public var body: some View {
        mainContent
            .background(
                GeometryReader { geo in
                    Color.clear.preference(key: OverlayContentSizeKey.self, value: geo.size)
                }
            )
            .onPreferenceChange(OverlayContentSizeKey.self) { newSize in
                guard newSize.width > 0, newSize.height > 0 else { return }
                DispatchQueue.main.async {
                    FloatingOverlayManager.shared.updateSize(newSize)
                }
            }
            .contextMenu {
                if store.connectionStatus == .connected {
                    Text("#\(channelName)")
                        .font(.headline)
                    Text("\(channelMembers.count) users in channel")
                    Divider()
                    Button(store.isSelfMuted ? "Unmute Microphone" : "Mute Microphone") {
                        store.toggleSelfMute()
                    }
                    Button(store.isSelfDeafened ? "Undeafen Audio" : "Deafen Audio") {
                        store.toggleSelfDeaf()
                    }
                    Divider()
                    Button(isCollapsed ? "Expand Member List" : "Collapse Member List") {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            isCollapsed.toggle()
                        }
                    }
                    Divider()
                }
                Button("Reset Overlay Position") {
                    FloatingOverlayManager.shared.resetPosition()
                }
                Button("Hide Overlay") {
                    FloatingOverlayManager.shared.hide()
                }
            }
    }

    @ViewBuilder
    private var mainContent: some View {
        if store.connectionStatus != .connected {
            // Disconnected / Connecting pill
            HStack(spacing: 8) {
                dragHandleView

                Image(systemName: store.connectionStatus == .connecting ? "waveform.badge.magnifyingglass" : "waveform.slash")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 11))
                Text(store.connectionStatus == .connecting ? "Connecting..." : "Disconnected")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Spacer(minLength: 4)

                closeButton
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 8)
            .frame(width: 210)
            .glassEffect(.regular.interactive(), in: .capsule)
            .simultaneousGesture(dragGesture)
        } else if isCollapsed {
            // Collapsed compact pill
            HStack(spacing: 7) {
                dragHandleView

                HStack(spacing: 5) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(store.accentTint)
                        .font(.system(size: 10, weight: .bold))

                    Text("#\(channelName)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Text("(\(channelMembers.count))")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
                .simultaneousGesture(dragGesture)

                if let speaker = activeSpeakers.first {
                    HStack(spacing: 4) {
                        SpeakingOrbView(isTalking: true, talkingState: speaker.talkingState, size: 7)
                        Text(speaker.name)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.15), in: Capsule())
                }

                Spacer(minLength: 4)

                quickMuteButton
                quickDeafenButton

                Button(action: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                        isCollapsed = false
                    }
                }) {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Color.secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .help("Expand Member List")

                closeButton
            }
            .padding(.leading, 8)
            .padding(.trailing, 10)
            .padding(.vertical, 6)
            .frame(minWidth: 220, maxWidth: 300)
            .glassEffect(
                .regular.tint(!activeSpeakers.isEmpty ? Color.green.opacity(0.12) : nil).interactive(),
                in: .capsule
            )
        } else {
            // Expanded Channel Card showing all channel members with speaking dots & audio status
            VStack(alignment: .leading, spacing: 5) {
                // Header
                HStack(spacing: 6) {
                    dragHandleView

                    HStack(spacing: 5) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(store.accentTint)

                        Text("#\(channelName)")
                            .font(.system(size: 11, weight: .bold))
                            .lineLimit(1)

                        Text("(\(channelMembers.count))")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                    .simultaneousGesture(dragGesture)

                    Spacer(minLength: 4)

                    quickMuteButton
                    quickDeafenButton

                    Button(action: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            isCollapsed = true
                        }
                    }) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(Color.secondary)
                            .frame(width: 18, height: 18)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Collapse Overlay")

                    closeButton
                }
                .padding(.leading, 8)
                .padding(.trailing, 10)
                .padding(.top, 8)
                .padding(.bottom, 2)

                Divider()
                    .opacity(0.3)
                    .padding(.horizontal, 6)

                // Channel Members
                if channelMembers.count > 8 {
                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 2) {
                            ForEach(channelMembers) { member in
                                ChannelMemberOverlayRow(member: member)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(channelMembers) { member in
                            ChannelMemberOverlayRow(member: member)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 6)
                }
            }
            .frame(minWidth: 220, maxWidth: 260)
            .glassEffect(
                .regular.tint(!activeSpeakers.isEmpty ? Color.green.opacity(0.08) : nil).interactive(),
                in: RoundedRectangle(cornerRadius: 14)
            )
        }
    }

    private var quickMuteButton: some View {
        Button(action: {
            store.toggleSelfMute()
        }) {
            Image(systemName: store.isSelfMuted ? "mic.slash.fill" : "mic.fill")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(store.isSelfMuted ? Color.red : Color.secondary)
                .frame(width: 20, height: 20)
                .background(
                    store.isSelfMuted ? Color.red.opacity(0.18) : Color.secondary.opacity(0.1),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(store.isSelfMuted ? "Unmute Microphone" : "Mute Microphone")
    }

    private var quickDeafenButton: some View {
        Button(action: {
            store.toggleSelfDeaf()
        }) {
            Image(systemName: store.isSelfDeafened ? "headphones.slash" : "headphones")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(store.isSelfDeafened ? Color.red : Color.secondary)
                .frame(width: 20, height: 20)
                .background(
                    store.isSelfDeafened ? Color.red.opacity(0.18) : Color.secondary.opacity(0.1),
                    in: Circle()
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(store.isSelfDeafened ? "Undeafen Audio" : "Deafen Audio")
    }

    private var closeButton: some View {
        Button(action: {
            FloatingOverlayManager.shared.hide()
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.secondary)
                .frame(width: 18, height: 18)
                .background(Color.secondary.opacity(0.15), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Hide Overlay")
    }
}

/// An AppKit NSView that initiates native macOS window dragging on mouseDown.
public struct OverlayDragHandle: NSViewRepresentable {
    public init() {}

    public func makeNSView(context: Context) -> DragHandleNSView {
        DragHandleNSView()
    }

    public func updateNSView(_ nsView: DragHandleNSView, context: Context) {}
}

public final class DragHandleNSView: NSView {
    public override var mouseDownCanMoveWindow: Bool {
        return true
    }

    public override func resetCursorRects() {
        super.resetCursorRects()
        addCursorRect(bounds, cursor: .openHand)
    }

    public override func mouseDown(with event: NSEvent) {
        guard let window = window else { return }
        window.performDrag(with: event)
        FloatingOverlayManager.shared.savePosition(window.frame.origin)
    }
}

/// Custom hosting view enabling instant first-click interactions while running as a floating non-activating panel.
final class OverlayHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
}

/// Window controller managing the always-on-top floating game overlay panel.
@MainActor
public final class FloatingOverlayManager: ObservableObject {
    public static let shared = FloatingOverlayManager()

    public private(set) var panel: NSPanel?
    @Published public private(set) var isVisible: Bool = false

    private var initialMouseOffset: CGPoint? = nil
    private let userDefaultsXKey = "Swimble_Overlay_Position_X"
    private let userDefaultsYKey = "Swimble_Overlay_Position_Y"

    private init() {}

    public func toggle(store: MumbleStore) {
        if isVisible && panel?.isVisible == true {
            hide()
        } else {
            show(store: store)
        }
    }

    public func show(store: MumbleStore) {
        if panel == nil {
            let overlayView = FloatingOverlayPillView(store: store)
            let hosting = OverlayHostingView(rootView: overlayView)
            // CRITICAL: Disable NSHostingView's automatic window min/max size updates to prevent recursive AppKit constraint crashes
            hosting.sizingOptions = []

            let initialOrigin = loadInitialOrigin()

            let p = NSPanel(
                contentRect: NSRect(origin: initialOrigin, size: CGSize(width: 220, height: 80)),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .floating
            p.isFloatingPanel = true
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            p.hidesOnDeactivate = false
            p.becomesKeyOnlyIfNeeded = true
            p.isReleasedWhenClosed = false
            p.contentView = hosting
            self.panel = p
        }

        panel?.orderFrontRegardless()
        isVisible = true
    }

    public func hide() {
        panel?.orderOut(nil)
        isVisible = false
    }

    public func updateSize(_ newSize: CGSize) {
        guard let panel = panel else { return }
        let currentFrame = panel.frame
        let widthDiff = abs(currentFrame.width - newSize.width)
        let heightDiff = abs(currentFrame.height - newSize.height)

        if widthDiff > 0.5 || heightDiff > 0.5 {
            var newFrame = currentFrame
            // Preserve top-left origin so resizing doesn't cause erratic jumping
            newFrame.origin.y += (currentFrame.height - newSize.height)
            newFrame.size = newSize
            panel.setFrame(newFrame, display: true, animate: false)
        }
    }

    // MARK: - Dragging & Window Position Management

    public func handleDrag() {
        guard let panel = panel else { return }
        let currentMouse = NSEvent.mouseLocation

        if initialMouseOffset == nil {
            initialMouseOffset = CGPoint(
                x: panel.frame.origin.x - currentMouse.x,
                y: panel.frame.origin.y - currentMouse.y
            )
        }

        guard let offset = initialMouseOffset else { return }
        let newOrigin = CGPoint(
            x: currentMouse.x + offset.x,
            y: currentMouse.y + offset.y
        )
        panel.setFrameOrigin(newOrigin)
    }

    public func endDrag() {
        initialMouseOffset = nil
        if let panel = panel {
            savePosition(panel.frame.origin)
        }
    }

    public func savePosition(_ origin: CGPoint) {
        UserDefaults.standard.set(origin.x, forKey: userDefaultsXKey)
        UserDefaults.standard.set(origin.y, forKey: userDefaultsYKey)
    }

    public func resetPosition() {
        guard let panel = panel else { return }
        if let screen = panel.screen ?? NSScreen.main {
            let vf = screen.visibleFrame
            let newOrigin = CGPoint(x: vf.minX + 32, y: vf.maxY - panel.frame.height - 32)
            panel.setFrameOrigin(newOrigin)
            savePosition(newOrigin)
        }
    }

    private func loadInitialOrigin() -> CGPoint {
        if UserDefaults.standard.object(forKey: userDefaultsXKey) != nil,
           UserDefaults.standard.object(forKey: userDefaultsYKey) != nil {
            let x = UserDefaults.standard.double(forKey: userDefaultsXKey)
            let y = UserDefaults.standard.double(forKey: userDefaultsYKey)
            let candidate = CGPoint(x: x, y: y)
            return ensureVisibleOnScreen(candidate, size: CGSize(width: 220, height: 80))
        }

        // Default: Top-left of primary screen with comfortable margins
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            return CGPoint(x: vf.minX + 32, y: vf.maxY - 120)
        }
        return CGPoint(x: 100, y: 700)
    }

    private func ensureVisibleOnScreen(_ origin: CGPoint, size: CGSize) -> CGPoint {
        let testRect = NSRect(origin: origin, size: size)
        for screen in NSScreen.screens {
            if screen.visibleFrame.intersects(testRect) {
                return origin
            }
        }
        // Fall back to main screen top-left if candidate is off-screen
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            return CGPoint(x: vf.minX + 32, y: vf.maxY - size.height - 32)
        }
        return origin
    }
}
