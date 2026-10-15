import SwiftUI

/// User row in the channel tree displaying speaking orb, mute/deafen badges, and local volume controls.
public struct UserRowView: View {
    @Bindable public var store: MumbleStore
    public let user: UserInfo

    @State private var showingCommentAlert = false
    @State private var commentInput = ""
    @State private var showingPrivateMessageAlert = false
    @State private var privateMessageInput = ""
    @State private var showingKickAlert = false
    @State private var kickReasonInput = ""
    @State private var showingBanAlert = false
    @State private var banReasonInput = ""
    @State private var isHovered = false

    public init(store: MumbleStore, user: UserInfo) {
        self.store = store
        self.user = user
    }

    private var isMe: Bool {
        user.sessionId == store.mySessionId
    }

    private var userVolume: Float {
        store.getUserVolume(sessionId: user.sessionId)
    }

    private var isLocallyMuted: Bool {
        store.isUserLocallyMuted(sessionId: user.sessionId)
    }

    private var isTextIgnored: Bool {
        store.isUserTextIgnored(sessionId: user.sessionId)
    }

    private var isTalking: Bool {
        if isMe {
            return store.audioEngine.isTransmitting
        }
        return user.isTalking
    }

    private var talkingState: TalkingState {
        if isMe {
            return store.isWhispering ? .whisper : .talking
        }
        return user.talkingState
    }

