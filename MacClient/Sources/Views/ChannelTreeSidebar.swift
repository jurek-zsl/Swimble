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

    private var targetBookmark: ServerBookmark? {
        store.activeBookmark ?? store.lastUsedBookmark
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
                                        .selectionDisabled(true)
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
            let pingKey = targetBookmark.map { store.pingKey(for: $0) }
            let pingInfo = pingKey.flatMap { store.serverPingResults[$0] }
            let pingFailed = pingKey.flatMap { store.serverPingFailed[$0] } ?? false

            HStack(spacing: 10) {
                Circle()
                    .fill(
                        store.connectionStatus == .connected ? Color.green :
                        (store.connectionStatus == .connecting ? Color.orange :
                         (pingInfo != nil ? Color.green :
                          (pingFailed ? Color.red : Color.secondary.opacity(0.4))))
                    )
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading, spacing: 1) {
                    Text(store.activeBookmark?.name ?? (targetBookmark?.name ?? "Not Connected"))
                        .font(.caption.bold())
                        .lineLimit(1)

                    if store.connectionStatus == .connected {
                        Text("\(store.users.count) user\(store.users.count == 1 ? "" : "s") online • \(Int(store.tcpPingMs)) ms")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else if store.connectionStatus == .connecting {
                        Text("Connecting...")
                            .font(.system(size: 10))
                            .foregroundStyle(.orange)
                    } else if let ping = pingInfo {
                        HStack(spacing: 4) {
                            Text("Online • \(Int(ping.latencyMs)) ms")
                                .font(.system(size: 10))
                                .foregroundStyle(.secondary)
                            if ping.maxUsers > 0 {
                                Text("(\(ping.currentUsers)/\(ping.maxUsers))")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    } else if pingFailed {
                        Text("Offline")
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    } else if targetBookmark != nil {
                        Text("Checking status...")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No servers added")
                            .font(.system(size: 10))
                            .foregroundStyle(.tertiary)
                    }
                }

                Spacer()

                if store.connectionStatus == .disconnected, let target = targetBookmark {
                    Button("Connect") {
                        store.connect(bookmark: target)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .tint(store.accentTint)
                }

                Button(action: { showConnectSheet = true }) {
                    Image(systemName: "server.rack")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
                .help("Manage Servers")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.5))
        }
        .navigationTitle(store.activeBookmark?.name ?? "Swimble")
        .task(id: "\(targetBookmark?.id.uuidString ?? "")-\(store.connectionStatus)") {
            if store.connectionStatus != .connected, let target = targetBookmark {
                await store.pingBookmark(target)
            }
        }
    }
}

/// Recursive disclosure row for a channel tree node.
struct ChannelTreeNodeView: View {
    @Bindable var store: MumbleStore
    let node: ChannelTreeNode
    @State private var isExpanded: Bool = true

    var body: some View {
        if node.children.isEmpty && node.users.isEmpty {
            ChannelRowView(store: store, channel: node.channel, userCount: store.totalUsers(in: node.id))
                .tag(node.channel.id)
        } else {
            DisclosureGroup(isExpanded: $isExpanded) {
                // Users in this channel (shown on top of all subchannels)
                ForEach(node.users, id: \.sessionId) { user in
                    UserRowView(store: store, user: user)
                        .selectionDisabled(true)
                }
                // Subchannels (shown below users)
                ForEach(node.children) { child in
                    ChannelTreeNodeView(store: store, node: child)
                }
            } label: {
                ChannelRowView(
                    store: store,
                    channel: node.channel,
                    userCount: store.totalUsers(in: node.id)
                )
                .tag(node.channel.id)
            }
        }
    }
}

/// Search result row for a channel.
struct SearchChannelRow: View {
    @Bindable var store: MumbleStore
    let channel: ChannelInfo

    @State private var showDescriptionPopover = false
    @State private var isPinnedOpen = false
    @State private var isHoveringRow = false
    @State private var isHoveringPopover = false
    @State private var hoverTask: Task<Void, Never>? = nil

    private var isJoined: Bool {
        store.myChannelId == channel.id
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

    var body: some View {
        HStack {
            Image(systemName: isJoined ? "speaker.wave.2.fill" : "folder.fill")
                .foregroundStyle(isJoined ? Color.green : Color.secondary)
            Text(channel.name)
                .bold(isJoined)
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

            let count = store.totalUsers(in: channel.id)
            if count > 0 && SettingsState.shared.alwaysShowChannelUserCount {
                Text("\(count)")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.secondary.opacity(0.15), in: Capsule())
                    .foregroundStyle(Color.primary)
            }

            if !isJoined {
                Button(isLocked ? "Locked" : "Join") {
                    if channel.canEnter {
                        store.joinChannel(channelId: channel.id)
                    } else {
                        store.logSystemMessage("Cannot enter \(channel.name): Channel is locked.", icon: "lock.fill")
                        SoundManager.shared.playPermissionDenied()
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLocked)
            }
        }
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
        .tag(channel.id)
    }
}
