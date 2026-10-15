import SwiftUI
import AppKit

/// Speaker model tracking active talkers for the floating game overlay.
public struct SpeakerInfo: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let isMe: Bool
    public let talkingState: TalkingState
}

/// Compact Liquid Glass "Who's Talking" overlay view for full-screen games.
public struct FloatingOverlayPillView: View {
    @Bindable public var store: MumbleStore

    public init(store: MumbleStore) {
        self.store = store
    }

    private var activeSpeakers: [SpeakerInfo] {
        var list: [SpeakerInfo] = []
        // 1. Current user if speaking/transmitting
        if store.audioEngine.isTransmitting {
            let myName = store.users.first(where: { $0.sessionId == store.mySessionId })?.name ?? "You"
            list.append(SpeakerInfo(
                id: "me",
                name: "\(myName) (You)",
                isMe: true,
                talkingState: store.isWhispering ? .whisper : .talking
            ))
        }
        // 2. Other users currently talking
        let others = store.users.filter { $0.isTalking && $0.sessionId != store.mySessionId }
        for u in others {
            list.append(SpeakerInfo(
                id: "\(u.sessionId)",
                name: u.name,
                isMe: false,
                talkingState: u.talkingState
            ))
        }
        return list
    }

    private var channelName: String {
        if let ch = store.myChannel {
            return "#\(ch.name)"
        }
        return "#Root"
    }

    private var channelUsersCount: Int {
        guard let myChId = store.myChannelId else { return max(1, store.users.count) }
        let count = store.users.filter { $0.channelId == myChId }.count
        return max(1, count)
    }

    public var body: some View {
        HStack(spacing: 8) {
            if store.connectionStatus != .connected {
                Image(systemName: store.connectionStatus == .connecting ? "waveform.badge.magnifyingglass" : "waveform.slash")
                    .foregroundStyle(.secondary)
                    .font(.system(size: 13))
                Text(store.connectionStatus == .connecting ? "Connecting..." : "Disconnected")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            } else if !activeSpeakers.isEmpty {
                // When speakers are active: show speaking indicator + list of speakers
                Image(systemName: "waveform")
                    .foregroundStyle(Color.green)
                    .font(.system(size: 13, weight: .bold))

                ForEach(activeSpeakers) { speaker in
                    HStack(spacing: 5) {
                        SpeakingOrbView(isTalking: true, talkingState: speaker.talkingState, size: 8)
                        Text(speaker.name)
                            .font(.caption.bold())
                            .foregroundStyle(speaker.isMe ? Color.accentColor : Color.primary)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.12), in: Capsule())
                }
            } else {
                // Idle connected state: channel info, user count, and mute/deafen status
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .foregroundStyle(store.accentTint)
                    .font(.system(size: 12))

                Text(channelName)
                    .font(.caption.bold())
                    .foregroundStyle(.primary)

                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)

                Text("\(channelUsersCount) in channel")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                if store.isSelfMuted {
                    Button(action: {
                        store.toggleSelfMute()
                    }) {
                        Image(systemName: "mic.slash.fill")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.18), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Muted (Click to Unmute)")
                }

                if store.isSelfDeafened {
                    Button(action: {
                        store.toggleSelfDeaf()
                    }) {
                        Image(systemName: "headphones.slash")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.red)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 3)
                            .background(Color.red.opacity(0.18), in: Capsule())
                            .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Deafened (Click to Undeafen)")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.tint(!activeSpeakers.isEmpty ? Color.green.opacity(0.15) : nil).interactive(), in: .capsule)
        .animation(.spring(response: 0.28, dampingFraction: 0.75), value: activeSpeakers.map { $0.id })
        .animation(.easeInOut(duration: 0.2), value: store.isSelfMuted)
        .animation(.easeInOut(duration: 0.2), value: store.isSelfDeafened)
        .contextMenu {
            if store.connectionStatus == .connected {
                Text(channelName)
                    .font(.headline)
                Text("\(channelUsersCount) users in channel")
                Divider()
                Button(store.isSelfMuted ? "Unmute Microphone" : "Mute Microphone") {
                    store.toggleSelfMute()
                }
                Button(store.isSelfDeafened ? "Undeafen Audio" : "Deafen Audio") {
                    store.toggleSelfDeaf()
                }
                Divider()
            }
            Button("Hide Overlay") {
                FloatingOverlayManager.shared.hide()
            }
        }
    }
}

/// Auto-sizing hosting view that dynamically adjusts the NSPanel's frame to fit changing SwiftUI content.
final class AutoSizingOverlayHostingView<Content: View>: NSHostingView<Content> {
    override func layout() {
        super.layout()
        guard let window = self.window else { return }
        let fit = fittingSize
        if fit.width > 0 && fit.height > 0 {
            let current = window.frame.size
            if abs(current.width - fit.width) > 1 || abs(current.height - fit.height) > 1 {
                DispatchQueue.main.async { [weak window] in
                    guard let window = window else { return }
                    var newFrame = window.frame
                    newFrame.origin.y += (newFrame.size.height - fit.height)
                    newFrame.size = fit
                    window.setFrame(newFrame, display: true, animate: false)
                }
            }
        }
    }
}

/// Window controller managing the always-on-top floating game overlay panel.
@MainActor
public final class FloatingOverlayManager: ObservableObject {
    public static let shared = FloatingOverlayManager()

    private var panel: NSPanel?
    @Published public private(set) var isVisible: Bool = false

    private init() {}

    public func toggle(store: MumbleStore) {
        if isVisible {
            hide()
        } else {
            show(store: store)
        }
    }

    public func show(store: MumbleStore) {
        if panel == nil {
            let overlayView = FloatingOverlayPillView(store: store)
            let hosting = AutoSizingOverlayHostingView(rootView: overlayView)

            let p = NSPanel(
                contentRect: NSRect(x: 120, y: 120, width: 240, height: 40),
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            p.level = .floating
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.isMovableByWindowBackground = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
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
}
