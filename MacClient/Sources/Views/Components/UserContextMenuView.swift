import SwiftUI
import AppKit

/// Interactive volume slider view designed specifically for NSMenuItem custom views.
final class MenuVolumeSliderView: NSView {
    let sessionId: UInt32
    weak var store: MumbleStore?
    let slider: NSSlider
    let label: NSTextField
    let iconView: NSImageView
    let titleLabel: NSTextField

    init(sessionId: UInt32, initialVolume: Float, store: MumbleStore) {
        self.sessionId = sessionId
        self.store = store

        self.titleLabel = NSTextField(labelWithString: "Volume")
        self.slider = NSSlider(value: Double(initialVolume), minValue: 0.0, maxValue: 2.0, target: nil, action: nil)
        self.label = NSTextField(labelWithString: "\(Int(initialVolume * 100))%")
        self.iconView = NSImageView()

        super.init(frame: NSRect(x: 0, y: 0, width: 220, height: 44))

        titleLabel.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        titleLabel.textColor = .secondaryLabelColor
        titleLabel.frame = NSRect(x: 14, y: 24, width: 60, height: 16)

        label.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .right
        label.frame = NSRect(x: 156, y: 24, width: 50, height: 16)

        iconView.image = NSImage(systemSymbolName: "speaker.wave.2.fill", accessibilityDescription: "Volume")
        iconView.contentTintColor = .secondaryLabelColor
        iconView.frame = NSRect(x: 14, y: 4, width: 16, height: 16)

        slider.isContinuous = true
        slider.target = self
        slider.action = #selector(sliderMoved(_:))
        slider.frame = NSRect(x: 36, y: 2, width: 170, height: 20)

        addSubview(titleLabel)
        addSubview(label)
        addSubview(iconView)
        addSubview(slider)
    }

    @objc private func sliderMoved(_ sender: NSSlider) {
        let vol = Float(sender.doubleValue)
        label.stringValue = "\(Int(vol * 100))%"
        store?.setUserVolume(sessionId: sessionId, volume: vol)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
}

/// AppKit NSView that intercepts right-click events and displays a native NSMenu
/// featuring an interactive NSSlider for per-user volume adjustments.
final class UserContextMenuNSView: NSView {
    weak var store: MumbleStore?
    var user: UserInfo?
    var onPrivateMessage: (() -> Void)?
    var onKick: (() -> Void)?
    var onBan: (() -> Void)?
    var onComment: (() -> Void)?
    var onAvatar: (() -> Void)?
    var onPickAvatar: (() -> Void)?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let currentEvent = NSApp.currentEvent,
              currentEvent.type == .rightMouseDown ||
              (currentEvent.type == .leftMouseDown && currentEvent.modifierFlags.contains(.control)) else {
            return nil
        }
        return self
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        guard let store = store, let user = user else { return nil }
        return buildMenu(store: store, user: user)
    }

    private func buildMenu(store: MumbleStore, user: UserInfo) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let isMe = user.sessionId == store.mySessionId

