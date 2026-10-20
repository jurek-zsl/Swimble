import SwiftUI

/// Channel row view in the channel tree with user counts, rich descriptions, and double-click to join.
public struct ChannelRowView: View {
    @Bindable public var store: MumbleStore
    public let channel: ChannelInfo
    public let userCount: Int

    @State private var showingEditChannel = false
    @State private var showingAddSubchannelAlert = false
    @State private var subchannelName = ""
    @State private var subchannelDesc = ""
    @State private var subchannelTemporary = false

    @State private var showingEditDescModal = false
    @State private var showDescriptionPopover = false
    @State private var isPinnedOpen = false
    @State private var isHoveringRow = false
    @State private var isHoveringPopover = false
    @State private var hoverTask: Task<Void, Never>? = nil
    @State private var showingPrivileges = false
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
                    isPinnedOpen = false
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
        .onHover { inPopover in
            isHoveringPopover = inPopover
            if !inPopover && !isHoveringRow && !isPinnedOpen {
                hoverTask?.cancel()
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    if !Task.isCancelled && !isHoveringRow && !isHoveringPopover && !isPinnedOpen {
                        showDescriptionPopover = false
                    }
                }
            }
        }
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
            } else {
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

            if store.isListening(to: channel.id) { Image(systemName: "ear.badge.waveform").help("Listening to this channel") }
            if !channel.links.isEmpty { Image(systemName: "link").help("Linked channels: \(channel.links.compactMap { id in store.channels.first { $0.id == id }?.name }.joined(separator: ", "))") }
            if channel.isTemporary {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Temporary channel")
            }

            // Description Badge with Rich Popover
            if !channel.description.isEmpty {
                Button(action: {
                    isPinnedOpen = true
                    showDescriptionPopover.toggle()
                }) {
                    Image(systemName: containsImages(channel.description) ? "photo.on.rectangle.angled" : "info.circle")
                        .font(.caption2)
                        .foregroundStyle(containsImages(channel.description) ? store.accentTint : Color.secondary)
                }
                .buttonStyle(.plain)
                .help(containsImages(channel.description) ? "Channel Description (Contains Images)" : "Channel Description")
            }

            Spacer()

            if userCount > 0 && SettingsState.shared.alwaysShowChannelUserCount {
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
        .popover(isPresented: $showDescriptionPopover, arrowEdge: .trailing) {
            descriptionPopoverContent
        }
        .onHover { hovering in
            isHoveringRow = hovering
            hoverTask?.cancel()
            if hovering {
                guard !channel.description.isEmpty else { return }
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1200))
                    if !Task.isCancelled && isHoveringRow {
                        showDescriptionPopover = true
                    }
                }
            } else {
                guard !isPinnedOpen else { return }
                hoverTask = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(250))
                    if !Task.isCancelled && !isHoveringRow && !isHoveringPopover && !isPinnedOpen {
                        showDescriptionPopover = false
                    }
                }
            }
        }
        .onChange(of: showDescriptionPopover) { _, newValue in
            if !newValue {
                isPinnedOpen = false
                hoverTask?.cancel()
            }
        }
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
            store.selectedChannelId = channel.id
        }
        .contextMenu {
            Button(channel.canEnter ? "Join Channel" : "Channel Locked (Cannot Enter)") {
                if channel.canEnter {
                    store.joinChannel(channelId: channel.id)
                } else {
                    store.logSystemMessage("Cannot enter \(channel.name): Channel is locked.", icon: "lock.fill")
                    SoundManager.shared.playPermissionDenied()
                }
            }

            Button(store.isListening(to: channel.id) ? "Stop Listening to Channel" : "Listen to Channel") {
                store.client.setChannelListening(channelId: channel.id, listening: !store.isListening(to: channel.id))
            }.disabled(!store.hasPermission(0x800, in: channel.id))
            if let ownChannel = store.myChannelId, ownChannel != channel.id {
                let linked = store.myChannel?.links.contains(channel.id) == true
                Button(linked ? "Unlink from My Channel" : "Link with My Channel") {
                    store.client.setChannelLink(channelId: ownChannel, otherId: channel.id, linked: !linked)
                }.disabled(!store.hasPermission(0x80, in: channel.id) || !store.hasPermission(0x80, in: ownChannel))
            }
            Button("Edit Channel…") { showingEditChannel = true }.disabled(!store.hasPermission(1, in: channel.id))

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

            Button("Channel Privileges…") { showingPrivileges = true }
                .disabled(!store.canEditChannelPrivileges(in: channel.id))

            Button("Edit Description...") {
                showingEditDescModal = true
            }.disabled(!store.hasPermission(1, in: channel.id))

            Button("Add Sub-Channel...") {
                subchannelName = ""
                subchannelDesc = ""
                subchannelTemporary = false
                showingAddSubchannelAlert = true
            }.disabled(!store.hasPermission(0x40, in: channel.id) && !store.hasPermission(0x400, in: channel.id))

            if channel.id != 0 {
                Divider()
                Button("Remove Channel", role: .destructive) {
                    showingRemoveAlert = true
                }.disabled(!store.hasPermission(1, in: channel.id))
            }
        }
        .sheet(isPresented: $showingEditChannel) { EditChannelModal(store: store, channel: channel) }
        .sheet(isPresented: $showingPrivileges) { ChannelPrivilegesModal(store: store, channel: channel) }
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
            }.disabled(!store.hasPermission(0x40, in: channel.id))
            Button("Create (Temporary)") {
                store.createChannel(
                    parentId: channel.id,
                    name: subchannelName,
                    description: subchannelDesc,
                    position: 0,
                    isTemporary: true
                )
            }.disabled(!store.hasPermission(0x400, in: channel.id))
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
