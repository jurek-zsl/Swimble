import SwiftUI
import AppKit

/// Compact Liquid Glass "Who's Talking" overlay view for full-screen games.
public struct FloatingOverlayPillView: View {
    @Bindable public var store: MumbleStore

    public init(store: MumbleStore) {
        self.store = store
    }

    private var speakingUsers: [UserInfo] {
        store.users.filter { $0.isTalking }
    }

    public var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.circle.fill")
                .foregroundStyle(speakingUsers.isEmpty ? Color.secondary : Color.green)
                .font(.system(size: 14))

            if speakingUsers.isEmpty {
                Text(store.connectionStatus == .connected ? "Connected" : "Overlay")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(speakingUsers, id: \.sessionId) { user in
                    HStack(spacing: 5) {
                        SpeakingOrbView(isTalking: true, size: 8)
                        Text(user.name)
                            .font(.caption.bold())
                            .foregroundStyle(.primary)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect(.regular.interactive(), in: .capsule)
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
            let hosting = NSHostingView(rootView: overlayView)
            hosting.setFrameSize(hosting.fittingSize)

            let p = NSPanel(
                contentRect: NSRect(x: 100, y: 100, width: 220, height: 44),
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