        if !isMe {
            // Header
            let header = NSMenuItem(title: user.name, action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            // Information (User Stats)
            let infoItem = NSMenuItem(title: "Information", action: #selector(handleInformation), keyEquivalent: "")
            infoItem.target = self
            infoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
            menu.addItem(infoItem)

            menu.addItem(NSMenuItem.separator())

            if let comment = user.comment, !comment.isEmpty {
                let commentItem = NSMenuItem(title: "View Comment & Images...", action: #selector(handleComment), keyEquivalent: "")
                commentItem.target = self
                menu.addItem(commentItem)
            }

            if let tex = user.texture, !tex.isEmpty {
                let avatarItem = NSMenuItem(title: "View Full Avatar...", action: #selector(handleAvatar), keyEquivalent: "")
                avatarItem.target = self
                menu.addItem(avatarItem)
            }

            if (user.comment != nil && !user.comment!.isEmpty) || (user.texture != nil && !user.texture!.isEmpty) {
                menu.addItem(NSMenuItem.separator())
            }

            let pmItem = NSMenuItem(title: "Send Private Message...", action: #selector(handlePrivateMessage), keyEquivalent: "")
            pmItem.target = self
            menu.addItem(pmItem)

            let whisperItem = NSMenuItem(title: "Whisper to User", action: #selector(handleWhisper), keyEquivalent: "")
            whisperItem.target = self
            menu.addItem(whisperItem)

            menu.addItem(NSMenuItem.separator())

            let isMuted = store.isUserLocallyMuted(sessionId: user.sessionId)
            let localMuteItem = NSMenuItem(title: "Local Mute", action: #selector(handleToggleLocalMute), keyEquivalent: "")
            localMuteItem.target = self
            localMuteItem.state = isMuted ? .on : .off
            menu.addItem(localMuteItem)

            let isIgnored = store.isUserTextIgnored(sessionId: user.sessionId)
            let ignoreItem = NSMenuItem(title: "Ignore Text Messages", action: #selector(handleToggleIgnoreText), keyEquivalent: "")
            ignoreItem.target = self
            ignoreItem.state = isIgnored ? .on : .off
            menu.addItem(ignoreItem)

            menu.addItem(NSMenuItem.separator())

            // Live Volume Slider MenuItem
            let volumeItem = NSMenuItem()
            let sliderView = MenuVolumeSliderView(
                sessionId: user.sessionId,
                initialVolume: store.getUserVolume(sessionId: user.sessionId),
                store: store
            )
            volumeItem.view = sliderView
            menu.addItem(volumeItem)

            menu.addItem(NSMenuItem.separator())

            // Admin Submenu
            let adminMenu = NSMenu(title: "Admin Actions")
            let priorityItem = NSMenuItem(
                title: user.isPrioritySpeaker ? "Revoke Priority Speaker" : "Grant Priority Speaker",
                action: #selector(handleTogglePriority),
                keyEquivalent: ""
            )
            priorityItem.target = self
            adminMenu.addItem(priorityItem)

            let serverMuteItem = NSMenuItem(
                title: user.isMuted ? "Server Unmute" : "Server Mute",
                action: #selector(handleToggleServerMute),
                keyEquivalent: ""
            )
            serverMuteItem.target = self
            adminMenu.addItem(serverMuteItem)

            let serverDeafItem = NSMenuItem(
                title: user.isDeafened ? "Server Undeafen" : "Server Deafen",
                action: #selector(handleToggleServerDeaf),
                keyEquivalent: ""
            )
            serverDeafItem.target = self
            adminMenu.addItem(serverDeafItem)

            adminMenu.addItem(NSMenuItem.separator())

            let kickItem = NSMenuItem(title: "Kick User...", action: #selector(handleKick), keyEquivalent: "")
            kickItem.target = self
            adminMenu.addItem(kickItem)

            let banItem = NSMenuItem(title: "Ban User...", action: #selector(handleBan), keyEquivalent: "")
            banItem.target = self
            adminMenu.addItem(banItem)

            let adminItem = NSMenuItem(title: "Admin Actions", action: nil, keyEquivalent: "")
            adminItem.submenu = adminMenu
            menu.addItem(adminItem)
        } else {
            // Self context menu
            let header = NSMenuItem(title: "\(user.name) (You)", action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)

            let infoItem = NSMenuItem(title: "Information", action: #selector(handleInformation), keyEquivalent: "")
            infoItem.target = self
            infoItem.image = NSImage(systemSymbolName: "info.circle", accessibilityDescription: nil)
            menu.addItem(infoItem)

            menu.addItem(NSMenuItem.separator())

            let registerItem = NSMenuItem(title: "Register on Server", action: #selector(handleRegister), keyEquivalent: "")
            registerItem.target = self
            menu.addItem(registerItem)

            let commentItem = NSMenuItem(title: "Change Comment & Images...", action: #selector(handleChangeComment), keyEquivalent: "")
            commentItem.target = self
            menu.addItem(commentItem)

            let setAvatarItem = NSMenuItem(title: "Set Avatar Image...", action: #selector(handleSetAvatar), keyEquivalent: "")
            setAvatarItem.target = self
            menu.addItem(setAvatarItem)

            if let tex = user.texture, !tex.isEmpty {
                let removeAvatarItem = NSMenuItem(title: "Remove Avatar", action: #selector(handleRemoveAvatar), keyEquivalent: "")
                removeAvatarItem.target = self
                menu.addItem(removeAvatarItem)
            }
        }

        return menu
    }

    @objc private func handleInformation() {
        guard let user = user else { return }
        store?.requestUserStats(sessionId: user.sessionId)
    }

    @objc private func handleComment() {
        onComment?()
    }

    @objc private func handleAvatar() {
        onAvatar?()
    }

    @objc private func handlePrivateMessage() {
        onPrivateMessage?()
    }

    @objc private func handleWhisper() {
        guard let user = user else { return }
        let config = VoiceTargetConfig(
            id: 1,
            sessions: [user.sessionId],
            channelId: nil,
            group: nil,
            links: false,
            children: false
        )
        store?.setupVoiceTarget(config: config)
        store?.setWhispering(true, targetId: 1)
    }

    @objc private func handleToggleLocalMute() {
        guard let user = user else { return }
        let current = store?.isUserLocallyMuted(sessionId: user.sessionId) ?? false
        store?.setUserLocallyMuted(sessionId: user.sessionId, muted: !current)
    }

    @objc private func handleToggleIgnoreText() {
        guard let user = user else { return }
        store?.toggleIgnoreTextMessages(sessionId: user.sessionId)
    }

    @objc private func handleTogglePriority() {
        guard let user = user else { return }
        store?.setUserPrioritySpeaker(sessionId: user.sessionId, priority: !user.isPrioritySpeaker)
    }

    @objc private func handleToggleServerMute() {
        guard let user = user else { return }
        store?.setUserServerMuteDeaf(sessionId: user.sessionId, mute: !user.isMuted, deaf: user.isDeafened)
    }

    @objc private func handleToggleServerDeaf() {
        guard let user = user else { return }
        store?.setUserServerMuteDeaf(sessionId: user.sessionId, mute: user.isMuted, deaf: !user.isDeafened)
    }

    @objc private func handleKick() {
        onKick?()
    }

    @objc private func handleBan() {
        onBan?()
    }

    @objc private func handleRegister() {
        store?.registerUser()
    }

    @objc private func handleChangeComment() {
        store?.activeModal = .changeComment
    }

    @objc private func handleSetAvatar() {
        onPickAvatar?()
    }

    @objc private func handleRemoveAvatar() {
        store?.removeAvatar()
    }
}

/// SwiftUI wrapper presenting the custom native AppKit RMB menu.
struct UserContextMenuOverlay: NSViewRepresentable {
    let store: MumbleStore
    let user: UserInfo
    let onPrivateMessage: () -> Void
    let onKick: () -> Void
    let onBan: () -> Void
    let onComment: () -> Void
    let onAvatar: () -> Void
    let onPickAvatar: () -> Void

    func makeNSView(context: Context) -> UserContextMenuNSView {
        let view = UserContextMenuNSView()
        view.store = store
        view.user = user
        view.onPrivateMessage = onPrivateMessage
        view.onKick = onKick
        view.onBan = onBan
        view.onComment = onComment
        view.onAvatar = onAvatar
        view.onPickAvatar = onPickAvatar
        return view
    }

    func updateNSView(_ nsView: UserContextMenuNSView, context: Context) {
        nsView.store = store
        nsView.user = user
        nsView.onPrivateMessage = onPrivateMessage
        nsView.onKick = onKick
        nsView.onBan = onBan
        nsView.onComment = onComment
        nsView.onAvatar = onAvatar
        nsView.onPickAvatar = onPickAvatar
    }
}
