import SwiftUI

/// Channel row view in the channel tree with user counts, rich descriptions, and double-click to join.
public struct ChannelRowView: View {
    @Bindable public var store: MumbleStore
    public let channel: ChannelInfo
    public let userCount: Int

    @State private var showingAddSubchannelAlert = false
    @State private var subchannelName = ""
    @State private var subchannelDesc = ""
    @State private var subchannelTemporary = false

    @State private var showingEditDescModal = false
    @State private var showDescriptionPopover = false
    @State private var showingRemoveAlert = false

    public init(store: MumbleStore, channel: ChannelInfo, userCount: Int) {
        self.store = store
        self.channel = channel
        self.userCount = userCount
    }

    private var isJoined: Bool {
        if let myId = store.mySessionId, let me = store.users.first(where: { $0.sessionId == myId }) {
            return me.channelId == channel.id
        }
        return false
    }

    private var isSelected: Bool {
        store.selectedChannelId == channel.id
    }

    private var isLocked: Bool {
        !channel.canEnter
    }

    private var isUnlockedRestricted: Bool {
        channel.canEnter && (channel.isEnterRestricted || store.previouslyLockedChannelIds.contains(channel.id))
    }

    @ViewBuilder
    private var descriptionPopoverContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "folder.fill")
                    .foregroundStyle(store.accentTint)
                Text(channel.name)
                    .font(.headline)
                    .lineLimit(1)
                Spacer()
                Button {
                    showDescriptionPopover = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Divider()

            ScrollView(.vertical, showsIndicators: true) {
                RichDescriptionView(rawHtml: channel.description, accentTint: store.accentTint)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(14)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 520)
        .frame(minHeight: 120, maxHeight: 460)
        .lineLimit(nil)
    }

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isJoined ? "speaker.wave.2.fill" : "folder.fill")
                .foregroundStyle(isJoined ? Color.green : Color.secondary)
                .font(.subheadline)

            Text(channel.name)
                .font(.system(size: 13, weight: isJoined ? .semibold : .medium))
                .foregroundStyle(isLocked ? Color.secondary : Color.primary)

            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .help("Locked channel: You cannot enter this channel")
            } else if isUnlockedRestricted {
                Image(systemName: "lock.open.fill")
                    .font(.caption2)
                    .foregroundStyle(.green)
                    .help("Unlocked channel: You have permission to enter")
            }

            if isJoined {
                Text("YOU")
                    .font(.system(size: 8, weight: .black))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.green.opacity(0.18), in: Capsule())
                    .foregroundStyle(.green)
            }

            if channel.isTemporary {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Temporary channel")
            }

            // Description Badge with Rich Popover
            if !channel.description.isEmpty {
                Button(action: { showDescriptionPopover.toggle() }) {
                    Image(systemName: containsImages(channel.description) ? "photo.on.rectangle.angled" : "info.circle")
                        .font(.caption2)
                        .foregroundStyle(containsImages(channel.description) ? store.accentTint : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(containsImages(channel.description) ? "Channel Description (Contains Images)" : "Channel Description")
                .popover(isPresented: $showDescriptionPopover, arrowEdge: .trailing) {
                    descriptionPopoverContent
                }
            }

            Spacer()

            if userCount > 0 || SettingsState.shared.alwaysShowChannelUserCount {
                Text("\(userCount)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(userCount > 0 ? Color.primary : Color.secondary.opacity(0.6))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .contentShape(Rectangle())
        .dropDestination(for: String.self) { items, _ in
            guard let first = items.first, let sessionId = UInt32(first) else { return false }
            store.moveUser(sessionId: sessionId, channelId: channel.id)
            return true
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if channel.canEnter {
                    store.joinChannel(channelId: channel.id)
                } else {
                    store.logSystemMessage("Cannot enter \(channel.name): Channel is locked.", icon: "lock.fill")
                    SoundManager.shared.playPermissionDenied()
                }
            }
        )
        .onTapGesture {
            store.openChannelChat(channelId: channel.id)
        }
        .contextMenu {
            Button("Open Chat Tab") {
                store.openChannelChat(channelId: channel.id)
            }

            Button(channel.canEnter ? "Join Channel" : "Channel Locked (Cannot Enter)") {
                if channel.canEnter {
                    store.joinChannel(channelId: channel.id)
                } else {
                    store.logSystemMessage("Cannot enter \(channel.name): Channel is locked.", icon: "lock.fill")
                    SoundManager.shared.playPermissionDenied()
                }
            }

            Button("Whisper to Channel") {
                let config = VoiceTargetConfig(
                    id: 2,
                    sessions: [],
                    channelId: channel.id,
                    group: nil,
                    links: false,
                    children: false
                )
                store.setupVoiceTarget(config: config)
                store.setWhispering(true, targetId: 2)
            }

            Divider()

            if !channel.description.isEmpty {
                Button("View Description & Images...") {
                    showDescriptionPopover = true
                }
            }

            Button("Edit Description...") {
                showingEditDescModal = true
            }

            Button("Add Sub-Channel...") {
                subchannelName = ""
                subchannelDesc = ""
                subchannelTemporary = false
                showingAddSubchannelAlert = true
            }

            if channel.id != 0 {
                Divider()
                Button("Remove Channel", role: .destructive) {
                    showingRemoveAlert = true
                }
            }
        }
        .sheet(isPresented: $showingEditDescModal) {
            EditChannelDescriptionModal(store: store, channel: channel)
        }
        .alert("Add Sub-Channel", isPresented: $showingAddSubchannelAlert) {
            TextField("Channel Name", text: $subchannelName)
            TextField("Description (optional)", text: $subchannelDesc)
            Button("Create (Permanent)") {
                store.createChannel(
                    parentId: channel.id,
                    name: subchannelName,
                    description: subchannelDesc,
                    position: 0,
                    isTemporary: false
                )
            }
            Button("Create (Temporary)") {
                store.createChannel(
                    parentId: channel.id,
                    name: subchannelName,
                    description: subchannelDesc,
                    position: 0,
                    isTemporary: true
                )
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Remove Channel '\(channel.name)'?", isPresented: $showingRemoveAlert) {
            Button("Remove", role: .destructive) {
                store.removeChannel(channelId: channel.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This channel and all its subchannels will be removed from the server.")
        }
    }
}
