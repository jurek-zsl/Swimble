import SwiftUI

/// Recursive channel tree sidebar inside NavigationSplitView with live search and status bar.
public struct ChannelTreeSidebar: View {
    @Bindable public var store: MumbleStore
    @Binding public var showConnectSheet: Bool
    @State private var searchText: String = ""

    public init(store: MumbleStore, showConnectSheet: Binding<Bool>) {
        self.store = store
        self._showConnectSheet = showConnectSheet
    }

    private var matchingChannels: [ChannelInfo] {
        guard !searchText.isEmpty else { return [] }
        return store.channels.filter {
            $0.name.localizedStandardContains(searchText) ||
            $0.description.localizedStandardContains(searchText)
        }
    }

    private var matchingUsers: [UserInfo] {
        guard !searchText.isEmpty else { return [] }
        return store.users.filter {
            $0.name.localizedStandardContains(searchText) ||
            ($0.comment?.localizedStandardContains(searchText) ?? false)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            if store.connectionStatus != .connected && store.channels.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .foregroundStyle(store.accentTint)

                    VStack(spacing: 4) {
                        Text(store.connectionStatus == .connecting ? "Connecting to Murmur..." : "Not Connected")
                            .font(.headline)
                        Text("Connect to a Mumble server to start voice chat.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }

                    Button(action: { showConnectSheet = true }) {
                        Label("Connect to Server", systemImage: "server.rack")
                            .font(.subheadline.bold())
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(store.accentTint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(24)
            } else {
                List(selection: $store.selectedChannelId) {
                    if !searchText.isEmpty {
                        // Search Results Section
                        if !matchingChannels.isEmpty {
                            Section("Channels") {
                                ForEach(matchingChannels, id: \.id) { ch in
                                    SearchChannelRow(store: store, channel: ch)
                                }
                            }
                        }

                        if !matchingUsers.isEmpty {
                            Section("Users") {
                                ForEach(matchingUsers, id: \.sessionId) { user in
                                    UserRowView(store: store, user: user)
                                }
                            }
                        }

                        if matchingChannels.isEmpty && matchingUsers.isEmpty {
                            ContentUnavailableView.search(text: searchText)
                        }
                    } else {
                        // Normal Recursive Channel Tree
                        ForEach(store.channelTree) { node in
                            ChannelTreeNodeView(store: store, node: node)
                        }
                    }
                }
                .listStyle(.sidebar)
                .searchable(text: $searchText, prompt: "Search channels and users...")
            }

            // Bottom Server Status Bar
            Divider()
            HStack(spacing: 10) {
                Circle()
                    .fill(store.connectionStatus == .connected ? Color.green : (store.connectionStatus == .connecting ? Color.orange : Color.secondary.opacity(0.4)))
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.activeBookmark?.name ?? (store.connectionStatus == .connected ? "Connected" : "Offline"))
                        .font(.caption.bold())
                        .lineLimit(1)

                    if store.connectionStatus == .connected {
                        Text("\(store.users.count) user\(store.users.count == 1 ? "" : "s") online")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button(action: { showConnectSheet = true }) {
                    Image(systemName: "server.rack")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Servers")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .navigationTitle(store.activeBookmark?.name ?? "Swimble")
    }
}

/// Recursive disclosure row for a channel tree node.
struct ChannelTreeNodeView: View {
    @Bindable var store: MumbleStore
    let node: ChannelTreeNode
    @State private var isExpanded: Bool = true

    var body: some View {
        if node.children.isEmpty && node.users.isEmpty {
            ChannelRowView(store: store, channel: node.channel, userCount: 0)
                .tag(node.channel.id)
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                // Subchannels
                ForEach(node.children) { child in
                    ChannelTreeNodeView(store: store, node: child)
                }
                // Users in this channel
                ForEach(node.users, id: \.sessionId) { user in
                    UserRowView(store: store, user: user)
                }
            } label: {
                ChannelRowView(
                    store: store,
                    channel: node.channel,
                    userCount: node.users.count
                )
            }
            .tag(node.channel.id)
        }
    }
}

/// Search result row for a channel.
struct SearchChannelRow: View {
    @Bindable var store: MumbleStore
    let channel: ChannelInfo

    private var isJoined: Bool {
        store.myChannelId == channel.id
    }

    var body: some View {
        HStack {
            Image(systemName: isJoined ? "speaker.wave.2.fill" : "folder.fill")
                .foregroundStyle(isJoined ? Color.green : Color.secondary)
            Text(channel.name)
                .bold(isJoined)
            Spacer()
            if !isJoined {
                Button("Join") {
                    store.joinChannel(channelId: channel.id)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .tag(channel.id)
    }
}
