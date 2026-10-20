import Foundation
import CryptoKit
import Observation
import SwiftUI

private final class WeakStore: @unchecked Sendable {
    weak var value: MumbleStore?
    init(_ value: MumbleStore) { self.value = value }
}

/// Rust retains its callback object. Keep the reference back to the window
/// weak so closing a window releases its engine, decoder state, and timers.
private final class StoreEventHandler: MumbleEventHandler, @unchecked Sendable {
    weak var store: MumbleStore?
    init(_ store: MumbleStore) { self.store = store }
    func onConnectionStatusChanged(status: ConnectionStatus) { store?.onConnectionStatusChanged(status: status) }
    func onServerIdentityChallenge(challenge: ServerIdentityChallenge) { store?.onServerIdentityChallenge(challenge: challenge) }
    func onChannelAclReceived(acl: ChannelAcl) { store?.onChannelAclReceived(acl: acl) }
    func onChannelsUpdated(channels: [ChannelInfo]) { store?.onChannelsUpdated(channels: channels) }
    func onUsersUpdated(users: [UserInfo]) { store?.onUsersUpdated(users: users) }
    func onUserTalkingChanged(sessionId: UInt32, isTalking: Bool, talkingState: TalkingState) { store?.onUserTalkingChanged(sessionId: sessionId, isTalking: isTalking, talkingState: talkingState) }
    func onChatMessage(message: ChatMessage) { store?.onChatMessage(message: message) }
    func onPingUpdated(tcpMs: Float, udpMs: Float, usingUdpTunnel: Bool) { store?.onPingUpdated(tcpMs: tcpMs, udpMs: udpMs, usingUdpTunnel: usingUdpTunnel) }
    func onServerConnectionInfoUpdated(info: ServerConnectionInfo) { store?.onServerConnectionInfoUpdated(info: info) }
    func onRegisteredUsersUpdated(users: [RegisteredUser]) { store?.onRegisteredUsersUpdated(users: users) }
    func onBanListUpdated(bans: [BanEntryInfo]) { store?.onBanListUpdated(bans: bans) }
    func onUserStatsReceived(stats: UserStatsInfo) { store?.onUserStatsReceived(stats: stats) }
}

/// Active modal sheet displayed in the application
public enum ActiveModal: String, Identifiable {
    case serverConnect
    case serverInfo
    case accessTokens
    case registeredUsers
    case banList
    case changeComment
    case audioStatistics
    case audioWizard
    case certificateWizard
    case ttsSettings
    case overlaySettings
    case userStats
    case openMumbleLink

    public var id: String { rawValue }
}


/// Main application state store managing Mumble server networking, channel hierarchies,
/// user speaking states, chat activity, and audio hardware synchronization.
@Observable
@MainActor
public final class MumbleStore: MumbleEventHandler, @unchecked Sendable {
    nonisolated private static let storeLock = NSLock()
    nonisolated(unsafe) private static var _activeStores: [WeakStore] = []
    nonisolated public static var activeStores: [MumbleStore] {
        storeLock.lock()
        defer { storeLock.unlock() }
        return _activeStores.compactMap(\.value)
    }
    nonisolated public static var shared: MumbleStore? {
        storeLock.lock()
        defer { storeLock.unlock() }
        return _activeStores.compactMap(\.value).last
    }

    public private(set) var client: MumbleClient!
    public private(set) var audioEngine: MacAudioEngine!
    public let recorder = AudioRecorder()
    public let globalPTT = GlobalPTT.shared

    // Connection & Networking State
    public var connectionStatus: ConnectionStatus = .disconnected
    public var tcpPingMs: Float = 0.0
    public var udpPingMs: Float = 0.0
    public var usingUdpTunnel: Bool = false
    public var isUserInitiatedDisconnect: Bool = false
    public var currentUserStats: UserStatsInfo? = nil
    public var serverIdentityChallenge: ServerIdentityChallenge?
    public var channelAcl: ChannelAcl?
    public var aclChannelId: UInt32?
    private var requestedPermissions: Set<UInt32> = []

    public func isListening(to id: UInt32) -> Bool { users.first { $0.sessionId == mySessionId }?.listeningChannels.contains(id) == true }
    public func displayName(_ user: UserInfo) -> String { ClientPreferences.shared.displayName(user) }
    // Channel & User Tree
    public var channels: [ChannelInfo] = []
    public var channelTree: [ChannelTreeNode] = []
    private var channelUserCounts: [UInt32: Int] = [:]
    public var previouslyLockedChannelIds: Set<UInt32> = []
    public var users: [UserInfo] = []
    public var selectedChannelId: UInt32? = nil
    public var mySessionId: UInt32? = nil
    public var pendingTargetChannelPath: [String]? = nil

    // Chat Activity Stream
    public var chatMessages: [ChatMessage] = [] {
        didSet {
            let requested = SettingsState.shared.maxChatBlockCount
            let limit = requested > 0 ? min(requested, 10000) : 10000
            if chatMessages.count > limit { chatMessages.removeFirst(chatMessages.count - limit) }
        }
    }
    public var unreadMessageCount = 0
    public var chatVisible = false
    public func markChatRead() {
        guard chatVisible, NSApp.isActive, GlobalPTT.shared.activeStore === self else { return }
        unreadMessageCount = 0; updateDockBadge()
    }
    private var reconnectAttempt = 0

    // Local Mute & Deafen
    public var isSelfMuted: Bool = false
    public var isSelfDeafened: Bool = false

    // Per-User Audio Settings (sessionId -> value)
    public var userVolumes: [UInt32: Float] = [:]
    public var userLocalMutes: [UInt32: Bool] = [:]

    // Bookmarks & Identity
    public var bookmarks: [ServerBookmark] = []
    public var activeBookmark: ServerBookmark? = nil
    public var serverPreferenceKey: String { activeBookmark.map { "[\($0.host.lowercased())]:\($0.port)" } ?? "" }
    public var lastUsedBookmark: ServerBookmark? {
        if let idStr = UserDefaults.standard.string(forKey: "Swimble_LastConnectedBookmarkId"),
           let uuid = UUID(uuidString: idStr),
           let bm = bookmarks.first(where: { $0.id == uuid }) {
            return bm
        }
        return nil
    }
    public private(set) var isIdentityReady = false
    private var identityTask: Task<Void, Never>?
    private var pendingIdentityConnection: UUID?
    public var identityError: String?
    public var clientIdentity: ClientIdentity!
    public var certFingerprint: String = ""

    // Server Ping Caching
    public var serverPingResults: [String: ServerPingInfo] = [:]
    public var serverPingFailed: [String: Bool] = [:]
    public var isPingingServers: Bool = false
    private var backgroundPingTimer: Timer? = nil

    // Server Connection Information
    public var connectionInfo: ServerConnectionInfo? = nil

    // Server ACL Access Tokens
    public var accessTokens: [String] = []

    // Server Registered Users & Ban List
    public var registeredUsers: [RegisteredUser] = []
    public var banList: [BanEntryInfo] = []

