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

/// Compact Liquid Glass "Who's Talking & Channel Members" overlay view for full-screen games.
public struct FloatingOverlayPillView: View {
    @Bindable public var store: MumbleStore
    @Bindable private var settings: SettingsState = SettingsState.shared
    @State private var isCollapsed: Bool = false

    public init(store: MumbleStore) {
        self.store = store
    }

    private var overlayWidth: CGFloat {
        FloatingOverlayManager.targetWidth(isConnected: store.connectionStatus == .connected)
    }

    private var currentFpsText: String {
        let maxFps = NSScreen.main?.maximumFramesPerSecond ?? 60
        return "\(maxFps) Hz"
    }

    private var fpsBadgeView: some View {
        HStack(spacing: 3) {
            Text(currentFpsText)
                .font(.system(size: 9.5, weight: .bold))
                .monospacedDigit()
                .foregroundStyle(Color.swimbleHex(settings.overlayColorHex))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Color.black.opacity(0.35), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.swimbleHex(settings.overlayColorHex).opacity(0.35), lineWidth: 0.5)
        )
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: true)
        .layoutPriority(1)
        .help("Display Refresh Rate")
    }

    private var clockBadgeView: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(Date.now, style: .time)
                .font(.system(size: 9.5, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.primary.opacity(0.9))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2.5)
        .background(Color.secondary.opacity(0.12), in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5)
        )
        .lineLimit(1)
        .fixedSize(horizontal: true, vertical: true)
        .layoutPriority(1)
        .help("Current Time")
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

    private var dragHandleView: some View {
        Capsule()
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 3.5, height: 13)
            .frame(width: 14, height: 20)
            .contentShape(Rectangle())
            .help("Drag to reposition overlay")
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { _ in
                        FloatingOverlayManager.shared.handleDrag()
                    }
                    .onEnded { _ in
                        FloatingOverlayManager.shared.endDrag()
                    }
            )
    }

    public var body: some View {
        mainContent
            .onAppear {
                FloatingOverlayManager.shared.updateLayout(
                    isConnected: store.connectionStatus == .connected,
                    isCollapsed: isCollapsed,
                    memberCount: channelMembers.count,
                    animate: false
                )
            }
            .onChange(of: store.connectionStatus) { _, newStatus in
                FloatingOverlayManager.shared.updateLayout(
                    isConnected: newStatus == .connected,
                    isCollapsed: isCollapsed,
                    memberCount: channelMembers.count
                )
            }
            .onChange(of: channelMembers.count) { _, newCount in
                if !isCollapsed {
                    FloatingOverlayManager.shared.updateLayout(
                        isConnected: store.connectionStatus == .connected,
                        isCollapsed: false,
                        memberCount: newCount
                    )
                }
            }
            .onChange(of: settings.showFpsCounter) { _, _ in
                FloatingOverlayManager.shared.updateLayout(
                    isConnected: store.connectionStatus == .connected,
                    isCollapsed: isCollapsed,
                    memberCount: channelMembers.count
                )
            }
            .onChange(of: settings.showCurrentTime) { _, _ in
                FloatingOverlayManager.shared.updateLayout(
                    isConnected: store.connectionStatus == .connected,
                    isCollapsed: isCollapsed,
                    memberCount: channelMembers.count
                )
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
                        let nextCollapsed = !isCollapsed
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                            isCollapsed = nextCollapsed
                        }
                        FloatingOverlayManager.shared.updateLayout(
                            isConnected: store.connectionStatus == .connected,
                            isCollapsed: nextCollapsed,
                            memberCount: channelMembers.count
                        )
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
                    .fixedSize(horizontal: true, vertical: false)

                Spacer(minLength: 4)

                if settings.showFpsCounter {
                    fpsBadgeView
                }

                if settings.showCurrentTime {
                    clockBadgeView
                }

                closeButton
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .frame(width: overlayWidth, height: 40)
            .glassEffect(.regular.interactive(), in: .capsule)
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
        } else if isCollapsed {
            // Collapsed compact pill
            HStack(spacing: 7) {
                dragHandleView

                // Channel indicator & member count
                HStack(spacing: 5) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .foregroundStyle(store.accentTint)
                        .font(.system(size: 10, weight: .bold))

                    Text("#\(channelName)")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: activeSpeakers.isEmpty ? 110 : 75, alignment: .leading)

                    Text("\(channelMembers.count)")
                        .font(.system(size: 9.5, weight: .bold))
                        .foregroundStyle(Color.secondary.opacity(0.9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Color.secondary.opacity(0.15), in: Capsule())
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: true)
                }
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { _ in
                            FloatingOverlayManager.shared.handleDrag()
                        }
                        .onEnded { _ in
                            FloatingOverlayManager.shared.endDrag()
                        }
                )

                // Active speaker badge (if anyone is currently talking)
                if let speaker = activeSpeakers.first {
                    HStack(spacing: 5) {
                        SpeakingOrbView(isTalking: true, talkingState: speaker.talkingState, size: 7.5)
                        Text(speaker.name)
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(speaker.isMe ? Color.accentColor : Color.primary)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 80, alignment: .leading)
                    }
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(Color.green.opacity(0.18), in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.green.opacity(0.35), lineWidth: 0.5)
                    )
                    .fixedSize(horizontal: true, vertical: false)
                }

                Spacer(minLength: 4)

                if settings.showFpsCounter {
                    fpsBadgeView
                }

                if settings.showCurrentTime {
                    clockBadgeView
                }

                // Control buttons cluster
                HStack(spacing: 4) {
                    quickMuteButton
                    quickDeafenButton
                    expandCollapseButton
                    closeButton
                }
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.vertical, 5)
            .frame(width: overlayWidth, height: 40)
            .glassEffect(
                .regular.tint(!activeSpeakers.isEmpty ? Color.green.opacity(0.12) : nil).interactive(),
                in: .capsule
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
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
                            .truncationMode(.tail)
                            .frame(maxWidth: 130, alignment: .leading)

                        Text("\(channelMembers.count)")
                            .font(.system(size: 9.5, weight: .bold))
                            .foregroundStyle(Color.secondary.opacity(0.9))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1.5)
                            .background(Color.secondary.opacity(0.15), in: Capsule())
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: true)
                    }
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 1)
                            .onChanged { _ in
                                FloatingOverlayManager.shared.handleDrag()
                            }
                            .onEnded { _ in
                                FloatingOverlayManager.shared.endDrag()
                            }
                    )

                    Spacer(minLength: 4)

                    if settings.showFpsCounter {
                        fpsBadgeView
                    }

                    if settings.showCurrentTime {
                        clockBadgeView
                    }

                    HStack(spacing: 4) {
                        quickMuteButton
                        quickDeafenButton
                        expandCollapseButton
                        closeButton
                    }
                }
                .padding(.leading, 8)
                .padding(.trailing, 8)
                .padding(.top, 8)
                .padding(.bottom, 2)

                Divider()
                    .opacity(0.3)
                    .padding(.horizontal, 6)

                // Channel Members
                if channelMembers.count > 7 {
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
            .frame(width: overlayWidth)
            .glassEffect(
                .regular.tint(!activeSpeakers.isEmpty ? Color.green.opacity(0.08) : nil).interactive(),
                in: RoundedRectangle(cornerRadius: 14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.5)
            )
        }
    }

    private func controlButton(
        systemName: String,
        isActive: Bool = false,
        activeColor: Color = .red,
        helpText: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 9.5, weight: .bold))
                .foregroundStyle(
                    isActive
                        ? activeColor
                        : Color.secondary.opacity(0.85)
                )
                .frame(width: 22, height: 22)
                .background(
                    isActive
                        ? activeColor.opacity(0.2)
                        : Color.secondary.opacity(0.12),
                    in: Circle()
                )
                .overlay(
                    Circle()
                        .strokeBorder(
                            isActive
                                ? activeColor.opacity(0.4)
                                : Color.white.opacity(0.08),
                            lineWidth: 0.5
                        )
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(helpText)
    }

    private var quickMuteButton: some View {
        controlButton(
            systemName: store.isSelfMuted ? "mic.slash.fill" : "mic.fill",
            isActive: store.isSelfMuted,
            activeColor: .red,
            helpText: store.isSelfMuted ? "Unmute Microphone" : "Mute Microphone",
            action: { store.toggleSelfMute() }
        )
    }

    private var quickDeafenButton: some View {
        controlButton(
            systemName: store.isSelfDeafened ? "headphones.slash" : "headphones",
            isActive: store.isSelfDeafened,
            activeColor: .red,
            helpText: store.isSelfDeafened ? "Undeafen Audio" : "Deafen Audio",
            action: { store.toggleSelfDeaf() }
        )
    }

    private var expandCollapseButton: some View {
        controlButton(
            systemName: isCollapsed ? "chevron.down" : "chevron.up",
            isActive: false,
            helpText: isCollapsed ? "Expand Member List" : "Collapse Member List",
            action: {
                let nextCollapsed = !isCollapsed
                withAnimation(.spring(response: 0.28, dampingFraction: 0.8)) {
                    isCollapsed = nextCollapsed
                }
                FloatingOverlayManager.shared.updateLayout(
                    isConnected: store.connectionStatus == .connected,
                    isCollapsed: nextCollapsed,
                    memberCount: channelMembers.count
                )
            }
        )
    }

    private var closeButton: some View {
        controlButton(
            systemName: "xmark",
            isActive: false,
            helpText: "Hide Overlay",
            action: { FloatingOverlayManager.shared.hide() }
        )
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

    public static func targetWidth(isConnected: Bool) -> CGFloat {
        let settings = SettingsState.shared
        var badgeExtra: CGFloat = 0
        if settings.showFpsCounter {
            badgeExtra += 64
        }
        if settings.showCurrentTime {
            badgeExtra += 80
        }

        if !isConnected {
            return 220 + badgeExtra
        } else {
            return 340 + badgeExtra
        }
    }

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
            hosting.sizingOptions = []
            hosting.translatesAutoresizingMaskIntoConstraints = true
            hosting.autoresizingMask = [.width, .height]

            let isConnected = store.connectionStatus == .connected
            let initialW: CGFloat = Self.targetWidth(isConnected: isConnected)
            let initialH: CGFloat = 40
            let initialOrigin = loadInitialOrigin(width: initialW, height: initialH)

            let p = NSPanel(
                contentRect: NSRect(origin: initialOrigin, size: CGSize(width: initialW, height: initialH)),
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
        SettingsState.shared.overlayEnabled = true
    }

    public func hide() {
        panel?.orderOut(nil)
        isVisible = false
        SettingsState.shared.overlayEnabled = false
    }

    public func updateLayout(isConnected: Bool, isCollapsed: Bool, memberCount: Int, animate: Bool = true) {
        guard let panel = panel else { return }

        let targetWidth = Self.targetWidth(isConnected: isConnected)
        let targetHeight: CGFloat

        if !isConnected {
            targetHeight = 40
        } else if isCollapsed {
            targetHeight = 40
        } else {
            let rowHeight: CGFloat = 26
            let headerAndPadding: CGFloat = 58
            if memberCount > 7 {
                targetHeight = 270
            } else {
                targetHeight = max(84, headerAndPadding + CGFloat(memberCount) * rowHeight)
            }
        }

        let currentFrame = panel.frame
        let widthDiff = abs(currentFrame.width - targetWidth)
        let heightDiff = abs(currentFrame.height - targetHeight)

        if widthDiff >= 1.0 || heightDiff >= 1.0 {
            var newFrame = currentFrame
            if initialMouseOffset == nil {
                // Preserve top-left origin so resizing expands downwards naturally
                newFrame.origin.y += (currentFrame.height - targetHeight)

                if let screen = panel.screen ?? NSScreen.main {
                    let maxAllowedX = screen.visibleFrame.maxX - targetWidth - 10
                    if newFrame.origin.x > maxAllowedX {
                        newFrame.origin.x = maxAllowedX
                    }
                }
            }
            newFrame.size = CGSize(width: targetWidth, height: targetHeight)
            panel.setFrame(newFrame, display: true, animate: animate)
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

    public func applyPosition(preset: OverlayPositionPreset) {
        guard let panel = panel, let screen = panel.screen ?? NSScreen.main else { return }
        let vf = screen.visibleFrame
        let w = panel.frame.width > 0 ? panel.frame.width : Self.targetWidth(isConnected: true)
        let h = panel.frame.height > 0 ? panel.frame.height : 40

        let origin: CGPoint
        switch preset {
        case .topLeft:
            origin = CGPoint(x: vf.minX + 32, y: vf.maxY - h - 32)
        case .topRight:
            origin = CGPoint(x: vf.maxX - w - 32, y: vf.maxY - h - 32)
        case .bottomLeft:
            origin = CGPoint(x: vf.minX + 32, y: vf.minY + 32)
        case .bottomRight:
            origin = CGPoint(x: vf.maxX - w - 32, y: vf.minY + 32)
        case .custom:
            return
        }

        panel.setFrameOrigin(origin)
        savePosition(origin)
    }

    private func loadInitialOrigin(width: CGFloat? = nil, height: CGFloat = 40) -> CGPoint {
        let w = width ?? Self.targetWidth(isConnected: true)
        if UserDefaults.standard.object(forKey: userDefaultsXKey) != nil,
           UserDefaults.standard.object(forKey: userDefaultsYKey) != nil {
            let x = UserDefaults.standard.double(forKey: userDefaultsXKey)
            let y = UserDefaults.standard.double(forKey: userDefaultsYKey)
            let candidate = CGPoint(x: x, y: y)
            return ensureVisibleOnScreen(candidate, size: CGSize(width: w, height: height))
        }

        let preset = SettingsState.shared.overlayPositionPreset
        if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            switch preset {
            case .topLeft:
                return CGPoint(x: vf.minX + 32, y: vf.maxY - height - 32)
            case .topRight:
                return CGPoint(x: vf.maxX - w - 32, y: vf.maxY - height - 32)
            case .bottomLeft:
                return CGPoint(x: vf.minX + 32, y: vf.minY + 32)
            case .bottomRight:
                return CGPoint(x: vf.maxX - w - 32, y: vf.minY + 32)
            case .custom:
                break
            }
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

extension Color {
    public static func swimbleHex(_ hex: String) -> Color {
        var cleanHex = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if cleanHex.hasPrefix("#") {
            cleanHex.removeFirst()
        }
        guard cleanHex.count == 6, let intVal = UInt64(cleanHex, radix: 16) else {
            return .cyan
        }
        let r = Double((intVal >> 16) & 0xFF) / 255.0
        let g = Double((intVal >> 8) & 0xFF) / 255.0
        let b = Double(intVal & 0xFF) / 255.0
        return Color(red: r, green: g, blue: b)
    }

    public func toSwimbleHex() -> String {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else {
            return "#00E5FF"
        }
        let r = Int(components.redComponent * 255.0)
        let g = Int(components.greenComponent * 255.0)
        let b = Int(components.blueComponent * 255.0)
        return String(format: "#%02X%02X%02X", r, g, b)
    }
}
