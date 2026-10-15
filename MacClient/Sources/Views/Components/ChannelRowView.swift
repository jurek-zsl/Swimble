import SwiftUI

/// Channel row view in the channel tree with user counts and double-click to join.
public struct ChannelRowView: View {
    @Bindable public var store: MumbleStore
    public let channel: ChannelInfo
    public let userCount: Int

    @State private var showingAddSubchannelAlert = false
    @State private var subchannelName = ""
    @State private var subchannelDesc = ""
    @State private var subchannelTemporary = false

    @State private var showingEditDescAlert = false
    @State private var editDescText = ""
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

    public var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isJoined ? "speaker.wave.2.fill" : "folder.fill")
                .foregroundStyle(isJoined ? Color.accentColor : Color.secondary)
                .font(.subheadline)

            Text(channel.name)
                .font(isJoined ? .headline : .body)
                .foregroundStyle(isJoined ? Color.accentColor : Color.primary)

            if channel.isTemporary {
                Image(systemName: "clock")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Temporary channel")
            }

            if !channel.description.isEmpty {
                Image(systemName: "info.circle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .help(channel.description)
            }

            Spacer()

            if userCount > 0 {
                Text("\(userCount)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(.secondary)
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
        .onTapGesture(count: 2) {
            store.joinChannel(channelId: channel.id)
        }
        .onTapGesture(count: 1) {
            store.selectedChannelId = channel.id
        }
        .contextMenu {
            Button("Join Channel") {
                store.joinChannel(channelId: channel.id)
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

            Button("Add Sub-Channel...") {
                subchannelName = ""
                subchannelDesc = ""
                subchannelTemporary = false
                showingAddSubchannelAlert = true
            }

            Button("Edit Description...") {
                editDescText = channel.description
                showingEditDescAlert = true
            }

            if channel.id != 0 {
                Divider()
                Button("Remove Channel", role: .destructive) {
                    showingRemoveAlert = true
                }
            }
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
        .alert("Edit Channel Description", isPresented: $showingEditDescAlert) {
            TextField("Description", text: $editDescText)
            Button("Save") {
                store.setChannelDescription(channelId: channel.id, description: editDescText)
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