    // Whisper & Shout
    public var isWhispering: Bool = false
    public var whisperTargetConfig: VoiceTargetConfig? = nil

    // Ignored Users for Chat
    public var ignoredTextMessageUsers: Set<UInt32> = []

    // Active Modal Sheet
    public var activeModal: ActiveModal? = nil

    // User Settings & UI Preferences
    public var selectedSettingsTab: SettingsTab = .general
    public var accentColorName: String = UserDefaults.standard.string(forKey: "Swimble_AccentColor") ?? "Cyan" {
        didSet {
            UserDefaults.standard.set(accentColorName, forKey: "Swimble_AccentColor")
            self.accentTint = Self.colorFromName(accentColorName)
        }
    }
    public var accentTint: Color = .cyan

    public var autoReconnectOnLaunch: Bool {
        get { SettingsState.shared.autoConnectLastUsedServer }
        set { SettingsState.shared.autoConnectLastUsedServer = newValue; SettingsState.shared.saveToUserDefaults() }
    }

    public var myChannelId: UInt32? {
        guard let myId = mySessionId, let me = users.first(where: { $0.sessionId == myId }) else { return nil }
        return me.channelId
    }

    // System Event & Channel Move Tracking
    private var hasLoggedInitialJoin: Bool = false
    private var lastKnownMyChannelId: UInt32? = nil
    private var pendingUserMoves: [UInt32: UInt32] = [:]
    private var previousUserChannelMap: [UInt32: UInt32] = [:]
    private var previousUserNames: [UInt32: String] = [:]
    private var previousUserMuteMap: [UInt32: Bool] = [:]
    private var previousUserDeafMap: [UInt32: Bool] = [:]
    private var previousUserPriorityMap: [UInt32: Bool] = [:]

    public func channelName(for channelId: UInt32) -> String {
        if let ch = channels.first(where: { $0.id == channelId }) {
            return ch.name
        }
        if channelId == 0, let bm = activeBookmark {
            return bm.name
        }
        return "Root"
    }

    /// Returns the total number of users currently in this channel plus all recursive child subchannels.
    public func totalUsers(in channelId: UInt32) -> Int {
        channelUserCounts[channelId, default: 0]
    }

