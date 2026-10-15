import SwiftUI

/// Recursive channel tree sidebar inside NavigationSplitView.
public struct ChannelTreeSidebar: View {
    @Bindable public var store: MumbleStore
    @Binding public var showConnectSheet: Bool

    public init(store: MumbleStore, showConnectSheet: Binding<Bool>) {
        self.store = store
        self._showConnectSheet = showConnectSheet
    }

    public var body: some View {
        VStack(spacing: 0) {
            if store.connectionStatus != .connected && store.channels.isEmpty {
                VStack(spacing: 16) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.secondary)

                    Text(store.connectionStatus == .connecting ? "Connecting..." : "Not Connected")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Button("Connect to Server...") {
                        showConnectSheet = true
                    }
                    .buttonStyle(.borderedProminent)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List(selection: $store.selectedChannelId) {
                    ForEach(store.channelTree) { node in
                        ChannelTreeNodeView(store: store, node: node)
                    }
                }
                .listStyle(.sidebar)
            }
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
