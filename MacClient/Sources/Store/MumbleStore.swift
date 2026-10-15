import Foundation
import CryptoKit
import Observation
import SwiftUI

/// Main application state store managing Mumble server networking, channel hierarchies,
/// user speaking states, chat activity, and audio hardware synchronization.
@Observable
@MainActor
public final class MumbleStore: MumbleEventHandler, @unchecked Sendable {
    public private(set) var client: MumbleClient!
    public private(set) var audioEngine: MacAudioEngine!
    public let globalPTT = GlobalPTT.shared

    // Connection & Networking State
    public var connectionStatus: ConnectionStatus = .disconnected
    public var tcpPingMs: Float = 0.0
    public var udpPingMs: Float = 0.0
    public var usingUdpTunnel: Bool = false

    // Channel & User Tree
    public var channels: [ChannelInfo] = []
    public var channelTree: [ChannelTreeNode] = []
    public var users: [UserInfo] = []
    public var selectedChannelId: UInt32? = nil
    public var mySessionId: UInt32? = nil

    // Chat
    public var chatMessages: [ChatMessage] = []

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

    // Server Connection Information
    public var connectionInfo: ServerConnectionInfo? = nil

    // Server ACL Access Tokens
    public var accessTokens: [String] = []

    // Whisper & Shout
    public var isWhispering: Bool = false
    public var whisperTargetConfig: VoiceTargetConfig? = nil

    // Ignored Users for Chat
    public var ignoredTextMessageUsers: Set<UInt32> = []

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

        // 4. Load saved bookmarks & access tokens
        loadBookmarks()
        loadAccessTokens()

        // 5. Initialize accent tint and auto-connect if enabled
        self.accentTint = Self.colorFromName(self.accentColorName)
        if self.autoReconnectOnLaunch, let fav = self.bookmarks.first(where: { $0.isFavorite }) ?? self.bookmarks.first {
            Task { @MainActor [weak self] in
                self?.connect(bookmark: fav)
            }
        }
    }

    // MARK: - Server Connection Actions

    public func connect(bookmark: ServerBookmark) {
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
        audioEngine.stop()
        client.disconnect()
        self.connectionStatus = .disconnected
        self.channels = []
        self.channelTree = []
        self.users = []
        self.mySessionId = nil
        self.selectedChannelId = nil
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
            htmlBody: message,
            timestamp: UInt64(Date().timeIntervalSince1970 * 1000)
        )
        self.chatMessages.append(localMsg)
    }

    public func toggleSelfMute() {
        let newMuted = !isSelfMuted
        self.isSelfMuted = newMuted
        client.setSelfMute(muted: newMuted)
        SoundManager.shared.playMute(isMuted: newMuted)
    }

    public func toggleSelfDeaf() {
        let newDeaf = !isSelfDeafened
        self.isSelfDeafened = newDeaf
        client.setSelfDeaf(deafened: newDeaf)
        SoundManager.shared.playDeafen(isDeafened: newDeaf)
        // Mumble convention: deafening also mutes
        if newDeaf {
            self.isSelfMuted = true
        }
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
    }

    public func setComment(comment: String) {
        client.setComment(comment: comment)
    }

    public func sendUserMessage(sessionId: UInt32, message: String) {
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        client.sendUserMessage(sessionId: sessionId, message: message)
    }

    public func setUserPrioritySpeaker(sessionId: UInt32, priority: Bool) {
        client.setUserPrioritySpeaker(sessionId: sessionId, priority: priority)
    }

    public func setUserServerMuteDeaf(sessionId: UInt32, mute: Bool, deaf: Bool) {
        client.setUserServerMuteDeaf(sessionId: sessionId, mute: mute, deaf: deaf)
    }

    public func moveUser(sessionId: UInt32, channelId: UInt32) {
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

    private func rebuildTree() {
        self.channelTree = ChannelTreeNode.buildTree(channels: self.channels, users: self.users)
    }

    // MARK: - UniFFI Event Handler Callbacks

    nonisolated public func onConnectionStatusChanged(status: ConnectionStatus) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.connectionStatus = status
            if status == .connected {
                self.mySessionId = self.client.getMySession()
                self.client.setTokens(tokens: self.accessTokens)
            }
        }
    }

    nonisolated public func onChannelsUpdated(channels: [ChannelInfo]) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            self.channels = channels
            if self.selectedChannelId == nil, let first = channels.first {
                self.selectedChannelId = first.id
            }
            self.rebuildTree()
        }
    }

    nonisolated public func onUsersUpdated(users: [UserInfo]) {
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            let oldSessions = Set(self.users.map { $0.sessionId })
            let newSessions = Set(users.map { $0.sessionId })

            if !self.users.isEmpty {
                let joined = newSessions.subtracting(oldSessions)
                let left = oldSessions.subtracting(newSessions)
                let myId = self.mySessionId ?? 0
                if !joined.isEmpty && !joined.contains(myId) {
                    SoundManager.shared.playUserJoined()
                } else if !left.isEmpty && !left.contains(myId) {
                    SoundManager.shared.playUserLeft()
                }
            }

            self.users = users
            if let myId = self.mySessionId, let me = users.first(where: { $0.sessionId == myId }) {
                self.isSelfMuted = me.isSelfMuted
                self.isSelfDeafened = me.isSelfDeafened
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
            if message.senderSession != self.mySessionId {
                SoundManager.shared.playMessageReceived()
            }
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
        }
    }
}