    public func logSystemMessage(_ text: String, icon: String = "info.circle.fill") {
        let sysMsg = ChatMessage(
            senderSession: 0,
            senderName: "System",
            channelId: self.selectedChannelId ?? self.myChannelId,
            recipientSession: nil,
            htmlBody: text,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000)
        )
        self.chatMessages.append(sysMsg)
        TTSEngine.shared.speakEvent(text)
    }

    private func checkInitialJoin(with usersList: [UserInfo]? = nil) {
        guard !hasLoggedInitialJoin, let myId = mySessionId else { return }
        let currentUsers = usersList ?? self.users
        guard let me = currentUsers.first(where: { $0.sessionId == myId }) else { return }
        guard !channels.isEmpty || activeBookmark != nil else { return }
        hasLoggedInitialJoin = true
        lastKnownMyChannelId = me.channelId
        let chName = channelName(for: me.channelId)
        logSystemMessage("You joined \(chName).", icon: "arrow.right.circle.fill")

        if let path = pendingTargetChannelPath, !path.isEmpty {
            if let targetCh = findChannel(byPath: path) {
                pendingTargetChannelPath = nil
                joinChannel(channelId: targetCh.id)
            }
        }
    }

    public var myChannel: ChannelInfo? {
        guard let chId = myChannelId else { return nil }
        return channels.first(where: { $0.id == chId })
    }

    public var isViewingCurrentChannel: Bool {
        guard let sel = selectedChannelId, let myCh = myChannelId else { return false }
        return sel == myCh
    }

    public static func colorFromName(_ name: String) -> Color {
        switch name {
        case "Cyan": return .cyan
        case "Emerald": return .green
        case "Sapphire": return .blue
        case "Amethyst": return .purple
        case "Amber": return .orange
        case "Ruby": return .red
        default: return .cyan
        }
    }

    public init() {
        self.clientIdentity = ClientIdentity(certPem: "", keyPem: "")
        self.certFingerprint = "Loading identity…"

        // 2. Initialize Rust MumbleClient with self as event handler
        let client = MumbleClient(handler: StoreEventHandler(self))
        self.client = client

        // 3. Initialize Audio Engine & Global PTT
        let audioEngine = MacAudioEngine(client: client)
        self.audioEngine = audioEngine
        audioEngine.onTransmissionChanged = { [weak self] transmitting in
            Task { @MainActor [weak self] in
                guard let self = self else { return }
                if let myId = self.mySessionId, let idx = self.users.firstIndex(where: { $0.sessionId == myId }) {
                    self.users[idx].isTalking = transmitting
                    self.users[idx].talkingState = transmitting ? (self.isWhispering ? .whisper : .talking) : .passive
                    self.updateTreeUser(self.users[idx])
                }
            }
        }
        // 4. Load saved bookmarks & access tokens
        loadBookmarks()
        loadAccessTokens()
        pingAllBookmarks()
        startBackgroundPingTimer()

        // 5. Initialize accent tint, apply saved settings, and auto-connect if enabled
        self.accentTint = Self.colorFromName(self.accentColorName)
        startIdleMonitor()

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            SettingsState.shared.apply(to: self)
        }

        identityTask = Task { [weak self] in
            do {
                let identity = try await CredentialRepository.shared.loadIdentity()
                guard let self else { return }
                self.clientIdentity = identity; self.certFingerprint = Self.computeFingerprint(pem: identity.certPem)
                self.isIdentityReady = true
                if self.pendingIdentityConnection == nil && !self.isUserInitiatedDisconnect && SettingsState.shared.autoConnectLastUsedServer, let last = self.lastUsedBookmark { self.connect(bookmark: last) }
            } catch {
                self?.identityError = error.localizedDescription
                self?.logSystemMessage("Client identity could not be loaded from Keychain: \(error.localizedDescription). Unlock Keychain and reopen Swimble.")
            }
        }

        Self.storeLock.lock()
        Self._activeStores.removeAll { $0.value == nil }
        Self._activeStores.append(WeakStore(self))
        Self.storeLock.unlock()
    }

    deinit {
        Self.storeLock.lock()
        Self._activeStores.removeAll(where: { $0.value == nil || $0.value === self })
        Self.storeLock.unlock()
    }

    public func performHaptic() {
        guard SettingsState.shared.hapticFeedbackEnabled else { return }
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
    }

    // MARK: - Server Connection Actions

    public func connect(bookmark: ServerBookmark, trustedFingerprint: String? = nil, isRetry: Bool = false) {
        guard isIdentityReady else {
            let request = UUID(); pendingIdentityConnection = request
            Task { [weak self] in
                await self?.identityTask?.value
                guard let self, self.isIdentityReady, self.pendingIdentityConnection == request else { return }
                self.pendingIdentityConnection = nil
                self.connect(bookmark: bookmark, trustedFingerprint: trustedFingerprint, isRetry: isRetry)
            }
            return
        }
        if !isRetry { reconnectAttempt = 0 }
        serverIdentityChallenge = nil
        requestedPermissions.removeAll()
        self.isUserInitiatedDisconnect = false
        self.reconnectTimer?.invalidate()
        self.reconnectTimer = nil
        self.activeBookmark = bookmark
        self.connectionStatus = .connecting

        // Trigger immediate reachability ping for fresh latency/status info
        Task { [weak self] in
            await self?.pingBookmark(bookmark)
        }

        // Resolve password from Keychain if present
        let password = bookmark.password ?? KeychainHelper.loadServerPassword(bookmarkId: bookmark.id)

        // Synchronize tokens to client before connecting
        client.setTokens(tokens: accessTokens)

        client.connect(
            host: bookmark.host,
            port: bookmark.port,
            username: bookmark.username,
            password: password,
            clientCertPem: clientIdentity.certPem,
            clientKeyPem: clientIdentity.keyPem,
            trustedFingerprint: trustedFingerprint ?? KeychainHelper.loadServerFingerprint(host: bookmark.host, port: bookmark.port)
        )


    }

    public func shutdown() {
        backgroundPingTimer?.invalidate(); backgroundPingTimer = nil
        idleTimer?.invalidate(); idleTimer = nil
        disconnect()
        if GlobalPTT.shared.activeStore === self {
            GlobalPTT.shared.focus(store: MumbleStore.activeStores.first { $0 !== self && $0.connectionStatus == .connected })
        }
    }

    public func disconnect() {
        pendingIdentityConnection = nil
        self.isUserInitiatedDisconnect = true
        self.reconnectTimer?.invalidate()
        self.reconnectTimer = nil
        if recorder.isRecording { recorder.stopRecording(); client.setRecordingState(recording: false) }
        let clearComment = SettingsState.shared.clearUserCommentsOnExit && connectionStatus == .connected
        audioEngine.stop()
        if clearComment { client.clearCommentAndDisconnect() } else { client.disconnect() }
        self.connectionStatus = .disconnected
        self.activeBookmark = nil
        self.channels = []
        self.channelTree = []
        self.users = []
        self.mySessionId = nil
        self.selectedChannelId = nil
        self.hasLoggedInitialJoin = false
        self.lastKnownMyChannelId = nil
        self.pendingTargetChannelPath = nil
        pingAllBookmarks()
    }

    // MARK: - User Stats

    public func requestUserStats(sessionId: UInt32, statsOnly: Bool = false) {
        client.requestUserStats(sessionId: sessionId, statsOnly: statsOnly)
    }

    public func joinChannel(channelId: UInt32) {
        performHaptic()
        client.joinChannel(channelId: channelId)
        self.selectedChannelId = channelId
    }

    // MARK: - Mumble URL Scheme Handling

    public func handleMumbleLink(_ linkInfo: MumbleLinkInfo) {
        if !linkInfo.channelPath.isEmpty {
            self.pendingTargetChannelPath = linkInfo.channelPath
        } else {
            self.pendingTargetChannelPath = nil
        }

        let isSameServer = (connectionStatus == .connected) &&
            (activeBookmark?.host.caseInsensitiveCompare(linkInfo.host) == .orderedSame) &&
            (activeBookmark?.port == linkInfo.port)

        if isSameServer {
            if let path = pendingTargetChannelPath, !path.isEmpty {
                navigateToChannel(path: path)
            }
            return
        }

        let fallbackUser = bookmarks.first?.username ?? "User"
        let bookmark: ServerBookmark
        if let existing = bookmarks.first(where: { $0.host.caseInsensitiveCompare(linkInfo.host) == .orderedSame && $0.port == linkInfo.port }) {
            var merged = existing
            if let u = linkInfo.username, !u.isEmpty {
                merged.username = u
            }
            if let p = linkInfo.password, !p.isEmpty {
                merged.password = p
            }
            bookmark = merged
        } else {
            let newBm = linkInfo.makeBookmark(fallbackUsername: fallbackUser)
            addBookmark(newBm)
            bookmark = newBm
        }

        connect(bookmark: bookmark)
    }

    public func navigateToChannel(path: [String]) {
        guard !path.isEmpty else { return }
        if let targetCh = findChannel(byPath: path) {
            pendingTargetChannelPath = nil
            joinChannel(channelId: targetCh.id)
            logSystemMessage("Joined channel \(targetCh.name).", icon: "arrow.right.circle.fill")
        }
    }

    public func findChannel(byPath components: [String]) -> ChannelInfo? {
        guard !components.isEmpty else { return nil }

        // Root channel in Mumble has parentId == nil or id == 0
        let root = channels.first(where: { $0.parentId == nil || $0.id == 0 })
        var searchComponents = components

        // If root channel matches first component, step past root
        if let root = root, let first = searchComponents.first, first.caseInsensitiveCompare(root.name) == .orderedSame {
            searchComponents.removeFirst()
        }

        if searchComponents.isEmpty {
            return root
        }

        return searchChannelSubtree(parentId: root?.id, remaining: searchComponents)
    }

    private func searchChannelSubtree(parentId: UInt32?, remaining: [String]) -> ChannelInfo? {
        guard let targetName = remaining.first else { return nil }

        let matchingChild = channels.first { ch in
            let parentMatches: Bool
            if let pid = parentId {
                parentMatches = (ch.parentId == pid)
            } else {
                parentMatches = (ch.parentId == nil || ch.parentId == 0)
            }
            return parentMatches && ch.name.caseInsensitiveCompare(targetName) == .orderedSame
        }

        if let child = matchingChild {
            let rest = Array(remaining.dropFirst())
            if rest.isEmpty {
                return child
            }
            return searchChannelSubtree(parentId: child.id, remaining: rest)
        }

        // Direct search fallback if hierarchy matching failed
        if remaining.count == 1 {
            return channels.first { $0.name.caseInsensitiveCompare(targetName) == .orderedSame }
        }

        return nil
    }

    public func sendChatMessage(channelId: UInt32?, message: String) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let targetId = channelId ?? selectedChannelId ?? 0
        client.sendChatMessage(channelId: targetId, message: message)

        // Append locally for immediate feedback
        let localMsg = ChatMessage(
            senderSession: mySessionId ?? 0,
            senderName: activeBookmark?.username ?? "Me",
            channelId: targetId,
            recipientSession: nil,
            htmlBody: message,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000)
        )
        self.chatMessages.append(localMsg)
    }

    public func setSelfMute(_ muted: Bool) {
        if muted != isSelfMuted { performHaptic() }
        self.isSelfMuted = muted
        let me = users.first { $0.sessionId == mySessionId }
        audioEngine.isMuted = muted || isSelfDeafened || me?.isMuted == true || me?.isSuppressed == true || me?.isDeafened == true || !canSpeak(in: me?.channelId ?? 0)
        client.setSelfMute(muted: muted)
        EventNotificationManager.shared.dispatch(
            eventName: "You muted/deafened yourself",
            detail: muted ? "You are now muted." : "You are now unmuted.",
            store: self
        )
    }

    public func setSelfDeaf(_ deafened: Bool) {
        if deafened != isSelfDeafened { performHaptic() }
        self.isSelfDeafened = deafened
        if deafened { self.isSelfMuted = true; audioEngine.isMuted = true }
        client.setSelfDeaf(deafened: deafened)
        EventNotificationManager.shared.dispatch(
            eventName: "You muted/deafened yourself",
            detail: deafened ? "You are now deafened." : "You are now undeafened.",
            store: self
        )
        // Mumble convention: deafening also mutes
        if deafened {
            self.isSelfMuted = true
            audioEngine.isMuted = true
        } else {
            audioEngine.isMuted = self.isSelfMuted
        }
    }

    public func toggleSelfMute() {
        recordUserActivity()
        setSelfMute(!isSelfMuted)
    }

    public func toggleSelfDeaf() {
        recordUserActivity()
        setSelfDeaf(!isSelfDeafened)
    }

    // MARK: - Per-User Volume & Muting

    public func getUserVolume(sessionId: UInt32) -> Float {
        if userLocalMutes[sessionId] == true {
            return 0.0
        }
        return userVolumes[sessionId] ?? 1.0
    }

    public func setUserVolume(sessionId: UInt32, volume: Float) {
        let clamped = max(0.0, min(2.0, volume))
        userVolumes[sessionId] = clamped
        if userLocalMutes[sessionId] != true {
            client.setUserLocalVolume(sessionId: sessionId, volumeMultiplier: clamped)
        }
    }

    public func isUserLocallyMuted(sessionId: UInt32) -> Bool {
        return userLocalMutes[sessionId] == true
    }

    public func setUserLocallyMuted(sessionId: UInt32, muted: Bool) {
        userLocalMutes[sessionId] = muted
        let effectiveVol: Float = muted ? 0.0 : (userVolumes[sessionId] ?? 1.0)
        client.setUserLocalVolume(sessionId: sessionId, volumeMultiplier: effectiveVol)
    }

    // MARK: - Channel & User Administration Actions

    public func createChannel(parentId: UInt32, name: String, description: String = "", position: Int32 = 0, isTemporary: Bool = false) {
        client.createChannel(parentId: parentId, name: name, description: description, position: position, isTemporary: isTemporary)
    }

    public func setChannelDescription(channelId: UInt32, description: String) {
        client.setChannelDescription(channelId: channelId, description: description)
    }

    public func removeChannel(channelId: UInt32) {
        client.removeChannel(channelId: channelId)
    }

    public func registerUser(sessionId: UInt32? = nil) {
        client.registerUser(sessionId: sessionId)
        logSystemMessage("Registered nickname with server certificate.", icon: "checkmark.seal.fill")
    }

    public func registerSelf() {
        registerUser(sessionId: nil)
    }

    public var isSelfRegistered: Bool {
        guard let myId = mySessionId, let me = users.first(where: { $0.sessionId == myId }) else { return false }
        return me.userId != nil && me.userId! > 0
    }

    public func setComment(comment: String) {
        client.setComment(comment: comment)
    }

    public func setAvatar(data: Data) {
        client.setAvatar(texture: data)
        logSystemMessage("Avatar updated.", icon: "person.crop.circle.badge.checkmark")
    }

    public func removeAvatar() {
        client.removeAvatar()
        logSystemMessage("Avatar removed.", icon: "person.crop.circle.badge.minus")
    }

    public func sendUserMessage(sessionId: UInt32, message: String) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        client.sendUserMessage(sessionId: sessionId, message: message)
        let localMsg = ChatMessage(
            senderSession: mySessionId ?? 0,
            senderName: activeBookmark?.username ?? "Me",
            channelId: nil,
            recipientSession: sessionId,
            htmlBody: message,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000)
        )
        self.chatMessages.append(localMsg)
    }

    public var isMyPrioritySpeaker: Bool {
        guard let myId = mySessionId, let me = users.first(where: { $0.sessionId == myId }) else { return false }
        return me.isPrioritySpeaker
    }

    public func toggleSelfPrioritySpeaker() {
        guard let myId = mySessionId else { return }
        let current = isMyPrioritySpeaker
        client.setUserPrioritySpeaker(sessionId: myId, priority: !current)
    }

    public func setUserPrioritySpeaker(sessionId: UInt32, priority: Bool) {
        client.setUserPrioritySpeaker(sessionId: sessionId, priority: priority)
    }

    // Audio Recording
    public var isRecordingAudio: Bool {
        recorder.isRecording
    }

    public var recordingDuration: TimeInterval {
        recorder.durationSeconds
    }

    public func toggleAudioRecording() {
        if recorder.isRecording {
            if let savedUrl = recorder.stopRecording() {
                client.setRecordingState(recording: false)
                EventNotificationManager.shared.dispatch(
                    eventName: "Recording state changed",
                    detail: "Finished recording: \(savedUrl.lastPathComponent) (saved to ~/Music/Swimble/)",
                    store: self
                )
            }
        } else {
            if recorder.startRecording(client: client) {
                client.setRecordingState(recording: true)
                EventNotificationManager.shared.dispatch(
                    eventName: "Recording state changed",
                    detail: "Started recording conversation to ~/Music/Swimble/",
                    store: self
                )
            }
        }
    }

    public func setUserServerMuteDeaf(sessionId: UInt32, mute: Bool, deaf: Bool) {
        client.setUserServerMuteDeaf(sessionId: sessionId, mute: mute, deaf: deaf)
    }

    public func moveUser(sessionId: UInt32, channelId: UInt32) {
        pendingUserMoves[sessionId] = channelId
        client.moveUser(sessionId: sessionId, channelId: channelId)
    }

    public func kickUser(sessionId: UInt32, reason: String? = nil) {
        client.kickUser(sessionId: sessionId, reason: reason)
    }

    public func banUser(sessionId: UInt32, reason: String? = nil) {
        client.banUser(sessionId: sessionId, reason: reason)
    }

    public func toggleIgnoreTextMessages(sessionId: UInt32) {
        if ignoredTextMessageUsers.contains(sessionId) {
            ignoredTextMessageUsers.remove(sessionId)
        } else {
            ignoredTextMessageUsers.insert(sessionId)
        }
    }

    public func isUserTextIgnored(sessionId: UInt32) -> Bool {
        ignoredTextMessageUsers.contains(sessionId)
    }

    public func setupVoiceTarget(config: VoiceTargetConfig) {
        self.whisperTargetConfig = config
        client.setVoiceTarget(config: config)
    }

    public func setWhispering(_ active: Bool, targetId: UInt8 = 1) {
        self.isWhispering = active
        self.audioEngine.activeVoiceTargetId = active ? targetId : nil
        self.client.setActiveVoiceTargetId(targetId: active ? targetId : 0)
    }

    public func updateClientIdentity(_ newIdentity: ClientIdentity) async throws {
        try await CredentialRepository.shared.replaceIdentity(newIdentity)
        self.clientIdentity = newIdentity
        self.certFingerprint = Self.computeFingerprint(pem: newIdentity.certPem)
        self.isIdentityReady = true; self.identityError = nil
    }

    // MARK: - Bookmarks Management

    public func addBookmark(_ bookmark: ServerBookmark) {
        guard migrateBookmarkPasswords() else { return }
        if let pwd = bookmark.password, !pwd.isEmpty,
           !KeychainHelper.saveServerPassword(bookmarkId: bookmark.id, password: pwd) {
            logSystemMessage("Could not save the server password to Keychain. Bookmark was not saved."); return
        }
        var saved = bookmark; saved.password = nil
        bookmarks.append(saved); saveBookmarks()
    }

    public func saveBookmark(_ bookmark: ServerBookmark) {
        guard migrateBookmarkPasswords() else { return }
        if let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            if let pwd = bookmark.password, !pwd.isEmpty {
                guard KeychainHelper.saveServerPassword(bookmarkId: bookmark.id, password: pwd) else {
                    logSystemMessage("Could not save the server password to Keychain."); return
                }
            } else { _ = KeychainHelper.deleteServerPassword(bookmarkId: bookmark.id) }
            var saved = bookmark; saved.password = nil
            bookmarks[idx] = saved; saveBookmarks()
        }
    }

    public func deleteBookmark(_ bookmark: ServerBookmark) {
        guard migrateBookmarkPasswords() else { return }
        bookmarks.removeAll { $0.id == bookmark.id }
        _ = KeychainHelper.deleteServerPassword(bookmarkId: bookmark.id)
        saveBookmarks()
    }

    public func toggleFavoriteBookmark(_ bookmark: ServerBookmark) {
        guard migrateBookmarkPasswords() else { return }
        if let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[idx].isFavorite.toggle()
            saveBookmarks()
        }
    }

    private func loadBookmarks() {
        if let data = UserDefaults.standard.data(forKey: "Swimble_Bookmarks") ?? UserDefaults.standard.data(forKey: "MumbleGlass_Bookmarks"),
           let saved = try? JSONDecoder().decode([ServerBookmark].self, from: data) {
            self.bookmarks = saved
            var migrated = true
            for bookmark in saved {
                if let password = bookmark.password, !password.isEmpty,
                   !KeychainHelper.saveServerPassword(bookmarkId: bookmark.id, password: password) { migrated = false }
            }
            if migrated {
                self.bookmarks = saved.map { var item = $0; item.password = nil; return item }
                saveBookmarks()
                UserDefaults.standard.removeObject(forKey: "MumbleGlass_Bookmarks")
            }
        } else {
            self.bookmarks = []
            saveBookmarks()
        }
    }

    private func migrateBookmarkPasswords() -> Bool {
        for bookmark in bookmarks {
            if let password = bookmark.password, !password.isEmpty,
               !KeychainHelper.saveServerPassword(bookmarkId: bookmark.id, password: password) {
                logSystemMessage("Unlock Keychain before editing saved servers. Existing credentials have been preserved.")
                return false
            }
        }
        bookmarks = bookmarks.map { var value = $0; value.password = nil; return value }
        return true
    }

    private func saveBookmarks() {
        guard migrateBookmarkPasswords() else { return }
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: "Swimble_Bookmarks")
        }
    }

    // MARK: - Server Ping Operations

    public static func cleanServerHost(_ host: String) -> String {
        let value = host.trimmingCharacters(in: .whitespacesAndNewlines)
        if let components = URLComponents(string: value.contains("://") ? value : "mumble://\(value)"),
           let hostname = components.host, !hostname.isEmpty {
            return hostname.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        }
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }

    public static func pingKey(host: String, port: UInt16) -> String {
        let cleanHost = cleanServerHost(host).lowercased()
        return "\(cleanHost):\(port)"
    }

    public func pingKey(for bookmark: ServerBookmark) -> String {
        Self.pingKey(host: bookmark.host, port: bookmark.port)
    }

    public func pingBookmark(_ bookmark: ServerBookmark) async {
        let cleanHost = Self.cleanServerHost(bookmark.host)
        guard !cleanHost.isEmpty else { return }
        let key = pingKey(for: bookmark)

        do {
            let info = try await pingMumbleServer(host: cleanHost, port: bookmark.port, timeoutMs: 3000)
            self.serverPingResults[key] = info
            self.serverPingFailed[key] = false
        } catch is CancellationError {
            // Task was cancelled (e.g. view disappeared or refresh triggered); do not mark as failed
        } catch {
            if !Task.isCancelled {
                self.serverPingResults[key] = nil
                self.serverPingFailed[key] = true
            }
        }
    }

    public func pingAllBookmarks() {
        guard !isPingingServers else { return }
        isPingingServers = true
        var list = self.bookmarks
        if let last = self.lastUsedBookmark, let idx = list.firstIndex(where: { $0.id == last.id }), idx > 0 {
            list.remove(at: idx)
            list.insert(last, at: 0)
        }
        Task { [weak self] in
            await withTaskGroup(of: (String, ServerPingInfo?).self) { group in
                for bookmark in list {
                    let cleanHost = Self.cleanServerHost(bookmark.host)
                    guard !cleanHost.isEmpty else { continue }
                    let port = bookmark.port
                    let key = Self.pingKey(host: cleanHost, port: port)
                    group.addTask {
                        do {
                            let info = try await pingMumbleServer(host: cleanHost, port: port, timeoutMs: 3000)
                            return (key, info)
                        } catch {
                            return (key, nil)
                        }
                    }
                }
                for await (key, info) in group {
                    await MainActor.run { [weak self] in
                        guard let self = self else { return }
                        if let info = info {
                            self.serverPingResults[key] = info
                            self.serverPingFailed[key] = false
                        } else {
                            self.serverPingResults[key] = nil
                            self.serverPingFailed[key] = true
                        }
                    }
                }
            }
            await MainActor.run { [weak self] in
                self?.isPingingServers = false
            }
        }
    }

    private func startBackgroundPingTimer() {
        self.backgroundPingTimer?.invalidate()
        self.backgroundPingTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self = self, self.connectionStatus == .disconnected, !self.bookmarks.isEmpty else { return }
                self.pingAllBookmarks()
            }
        }
    }

    // MARK: - Server Access Tokens Management

    public func addAccessToken(_ token: String) {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !accessTokens.contains(trimmed) else { return }
        accessTokens.append(trimmed)
        saveAccessTokens()
        client.setTokens(tokens: accessTokens)
    }

    public func removeAccessToken(_ token: String) {
        accessTokens.removeAll { $0 == token }
        saveAccessTokens()
        client.setTokens(tokens: accessTokens)
    }

    public func removeAccessToken(at index: Int) {
        guard index >= 0 && index < accessTokens.count else { return }
        accessTokens.remove(at: index)
        saveAccessTokens()
        client.setTokens(tokens: accessTokens)
    }

    private func loadAccessTokens() {
        self.accessTokens = UserDefaults.standard.stringArray(forKey: "Swimble_AccessTokens") ?? []
    }

    private func saveAccessTokens() {
        UserDefaults.standard.set(accessTokens, forKey: "Swimble_AccessTokens")
    }

    // MARK: - Server Registered Users Management

    public func requestRegisteredUsers() {
        guard connectionStatus == .connected else { return }
        client.requestRegisteredUsers()
    }

    public func removeRegisteredUser(userId: UInt32) {
        client.removeRegisteredUser(userId: userId)
        registeredUsers.removeAll { $0.userId == userId }
    }

    public func renameRegisteredUser(userId: UInt32, newName: String) {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        client.renameRegisteredUser(userId: userId, newName: trimmed)
    }

    // MARK: - Server Ban List Management

    public func requestBanList() {
        guard connectionStatus == .connected else { return }
        client.requestBanList()
    }

    public func addBan(ip: String, mask: UInt32 = 32, reason: String = "", durationHours: UInt32 = 24) {
        let trimmedIp = ip.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedIp.isEmpty else { return }
        let durationSeconds = durationHours * 3600
        client.addBan(ip: trimmedIp, mask: mask, reason: reason, durationSeconds: durationSeconds)
    }

    public func removeBan(ip: String, mask: UInt32) {
        client.removeBan(ip: ip, mask: mask)
        banList.removeAll { $0.ip == ip && $0.mask == mask }
    }

    // MARK: - Helpers

    public static func computeFingerprint(pem: String) -> String {
        let lines = pem.components(separatedBy: .newlines)
            .filter { !$0.contains("-----") && !$0.isEmpty }
            .joined()
        guard let data = Data(base64Encoded: lines) else {
            let rawData = Data(pem.utf8)
            let hash = Insecure.SHA1.hash(data: rawData)
            return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
        }
        let hash = Insecure.SHA1.hash(data: data)
        return hash.map { String(format: "%02X", $0) }.joined(separator: ":")
    }

    private func updateTreeUser(_ user: UserInfo) {
        func update(_ nodes: inout [ChannelTreeNode]) -> Bool {
            for i in nodes.indices {
                if nodes[i].id == user.channelId,
                   let j = nodes[i].users.firstIndex(where: { $0.sessionId == user.sessionId }) {
                    nodes[i].users[j] = user
                    return true
                }
                if update(&nodes[i].children) { return true }
            }
            return false
        }
        _ = update(&channelTree)
    }

    private func refreshChannelPermissions() {
        guard connectionStatus == .connected else { return }
        for channel in channels where channel.permissions == nil {
            if requestedPermissions.insert(channel.id).inserted {
                client.requestChannelPermissions(channelId: channel.id)
            }
        }
    }

    private func canSpeak(in channelId: UInt32) -> Bool {
        guard let permissions = channels.first(where: { $0.id == channelId })?.permissions else { return true }
        return permissions & 0x8 != 0
    }

    public func canEditChannelPrivileges(in channelId: UInt32) -> Bool {
        hasPermission(1, in: channelId) || hasPermission(1, in: 0)
    }

    public func hasPermission(_ permission: UInt32, in channelId: UInt32) -> Bool {
        guard let permissions = channels.first(where: { $0.id == channelId })?.permissions else { return false }
        return permissions & permission != 0
    }

    public func requestChannelAcl(channelId: UInt32) {
        channelAcl = nil
        aclChannelId = channelId
        client.requestChannelAcl(channelId: channelId)
        client.requestRegisteredUsers()
    }

    nonisolated public func onChannelAclReceived(acl: ChannelAcl) {
        Task { @MainActor [weak self] in
            guard let self, self.aclChannelId == acl.channelId else { return }
            self.channelAcl = acl
        }
    }

    nonisolated public func onServerIdentityChallenge(challenge: ServerIdentityChallenge) {
        Task { @MainActor [weak self] in
            guard let self, let bookmark = self.activeBookmark,
                  bookmark.host == challenge.host, bookmark.port == challenge.port else { return }
            self.reconnectTimer?.invalidate()
            self.serverIdentityChallenge = challenge
        }
    }

    public func acceptServerIdentity(remember: Bool) {
        guard let challenge = serverIdentityChallenge, let bookmark = activeBookmark,
              challenge.host == bookmark.host, challenge.port == bookmark.port else { return }
        if remember && !KeychainHelper.saveServerFingerprint(host: challenge.host, port: challenge.port, fingerprint: challenge.fingerprint) {
            logSystemMessage("The server certificate could not be saved to Keychain. Connection remains blocked.")
            return
        }
        connect(bookmark: bookmark, trustedFingerprint: challenge.fingerprint)
    }

    public func rejectServerIdentity() {
        serverIdentityChallenge = nil
        disconnect()
    }

    public func rebuildTree() {
        self.channelTree = ChannelTreeNode.buildTree(
            channels: self.channels,
            users: self.users,
            userSort: SettingsState.shared.userSort,
            filterHidesEmpty: SettingsState.shared.filterHidesEmptyChannels
        )
        var counts: [UInt32: Int] = [:]
        func count(_ node: ChannelTreeNode) -> Int {
            let total = node.users.count + node.children.reduce(0) { $0 + count($1) }
            counts[node.id] = total
            return total
        }
        for node in channelTree { _ = count(node) }
        channelUserCounts = counts
    }

    public func rebuildChannelTree() {
        rebuildTree()
    }

    // MARK: - Auto-Reconnect & Idle Action Monitoring

    private var reconnectTimer: Timer?
    public var lastActivityDate: Date = Date()
    private var idleTimer: Timer?
    private var idleActionTriggered: Bool = false
    private var preIdleMuted: Bool = false
    private var preIdleDeafened: Bool = false

    public func recordUserActivity() {
        lastActivityDate = Date()
        if idleActionTriggered && SettingsState.shared.undoIdleActionOnActivity {
            if isSelfMuted != preIdleMuted {
                setSelfMute(preIdleMuted)
            }
            if isSelfDeafened != preIdleDeafened {
                setSelfDeaf(preIdleDeafened)
            }
            idleActionTriggered = false
        }
    }

    public func startIdleMonitor() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.checkIdleTimeout()
            }
        }
    }

    private func checkIdleTimeout() {
        guard connectionStatus == .connected else { return }
        let timeoutMinutes = SettingsState.shared.idleActionTimeoutMinutes
        guard timeoutMinutes > 0 else { return }
        let idleSeconds = Date().timeIntervalSince(lastActivityDate)

        if idleSeconds >= Double(timeoutMinutes * 60) && !idleActionTriggered {
            idleActionTriggered = true
            preIdleMuted = isSelfMuted
            preIdleDeafened = isSelfDeafened

            switch SettingsState.shared.idleActionType {
            case .muteSelf:
                setSelfMute(true)
                logSystemMessage("Auto-muted due to inactivity (\(timeoutMinutes) minutes).", icon: "mic.slash.fill")
            case .deafenSelf:
                setSelfDeaf(true)
                logSystemMessage("Auto-deafened due to inactivity (\(timeoutMinutes) minutes).", icon: "headphones.slash")
            case .setAfk:
                setSelfMute(true)
                logSystemMessage("Set AFK due to inactivity (\(timeoutMinutes) minutes).", icon: "moon.fill")
            case .doNothing:
                break
            }
        }
    }

    public func scheduleAutoReconnect() {
        guard !isUserInitiatedDisconnect, let bm = activeBookmark else { return }
        reconnectTimer?.invalidate()
        guard client.reconnectAllowed() else { return }
        reconnectAttempt += 1
        let delay = min(60.0, pow(2.0, Double(min(reconnectAttempt, 6)))) + Double.random(in: 0...1)
        logSystemMessage("Connection lost. Reconnecting in \(Int(delay)) seconds (attempt \(reconnectAttempt))…", icon: "arrow.clockwise")
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, !self.isUserInitiatedDisconnect, (self.connectionStatus == .disconnected || self.connectionStatus == .failed) else { return }
                self.connect(bookmark: bm, isRetry: true)
            }
        }
    }

    public func updateDockBadge() {
        if SettingsState.shared.includeUnreadCountInTaskbar {
            let count = MumbleStore.activeStores.reduce(0) { $0 + $1.unreadMessageCount }
            NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    // MARK: - UniFFI Event Handler Callbacks

    nonisolated public func onConnectionStatusChanged(status: ConnectionStatus) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            guard self.client.getConnectionStatus() == status else { return }
            let wasConnected = self.connectionStatus == .connected
            self.connectionStatus = status
            if status == .connected {
                self.reconnectAttempt = 0
                if let bookmark = self.activeBookmark {
                    UserDefaults.standard.set(bookmark.id.uuidString, forKey: "Swimble_LastConnectedBookmarkId")
                }
                do { try self.audioEngine.start() } catch {
                    self.logSystemMessage("Audio could not start: \(error.localizedDescription)")
                }
                self.mySessionId = self.client.getMySession()
                self.refreshChannelPermissions()
                if let me = self.users.first(where: { $0.sessionId == self.mySessionId }) {
                    self.audioEngine.isMuted = me.isSelfMuted || me.isMuted || me.isSuppressed || me.isDeafened || me.isSelfDeafened || !self.canSpeak(in: me.channelId)
                }
                self.client.setTokens(tokens: self.accessTokens)
                EventNotificationManager.shared.dispatch(
                    eventName: "Connected",
                    detail: "Connected to \(self.activeBookmark?.name ?? "Server")",
                    store: self
                )
            } else if status == .disconnected || status == .failed {
                self.recorder.stopRecording()
                self.audioEngine.stop()
                self.registeredUsers = []
                self.banList = []
                self.previouslyLockedChannelIds.removeAll()
                EventNotificationManager.shared.dispatch(
                    eventName: "Disconnected",
                    detail: "Disconnected from server",
                    store: self
                )
                if SettingsState.shared.clearChatWindowOnExit {
                    self.chatMessages.removeAll()
                }
                let reason = self.client.disconnectReason()
                if !reason.isEmpty { self.logSystemMessage(reason) }
                if (wasConnected || self.reconnectAttempt > 0) && self.client.reconnectAllowed() && self.serverIdentityChallenge == nil && !self.isUserInitiatedDisconnect && SettingsState.shared.reconnectAutomatically && self.activeBookmark != nil {
                    self.scheduleAutoReconnect()
                }
            }
        }
    }

    nonisolated public func onChannelsUpdated(channels: [ChannelInfo]) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            for ch in channels {
                if !ch.canEnter {
                    self.previouslyLockedChannelIds.insert(ch.id)
                }
            }
            self.channels = channels
            self.refreshChannelPermissions()
            if let me = self.users.first(where: { $0.sessionId == self.mySessionId }) {
                self.audioEngine.isMuted = me.isSelfMuted || me.isMuted || me.isSuppressed || me.isDeafened || me.isSelfDeafened || !self.canSpeak(in: me.channelId)
            }
            if self.selectedChannelId == nil, let first = channels.first {
                self.selectedChannelId = first.id
            }
            self.rebuildTree()
            self.checkInitialJoin()
            if let path = self.pendingTargetChannelPath, !path.isEmpty {
                if let targetCh = self.findChannel(byPath: path) {
                    self.pendingTargetChannelPath = nil
                    self.joinChannel(channelId: targetCh.id)
                }
            }
        }
    }

    nonisolated public func onUsersUpdated(users: [UserInfo]) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let oldSessions = Set(self.users.map { $0.sessionId })
            let newSessions = Set(users.map { $0.sessionId })
            let myId = self.mySessionId ?? 0

            // 1. Initial join tracking
            if !self.hasLoggedInitialJoin {
                self.checkInitialJoin(with: users)
            } else if let me = users.first(where: { $0.sessionId == myId }) {
                if let lastCh = self.lastKnownMyChannelId, lastCh != me.channelId {
                    self.lastKnownMyChannelId = me.channelId
                    let chName = self.channelName(for: me.channelId)
                    self.logSystemMessage("You joined \(chName).", icon: "arrow.right.circle.fill")
                }
            }

            // 2. User connect / disconnect events
            if !self.users.isEmpty {
                let joined = newSessions.subtracting(oldSessions)
                let left = oldSessions.subtracting(newSessions)

                for sid in joined where sid != myId {
                    if let u = users.first(where: { $0.sessionId == sid }) {
                        EventNotificationManager.shared.dispatch(
                            eventName: "User joined channel",
                            detail: "\(u.name) joined the server.",
                            store: self
                        )
                    }
                }

                for sid in left where sid != myId {
                    EventNotificationManager.shared.dispatch(
                        eventName: "User left channel",
                        detail: "A user left the server.",
                        store: self
                    )
                }
            }

            // 3. User channel moves
            for u in users where u.sessionId != myId {
                if let prevChannelId = self.previousUserChannelMap[u.sessionId], prevChannelId != u.channelId {
                    let targetChName = self.channelName(for: u.channelId)
                    // Check if WE moved this user (handled by rust-core event log)
                    if let pendingTarget = self.pendingUserMoves[u.sessionId], pendingTarget == u.channelId {
                        self.pendingUserMoves.removeValue(forKey: u.sessionId)
                    } else if u.channelId == self.myChannelId {
                        EventNotificationManager.shared.dispatch(
                            eventName: "User joined channel",
                            detail: "\(u.name) joined the channel.",
                            store: self
                        )
                    } else if prevChannelId == self.myChannelId {
                        EventNotificationManager.shared.dispatch(
                            eventName: "User moved (between other channels)",
                            detail: "\(u.name) moved to \(targetChName).",
                            store: self
                        )
                    }
                }
            }

            // 4. User mute & deafen state changes
            if self.hasLoggedInitialJoin {
                for u in users {
                    let isMuted = u.isSelfMuted || u.isMuted
                    let isDeafened = u.isSelfDeafened || u.isDeafened
                    let subject = (u.sessionId == myId) ? "You are" : "\(u.name) is"

                    if let prevMuted = self.previousUserMuteMap[u.sessionId] {
                        if !prevMuted && isMuted {
                            if u.sessionId == myId {
                                if u.isMuted && !u.isSelfMuted {
                                    EventNotificationManager.shared.dispatch(
                                        eventName: "You were muted/deafened (by admin)",
                                        detail: "You were muted by an administrator.",
                                        store: self
                                    )
                                }
                            } else {
                                self.logSystemMessage("\(subject) now muted.", icon: "mic.slash.fill")
                            }
                        } else if prevMuted && !isMuted {
                            if u.sessionId != myId {
                                self.logSystemMessage("\(subject) now unmuted.", icon: "mic.fill")
                            }
                        }
                    }

                    if let prevDeaf = self.previousUserDeafMap[u.sessionId] {
                        if !prevDeaf && isDeafened {
                            if u.sessionId != myId {
                                self.logSystemMessage("\(subject) now deafened.", icon: "speaker.slash.fill")
                            }
                        } else if prevDeaf && !isDeafened {
                            if u.sessionId != myId {
                                self.logSystemMessage("\(subject) now undeafened.", icon: "speaker.wave.2.fill")
                            }
                        }
                    }

                    if let prevPriority = self.previousUserPriorityMap[u.sessionId] {
                        if !prevPriority && u.isPrioritySpeaker {
                            self.logSystemMessage("\(subject) now a Priority Speaker.", icon: "star.fill")
                            if u.sessionId == myId {
                                SoundManager.shared.playPrioritySpeaker(isActive: true)
                            }
                        } else if prevPriority && !u.isPrioritySpeaker {
                            self.logSystemMessage("\(subject) no longer a Priority Speaker.", icon: "star.slash")
                            if u.sessionId == myId {
                                SoundManager.shared.playPrioritySpeaker(isActive: false)
                            }
                        }
                    }
                }
            }

            // Update cache maps
            var newChannelMap: [UInt32: UInt32] = [:]
            var newNameMap: [UInt32: String] = [:]
            var newMuteMap: [UInt32: Bool] = [:]
            var newDeafMap: [UInt32: Bool] = [:]
            var newPriorityMap: [UInt32: Bool] = [:]
            for u in users {
                newChannelMap[u.sessionId] = u.channelId
                newNameMap[u.sessionId] = u.name
                newMuteMap[u.sessionId] = u.isSelfMuted || u.isMuted
                newDeafMap[u.sessionId] = u.isSelfDeafened || u.isDeafened
                newPriorityMap[u.sessionId] = u.isPrioritySpeaker
            }
            self.previousUserChannelMap = newChannelMap
            self.previousUserNames = newNameMap
            self.previousUserMuteMap = newMuteMap
            self.previousUserDeafMap = newDeafMap
            self.previousUserPriorityMap = newPriorityMap

            self.users = users
            if let me = users.first(where: { $0.sessionId == myId }) {
                self.isSelfMuted = me.isSelfMuted
                self.isSelfDeafened = me.isSelfDeafened
                self.audioEngine.isMuted = me.isSelfMuted || me.isMuted || me.isSuppressed || me.isDeafened || me.isSelfDeafened
                    || !self.canSpeak(in: me.channelId)
            }
            self.rebuildTree()
        }
    }

    nonisolated public func onUserTalkingChanged(sessionId: UInt32, isTalking: Bool, talkingState: TalkingState) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if let idx = self.users.firstIndex(where: { $0.sessionId == sessionId }) {
                let wasWhispering = self.users[idx].talkingState == .whisper
                self.users[idx].isTalking = isTalking
                self.users[idx].talkingState = talkingState
                self.updateTreeUser(self.users[idx])

                if isTalking && talkingState == .whisper && !wasWhispering && sessionId != self.mySessionId {
                    SoundManager.shared.playWhisper()
                }
            }
        }
    }

    nonisolated public func onChatMessage(message: ChatMessage) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            if self.ignoredTextMessageUsers.contains(message.senderSession) { return }
            if message.senderSession == self.mySessionId {
                if let last = self.chatMessages.last,
                   last.senderSession == message.senderSession && last.htmlBody == message.htmlBody {
                    return
                }
            }
            self.chatMessages.append(message)
            if message.senderSession != 0 && message.senderSession != self.mySessionId {
                if self.chatVisible && NSApp.isActive && GlobalPTT.shared.activeStore === self { self.unreadMessageCount = 0 }
                else { self.unreadMessageCount += 1 }
            }

            let isPermissionDenied = message.senderSession == 0 && message.htmlBody.contains("Permission denied")
            let isPrivate = message.channelId == nil && message.senderSession != 0

            if isPermissionDenied {
                EventNotificationManager.shared.dispatch(
                    eventName: "Permission denied",
                    detail: cleanChatMessageText(from: message.htmlBody),
                    store: self
                )
            } else if message.senderSession != self.mySessionId && message.senderSession != 0 {
                let clean = cleanChatMessageText(from: message.htmlBody)
                EventNotificationManager.shared.dispatch(
                    eventName: isPrivate ? "Private text message received" : "Text message received",
                    detail: "\(message.senderName): \(clean)",
                    store: self,
                    ttsOverride: "\(message.senderName) says: \(clean)"
                )
            }

            // Cap chatMessages at maxChatBlockCount
            let maxBlocks = SettingsState.shared.maxChatBlockCount
            if maxBlocks > 0 && self.chatMessages.count > maxBlocks {
                self.chatMessages.removeFirst(self.chatMessages.count - maxBlocks)
            }

            self.updateDockBadge()
        }
    }

    nonisolated public func onPingUpdated(tcpMs: Float, udpMs: Float, usingUdpTunnel: Bool) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.tcpPingMs = tcpMs
            self.udpPingMs = udpMs
            self.usingUdpTunnel = usingUdpTunnel
        }
    }

    nonisolated public func onServerConnectionInfoUpdated(info: ServerConnectionInfo) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.connectionInfo = info
            let trimmed = info.welcomeText.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                let alreadyHasWelcome = self.chatMessages.contains { $0.senderSession == 0 && $0.senderName == "Server" && $0.htmlBody.trimmingCharacters(in: .whitespacesAndNewlines) == trimmed }
                if !alreadyHasWelcome {
                    let welcomeMsg = ChatMessage(
                        senderSession: 0,
                        senderName: "Server",
                        channelId: nil,
                        recipientSession: nil,
                        htmlBody: trimmed,
                        timestamp: UInt64(Date().timeIntervalSince1970 * 1000)
                    )
                    self.chatMessages.append(welcomeMsg)
                }
            }
        }
    }

    nonisolated public func onRegisteredUsersUpdated(users: [RegisteredUser]) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.registeredUsers = users
        }
    }

    nonisolated public func onBanListUpdated(bans: [BanEntryInfo]) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.banList = bans
        }
    }

    nonisolated public func onUserStatsReceived(stats: UserStatsInfo) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.currentUserStats = stats
            if self.activeModal != .userStats {
                self.activeModal = .userStats
            }
        }
    }
}

extension RegisteredUser: Identifiable {
    public var id: UInt32 { userId }
}

extension BanEntryInfo: Identifiable {
    public var id: String { "\(ip)/\(mask)-\(hash)-\(start)" }
}
