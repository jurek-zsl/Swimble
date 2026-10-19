import Foundation
import CryptoKit
import Observation
import SwiftUI

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

    public var id: String { rawValue }
}

public enum ChatTabTarget: Hashable, Equatable, Identifiable {
    case server
    case channel(UInt32)
    case direct(UInt32, String)

    public var id: String {
        switch self {
        case .server:
            return "server"
        case .channel(let cid):
            return "ch_\(cid)"
        case .direct(let sid, _):
            return "dm_\(sid)"
        }
    }
}

/// Main application state store managing Mumble server networking, channel hierarchies,
/// user speaking states, chat activity, and audio hardware synchronization.
@Observable
@MainActor
public final class MumbleStore: MumbleEventHandler, @unchecked Sendable {
    public static weak var shared: MumbleStore? = nil
    public private(set) var client: MumbleClient!
    public private(set) var audioEngine: MacAudioEngine!
    public let globalPTT = GlobalPTT.shared

    // Connection & Networking State
    public var connectionStatus: ConnectionStatus = .disconnected
    public var tcpPingMs: Float = 0.0
    public var udpPingMs: Float = 0.0
    public var usingUdpTunnel: Bool = false
    public var isUserInitiatedDisconnect: Bool = false
    public var currentUserStats: UserStatsInfo? = nil

    // Channel & User Tree
    public var channels: [ChannelInfo] = []
    public var channelTree: [ChannelTreeNode] = []
    public var previouslyLockedChannelIds: Set<UInt32> = []
    public var users: [UserInfo] = []
    public var selectedChannelId: UInt32? = nil
    public var mySessionId: UInt32? = nil

    // Chat & Tabs
    public var chatMessages: [ChatMessage] = []
    public var openChatTabs: [ChatTabTarget] = [.server]
    public var activeChatTab: ChatTabTarget = .server {
        didSet {
            unreadTabCounts[activeChatTab.id] = 0
            if case .channel(let cid) = activeChatTab {
                selectedChannelId = cid
            }
        }
    }
    public var unreadTabCounts: [String: Int] = [:]

    // Local Mute & Deafen
    public var isSelfMuted: Bool = false
    public var isSelfDeafened: Bool = false

    // Per-User Audio Settings (sessionId -> value)
    public var userVolumes: [UInt32: Float] = [:]
    public var userLocalMutes: [UInt32: Bool] = [:]

    // Bookmarks & Identity
    public var bookmarks: [ServerBookmark] = []
    public var activeBookmark: ServerBookmark? = nil
    public var clientIdentity: ClientIdentity!
    public var certFingerprint: String = ""

    // Server Ping Caching
    public var serverPingResults: [String: ServerPingInfo] = [:]
    public var serverPingFailed: [String: Bool] = [:]
    public var isPingingServers: Bool = false

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