    public var body: some View {
        HStack(spacing: 8) {
            SpeakingOrbView(isTalking: isTalking, talkingState: talkingState, size: 10)

            Text(user.name)
                .font(.body)
                .foregroundStyle(isTalking ? Color.primary : Color.secondary)
                .fontWeight(isTalking ? .semibold : .regular)

            if isMe {
                Text("(you)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }

            Spacer()

            // Comment badge
            if let comment = user.comment, !comment.isEmpty {
                Image(systemName: "text.bubble.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue.opacity(0.8))
                    .help("Comment: \(comment)")
            }

            // Priority speaker badge
            if user.isPrioritySpeaker {
                Image(systemName: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
                    .help("Priority Speaker")
            }

            // Ignored text badge
            if isTextIgnored && !isMe {
                Image(systemName: "message.badge.slash")
                    .font(.caption2)
                    .foregroundStyle(.purple)
                    .help("Text Messages Ignored")
            }

            // Registered user badge
            if let uid = user.userId, uid > 0 {
                Image(systemName: "checkmark.seal.fill")
                    .font(.caption2)
                    .foregroundStyle(.blue)
                    .help("Registered on server")
            }

            if user.isSelfMuted || user.isMuted {
                Image(systemName: "mic.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            if user.isSelfDeafened || user.isDeafened {
                Image(systemName: "headphones")
                    .font(.caption2)
                    .foregroundStyle(.orange)
            }

            if isLocallyMuted && !isMe {
                Image(systemName: "speaker.slash.fill")
                    .font(.caption2)
                    .foregroundStyle(.yellow)
            }
        }
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(
                    isTalking
                        ? Color.green.opacity(0.12)
                        : (isHovered ? Color.secondary.opacity(0.12) : Color.clear)
                )
        )
        .animation(.easeInOut(duration: 0.15), value: isTalking)
        .onHover { hovering in
            isHovered = hovering
        }
        .contentShape(Rectangle())
        .selectionDisabled(true)
        .draggable(String(user.sessionId))
        .contextMenu {
            if !isMe {
                Text(user.name)
                    .font(.headline)
                Divider()

                Button("Send Private Message...") {
                    privateMessageInput = ""
                    showingPrivateMessageAlert = true
                }

                Button("Whisper to User") {
                    let config = VoiceTargetConfig(
                        id: 1,
                        sessions: [user.sessionId],
                        channelId: nil,
                        group: nil,
                        links: false,
                        children: false
                    )
                    store.setupVoiceTarget(config: config)
                    store.setWhispering(true, targetId: 1)
                }

                Divider()

                Toggle("Local Mute", isOn: Binding(
                    get: { store.isUserLocallyMuted(sessionId: user.sessionId) },
                    set: { store.setUserLocallyMuted(sessionId: user.sessionId, muted: $0) }
                ))

                Toggle("Ignore Text Messages", isOn: Binding(
                    get: { store.isUserTextIgnored(sessionId: user.sessionId) },
                    set: { _ in store.toggleIgnoreTextMessages(sessionId: user.sessionId) }
                ))

                Divider()

                Menu("Local Volume (\(Int(userVolume * 100))%)") {
                    Button("Mute (0%)") { store.setUserVolume(sessionId: user.sessionId, volume: 0.0) }
                    Button("50%") { store.setUserVolume(sessionId: user.sessionId, volume: 0.5) }
                    Button("100% (Normal)") { store.setUserVolume(sessionId: user.sessionId, volume: 1.0) }
                    Button("150%") { store.setUserVolume(sessionId: user.sessionId, volume: 1.5) }
                    Button("200% (Maximum)") { store.setUserVolume(sessionId: user.sessionId, volume: 2.0) }
                }

                Slider(
                    value: Binding(
                        get: { Double(store.getUserVolume(sessionId: user.sessionId)) },
                        set: { store.setUserVolume(sessionId: user.sessionId, volume: Float($0)) }
                    ),
                    in: 0.0...2.0,
                    step: 0.05
                ) {
                    Text("Volume")
                }

                Divider()

                Menu("Admin Actions") {
                    Button(user.isPrioritySpeaker ? "Revoke Priority Speaker" : "Grant Priority Speaker") {
                        store.setUserPrioritySpeaker(sessionId: user.sessionId, priority: !user.isPrioritySpeaker)
                    }

                    Button(user.isMuted ? "Server Unmute" : "Server Mute") {
                        store.setUserServerMuteDeaf(sessionId: user.sessionId, mute: !user.isMuted, deaf: user.isDeafened)
                    }

                    Button(user.isDeafened ? "Server Undeafen" : "Server Deafen") {
                        store.setUserServerMuteDeaf(sessionId: user.sessionId, mute: user.isMuted, deaf: !user.isDeafened)
                    }

                    Divider()

                    Button("Kick User...", role: .destructive) {
                        kickReasonInput = ""
                        showingKickAlert = true
                    }

                    Button("Ban User...", role: .destructive) {
                        banReasonInput = ""
                        showingBanAlert = true
                    }
                }
            } else {
                Text("\(user.name) (You)")
                    .font(.headline)
                Divider()

                Button("Register on Server") {
                    store.registerUser()
                }

                Button("Change Comment...") {
                    commentInput = user.comment ?? ""
                    showingCommentAlert = true
                }

                Divider()

                Button(store.isSelfMuted ? "Unmute Self" : "Mute Self") {
                    store.toggleSelfMute()
                }
                Button(store.isSelfDeafened ? "Undeafen Self" : "Deafen Self") {
                    store.toggleSelfDeaf()
                }
            }
        }
        .alert("Change Comment", isPresented: $showingCommentAlert) {
            TextField("Comment text", text: $commentInput)
            Button("Save") {
                store.setComment(comment: commentInput)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Send Private Message to \(user.name)", isPresented: $showingPrivateMessageAlert) {
            TextField("Message", text: $privateMessageInput)
            Button("Send") {
                store.sendUserMessage(sessionId: user.sessionId, message: privateMessageInput)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Kick \(user.name)", isPresented: $showingKickAlert) {
            TextField("Reason (optional)", text: $kickReasonInput)
            Button("Kick", role: .destructive) {
                store.kickUser(sessionId: user.sessionId, reason: kickReasonInput.isEmpty ? nil : kickReasonInput)
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Ban \(user.name)", isPresented: $showingBanAlert) {
            TextField("Reason (optional)", text: $banReasonInput)
            Button("Ban", role: .destructive) {
                store.banUser(sessionId: user.sessionId, reason: banReasonInput.isEmpty ? nil : banReasonInput)
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
