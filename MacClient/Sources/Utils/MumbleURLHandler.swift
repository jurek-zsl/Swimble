import Foundation
import AppKit

/// Central coordinator for handling incoming `mumble://` URL requests.
/// Manages window tab routing, server connections, and channel navigation.
@MainActor
public final class MumbleURLHandler: ObservableObject {
    public static let shared = MumbleURLHandler()

    public private(set) var pendingLink: MumbleLinkInfo? = nil
    private var lastHandledURLString: String? = nil
    private var lastHandledTime: Date = .distantPast

    private init() {}

    /// Handles an incoming `mumble://` URL string.
    public func handle(string: String) {
        guard let linkInfo = MumbleURLParser.parse(string: string) else {
            print("[MumbleURLHandler] Failed to parse URL string: \(string)")
            return
        }
        dispatchLink(linkInfo)
    }

    /// Handles an incoming `mumble://` `URL`.
    public func handle(url: URL) {
        guard let linkInfo = MumbleURLParser.parse(url: url) else {
            print("[MumbleURLHandler] Failed to parse URL: \(url.absoluteString)")
            return
        }
        dispatchLink(linkInfo)
    }

    private func dispatchLink(_ linkInfo: MumbleLinkInfo) {
        let now = Date()
        let urlStr = linkInfo.originalURL.absoluteString
        if urlStr == lastHandledURLString && now.timeIntervalSince(lastHandledTime) < 1.0 {
            // Deduplicate rapid successive events
            return
        }
        lastHandledURLString = urlStr
        lastHandledTime = now

        print("[MumbleURLHandler] Dispatching mumble link: \(linkInfo.host):\(linkInfo.port), channel path: \(linkInfo.channelPath.joined(separator: "/"))")

        // Bring application to the front
        NSApp.activate(ignoringOtherApps: true)

        let activeStores = MumbleStore.activeStores

        // 1. Check if an active store is already connected to this server
        if let connectedStore = activeStores.first(where: {
            $0.connectionStatus == .connected &&
            $0.activeBookmark?.host.caseInsensitiveCompare(linkInfo.host) == .orderedSame &&
            $0.activeBookmark?.port == linkInfo.port
        }) {
            connectedStore.handleMumbleLink(linkInfo)
            return
        }

        // 2. Check if there is an active store that is currently disconnected
        if let disconnectedStore = activeStores.first(where: { $0.connectionStatus == .disconnected }) {
            disconnectedStore.activeModal = nil
            disconnectedStore.handleMumbleLink(linkInfo)
            return
        }

        // 3. If there are no stores yet (e.g. cold start launch), queue link
        if activeStores.isEmpty {
            self.pendingLink = linkInfo
            return
        }

        // 4. All existing stores are connected to OTHER servers:
        // Queue the link and open a new server tab
        self.pendingLink = linkInfo
        NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
    }

    /// Consumes and clears any pending cold-start or new-tab link.
    public func consumePendingLink() -> MumbleLinkInfo? {
        let link = self.pendingLink
        self.pendingLink = nil
        return link
    }
}