    public var autoReconnectOnLaunch: Bool = UserDefaults.standard.bool(forKey: "Swimble_AutoReconnect") {
        didSet {
            UserDefaults.standard.set(autoReconnectOnLaunch, forKey: "Swimble_AutoReconnect")
        }
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
        Self.shared = self
        // 1. Initialize or load persistent client identity from Keychain
        let identity: ClientIdentity
        if let saved = KeychainHelper.loadClientIdentity() {
            identity = saved
        } else {
            let generated = generateClientIdentity(commonName: "Swimble User")
            _ = KeychainHelper.saveClientIdentity(generated)
            identity = generated
        }
        self.clientIdentity = identity
        self.certFingerprint = Self.computeFingerprint(pem: identity.certPem)

        // 2. Initialize Rust MumbleClient with self as event handler
        let client = MumbleClient(handler: self)
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
                    self.rebuildTree()
                }
            }
        }
        self.globalPTT.configure(audioEngine: audioEngine)
        self.globalPTT.onToggleMute = { [weak self] in
            self?.toggleSelfMute()
        }
        self.globalPTT.onToggleDeafen = { [weak self] in
            self?.toggleSelfDeaf()
        }
        self.globalPTT.onWhisperChanged = { [weak self] isWhispering in
            self?.setWhispering(isWhispering, targetId: 1)
        }
        self.globalPTT.onToggleOverlay = { [weak self] in
            guard let self = self else { return }
            FloatingOverlayManager.shared.toggle(store: self)
        }

        // 4. Load saved bookmarks & access tokens
        loadBookmarks()
        loadAccessTokens()

        // 5. Initialize accent tint, apply saved settings, and auto-connect if enabled
        self.accentTint = Self.colorFromName(self.accentColorName)
        startIdleMonitor()

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            SettingsState.shared.apply(to: self)
        }

        if (self.autoReconnectOnLaunch || SettingsState.shared.autoConnectLastUsedServer),
           let fav = self.bookmarks.first(where: { $0.isFavorite }) ?? self.bookmarks.first {
            Task { @MainActor [weak self] in
                self?.connect(bookmark: fav)
            }
        }
    }

    // MARK: - Server Connection Actions

    public func connect(bookmark: ServerBookmark) {
        self.isUserInitiatedDisconnect = false
        self.reconnectTimer?.invalidate()
        self.reconnectTimer = nil
        self.activeBookmark = bookmark
        self.connectionStatus = .connecting

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
            clientKeyPem: clientIdentity.keyPem
        )

        // Start local audio engine
        do {
            try audioEngine.start()
        } catch {
            print("[MumbleStore] Error starting audio engine: \(error)")
        }
    }

    public func disconnect() {
        self.isUserInitiatedDisconnect = true
        self.reconnectTimer?.invalidate()
        self.reconnectTimer = nil
        audioEngine.stop()
        client.disconnect()
        self.connectionStatus = .disconnected
        self.activeBookmark = nil
        self.channels = []
        self.channelTree = []
        self.users = []
        self.mySessionId = nil
        self.selectedChannelId = nil
        self.hasLoggedInitialJoin = false
        self.lastKnownMyChannelId = nil
        self.openChatTabs = [.server]
        self.activeChatTab = .server
        self.unreadTabCounts.removeAll()
        self.pendingUserMoves.removeAll()
        self.previousUserChannelMap.removeAll()
        self.previousUserNames.removeAll()
        self.previousUserMuteMap.removeAll()
        self.previousUserDeafMap.removeAll()
    }

    // MARK: - Chat Tabs & User Stats

    public func openChannelChat(channelId: UInt32) {
        let target = ChatTabTarget.channel(channelId)
        if !openChatTabs.contains(where: { $0.id == target.id }) {
            openChatTabs.append(target)
        }
        activeChatTab = target
        selectedChannelId = channelId
        unreadTabCounts[target.id] = 0
    }

    public func openDirectChat(sessionId: UInt32, userName: String) {
        let target = ChatTabTarget.direct(sessionId, userName)
        if !openChatTabs.contains(where: { $0.id == target.id }) {
            openChatTabs.append(target)
        }
        activeChatTab = target
        unreadTabCounts[target.id] = 0
    }

    public func selectChatTab(_ target: ChatTabTarget) {
        activeChatTab = target
        unreadTabCounts[target.id] = 0
        if case .channel(let cid) = target {
            selectedChannelId = cid
        }
    }

    public func closeChatTab(_ target: ChatTabTarget) {
        guard target != .server else { return }
        if let idx = openChatTabs.firstIndex(where: { $0.id == target.id }) {
            openChatTabs.remove(at: idx)
            unreadTabCounts.removeValue(forKey: target.id)
            if activeChatTab.id == target.id {
                let newIdx = max(0, idx - 1)
                activeChatTab = openChatTabs[newIdx]
            }
        }
    }

    public func requestUserStats(sessionId: UInt32) {
        client.requestUserStats(sessionId: sessionId, statsOnly: false)
    }

    // MARK: - Channel & User Actions

    public func joinChannel(channelId: UInt32) {
        client.joinChannel(channelId: channelId)
        self.selectedChannelId = channelId
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
        self.isSelfMuted = muted
        audioEngine.isMuted = muted
        client.setSelfMute(muted: muted)
        EventNotificationManager.shared.dispatch(
            eventName: "You muted/deafened yourself",
            detail: muted ? "You are now muted." : "You are now unmuted.",
            store: self
        )
    }

    public func setSelfDeaf(_ deafened: Bool) {
        self.isSelfDeafened = deafened
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
        AudioRecorder.shared.isRecording
    }

    public var recordingDuration: TimeInterval {
        AudioRecorder.shared.durationSeconds
    }

    public func toggleAudioRecording() {
        if AudioRecorder.shared.isRecording {
            if let savedUrl = AudioRecorder.shared.stopRecording() {
                client.setRecordingState(recording: false)
                EventNotificationManager.shared.dispatch(
                    eventName: "Recording state changed",
                    detail: "Finished recording: \(savedUrl.lastPathComponent) (saved to ~/Music/Swimble/)",
                    store: self
                )
            }
        } else {
            if AudioRecorder.shared.startRecording() {
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

    public func updateClientIdentity(_ newIdentity: ClientIdentity) {
        self.clientIdentity = newIdentity
        self.certFingerprint = Self.computeFingerprint(pem: newIdentity.certPem)
        _ = KeychainHelper.saveClientIdentity(newIdentity)
    }

    // MARK: - Bookmarks Management

    public func addBookmark(_ bookmark: ServerBookmark) {
        bookmarks.append(bookmark)
        saveBookmarks()
        if let pwd = bookmark.password, !pwd.isEmpty {
            _ = KeychainHelper.saveServerPassword(bookmarkId: bookmark.id, password: pwd)
        }
    }

    public func saveBookmark(_ bookmark: ServerBookmark) {
        if let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[idx] = bookmark
            saveBookmarks()
            if let pwd = bookmark.password, !pwd.isEmpty {
                _ = KeychainHelper.saveServerPassword(bookmarkId: bookmark.id, password: pwd)
            }
        }
    }

    public func deleteBookmark(_ bookmark: ServerBookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        _ = KeychainHelper.deleteServerPassword(bookmarkId: bookmark.id)
        saveBookmarks()
    }

    public func toggleFavoriteBookmark(_ bookmark: ServerBookmark) {
        if let idx = bookmarks.firstIndex(where: { $0.id == bookmark.id }) {
            bookmarks[idx].isFavorite.toggle()
            saveBookmarks()
        }
    }

    private func loadBookmarks() {
        if let data = UserDefaults.standard.data(forKey: "Swimble_Bookmarks") ?? UserDefaults.standard.data(forKey: "MumbleGlass_Bookmarks"),
           let saved = try? JSONDecoder().decode([ServerBookmark].self, from: data),
           !saved.isEmpty {
            self.bookmarks = saved
        } else {
            self.bookmarks = [ServerBookmark.localDefault]
            saveBookmarks()
        }
    }

    private func saveBookmarks() {
        if let data = try? JSONEncoder().encode(bookmarks) {
            UserDefaults.standard.set(data, forKey: "Swimble_Bookmarks")
        }
    }

    // MARK: - Server Ping Operations

    public static func pingKey(host: String, port: UInt16) -> String {
        let clean = host.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "mumble://", with: "")
            .replacingOccurrences(of: "https://", with: "")
            .replacingOccurrences(of: "http://", with: "")
            .lowercased()
        let cleanHost = clean.components(separatedBy: ":").first ?? clean
        return "\(cleanHost):\(port)"
    }

    public func pingKey(for bookmark: ServerBookmark) -> String {
        Self.pingKey(host: bookmark.host, port: bookmark.port)
    }

    public func pingBookmark(_ bookmark: ServerBookmark) async {
        let cleanHost = bookmark.host.trimmingCharacters(in: .whitespacesAndNewlines)
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
        let list = self.bookmarks
        Task { [weak self] in
            for bookmark in list {
                Task { [weak self] in
                    await self?.pingBookmark(bookmark)
                }
            }
            self?.isPingingServers = false
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

    public func rebuildTree() {
        self.channelTree = ChannelTreeNode.buildTree(
            channels: self.channels,
            users: self.users,
            userSort: SettingsState.shared.userSort,
            filterHidesEmpty: SettingsState.shared.filterHidesEmptyChannels
        )
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
        logSystemMessage("Connection lost. Automatically reconnecting in 5 seconds...", icon: "arrow.clockwise")
        reconnectTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, !self.isUserInitiatedDisconnect, self.connectionStatus == .disconnected else { return }
                self.connect(bookmark: bm)
            }
        }
    }

    public func updateDockBadge() {
        if SettingsState.shared.includeUnreadCountInTaskbar {
            let count = self.chatMessages.filter { $0.senderSession != self.mySessionId && $0.senderSession != 0 }.count
            NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
        } else {
            NSApp.dockTile.badgeLabel = nil
        }
    }

    // MARK: - UniFFI Event Handler Callbacks

    nonisolated public func onConnectionStatusChanged(status: ConnectionStatus) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.connectionStatus = status
            if status == .connected {
                self.mySessionId = self.client.getMySession()
                self.client.setTokens(tokens: self.accessTokens)
                EventNotificationManager.shared.dispatch(
                    eventName: "Connected",
                    detail: "Connected to \(self.activeBookmark?.name ?? "Server")",
                    store: self
                )
            } else if status == .disconnected || status == .failed {
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
                if !self.isUserInitiatedDisconnect && SettingsState.shared.reconnectAutomatically && self.activeBookmark != nil {
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
            if self.selectedChannelId == nil, let first = channels.first {
                self.selectedChannelId = first.id
            }
            self.rebuildTree()
            self.checkInitialJoin()
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
                self.audioEngine.isMuted = me.isSelfMuted
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
                self.rebuildTree()

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

            // Update tab unread counts
            let targetTabId: String
            if let cid = message.channelId {
                targetTabId = "ch_\(cid)"
            } else if message.senderSession != 0 && message.senderSession != self.mySessionId {
                targetTabId = "dm_\(message.senderSession)"
                let dmTarget = ChatTabTarget.direct(message.senderSession, message.senderName)
                if !self.openChatTabs.contains(where: { $0.id == dmTarget.id }) {
                    self.openChatTabs.append(dmTarget)
                }
            } else {
                targetTabId = "server"
            }

            if self.activeChatTab.id != targetTabId {
                self.unreadTabCounts[targetTabId, default: 0] += 1
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
            self.activeModal = .userStats
        }
    }
}

extension RegisteredUser: Identifiable {
    public var id: UInt32 { userId }
}

extension BanEntryInfo: Identifiable {
    public var id: String { "\(ip)/\(mask)-\(hash)-\(start)" }
}
