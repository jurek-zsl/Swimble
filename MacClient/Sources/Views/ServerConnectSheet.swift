import SwiftUI
import AppKit

public enum ServerConnectTab: String, CaseIterable, Identifiable {
    case saved = "Saved Servers"
    case publicList = "Public Servers (Mumist)"

    public var id: String { rawValue }
}

/// Sheet for managing server bookmarks and initiating server connections.
public struct ServerConnectSheet: View {
    @Bindable public var store: MumbleStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: ServerConnectTab = .saved
    @State private var selectedBookmarkId: UUID?
    @State private var isEditing: Bool = false

    // Form Fields
    @State private var formName: String = ""
    @State private var formHost: String = ""
    @State private var formPort: String = "64738"
    @State private var formUsername: String = ""
    @State private var formPassword: String = ""
    @State private var copiedFingerprint: Bool = false

    public init(store: MumbleStore) {
        self.store = store
    }

    private var selectedBookmark: ServerBookmark? {
        store.bookmarks.first(where: { $0.id == selectedBookmarkId })
    }

    private var favoriteBookmarks: [ServerBookmark] {
        store.bookmarks.filter { $0.isFavorite }
    }

    private var otherBookmarks: [ServerBookmark] {
        store.bookmarks.filter { !$0.isFavorite }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 16) {
                Text("Connect to Server")
                    .font(.title3.bold())

                Spacer()

                Picker("", selection: $selectedTab) {
                    Label("Saved Servers", systemImage: "star.fill")
                        .tag(ServerConnectTab.saved)
                    Label("Public Directory (Mumist)", systemImage: "globe")
                        .tag(ServerConnectTab.publicList)
                }
                .pickerStyle(.segmented)
                .frame(width: 330)

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()

            switch selectedTab {
            case .saved:
                savedBookmarksView
            case .publicList:
                MumistPublicServersView(store: store, onConnect: { dismiss() })
            }
        }
        .frame(minWidth: 760, idealWidth: 800, maxWidth: 880, minHeight: 520, idealHeight: 540)
        .onAppear {
            if selectedBookmarkId == nil {
                if let lastUsed = store.lastUsedBookmark {
                    selectBookmark(lastUsed)
                }
            }
            store.pingAllBookmarks()
        }
        .onChange(of: selectedBookmarkId) { _, newId in
            if let id = newId, let bm = store.bookmarks.first(where: { $0.id == id }) {
                loadForm(bm)
                Task {
                    await store.pingBookmark(bm)
                }
            }
        }
    }

    private var savedBookmarksView: some View {
        HStack(spacing: 0) {
                // Left Column: Saved Bookmarks List
                VStack(spacing: 0) {
                    List(selection: $selectedBookmarkId) {
                        if !favoriteBookmarks.isEmpty {
                            Section("Favorites") {
                                ForEach(favoriteBookmarks) { bookmark in
                                    BookmarkRow(bookmark: bookmark, store: store, onConnect: { dismiss() })
                                        .tag(bookmark.id)
                                }
                            }
                        }

                        if !otherBookmarks.isEmpty || favoriteBookmarks.isEmpty {
                            Section(favoriteBookmarks.isEmpty ? "Servers" : "Other Servers") {
                                ForEach(favoriteBookmarks.isEmpty ? store.bookmarks : otherBookmarks) { bookmark in
                                    BookmarkRow(bookmark: bookmark, store: store, onConnect: { dismiss() })
                                        .tag(bookmark.id)
                                }
                            }
                        }
                    }
                    .listStyle(.sidebar)

                    Divider()

                    // Bottom list toolbar (+ / duplicate / trash / refresh)
                    HStack(spacing: 8) {
                        Button(action: createNewBookmark) {
                            Image(systemName: "plus")
                        }
                        .help("Add New Server")

                        Button(action: duplicateSelectedBookmark) {
                            Image(systemName: "plus.square.on.square")
                        }
                        .disabled(selectedBookmark == nil)
                        .help("Duplicate Selected Server")

                        Button(action: deleteSelectedBookmark) {
                            Image(systemName: "trash")
                        }
                        .disabled(selectedBookmark == nil)
                        .help("Delete Selected Server")

                        Spacer()

                        Button(action: {
                            store.pingAllBookmarks()
                        }) {
                            Image(systemName: "arrow.clockwise")
                        }
                        .disabled(store.isPingingServers)
                        .help("Refresh Server Status")
                    }
                    .padding(8)
                }
                .frame(width: 220)

                Divider()

                // Right Column: Server Details Form & Certificate Info
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        HStack {
                            Text("Server Details")
                                .font(.headline)
                            Spacer()
                            if let bm = selectedBookmark {
                                Button(action: {
                                    store.toggleFavoriteBookmark(bm)
                                }) {
                                    Label(bm.isFavorite ? "Favorited" : "Favorite", systemImage: bm.isFavorite ? "star.fill" : "star")
                                        .font(.caption)
                                        .foregroundStyle(bm.isFavorite ? Color.yellow : Color.secondary)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }

                        if let bm = selectedBookmark {
                            let pingKey = store.pingKey(for: bm)
                            let pingInfo = store.serverPingResults[pingKey]
                            let pingFailed = store.serverPingFailed[pingKey] ?? false
                            let isCurrent = store.connectionStatus == .connected &&
                                (store.activeBookmark?.id == bm.id ||
                                 (store.activeBookmark?.host.lowercased() == bm.host.lowercased() &&
                                  store.activeBookmark?.port == bm.port))

                            HStack(spacing: 10) {
                                Circle()
                                    .fill(
                                        isCurrent ? Color.green :
                                        (pingInfo != nil ? Color.green :
                                         (pingFailed ? Color.red : Color.orange.opacity(0.8)))
                                    )
                                    .frame(width: 10, height: 10)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        if isCurrent {
                                            Text("Currently Connected")
                                                .font(.subheadline.bold())
                                                .foregroundStyle(.green)
                                            Text("• \(Int(store.tcpPingMs)) ms")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                            Text("(\(store.users.count) user\(store.users.count == 1 ? "" : "s"))")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else if let ping = pingInfo {
                                            Text("Server Online")
                                                .font(.subheadline.bold())
                                                .foregroundStyle(.green)
                                            Text("• \(Int(ping.latencyMs)) ms")
                                                .font(.caption.bold())
                                                .foregroundStyle(.green)
                                            if ping.maxUsers > 0 {
                                                Text("(\(ping.currentUsers)/\(ping.maxUsers) users)")
                                                    .font(.caption)
                                                    .foregroundStyle(.secondary)
                                            }
                                            if !ping.version.isEmpty {
                                                Text("[\(ping.version)]")
                                                    .font(.caption2)
                                                    .foregroundStyle(.secondary)
                                            }
                                        } else if pingFailed {
                                            Text("Server Offline / Unreachable")
                                                .font(.subheadline.bold())
                                                .foregroundStyle(.red)
                                        } else {
                                            Text("Checking server status...")
                                                .font(.subheadline)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }

                                Spacer()

                                Button(action: {
                                    Task {
                                        await store.pingBookmark(bm)
                                    }
                                }) {
                                    Label("Check Status", systemImage: "arrow.clockwise")
                                        .font(.caption2)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .help("Test reachability and update ping")
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                        }

                        // Form Fields
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 12) {
                            GridRow {
                                Text("Name:")
                                    .foregroundStyle(.secondary)
                                TextField("e.g. Local Murmur", text: $formName)
                                    .textFieldStyle(.roundedBorder)
                            }

                            GridRow {
                                Text("Host:")
                                    .foregroundStyle(.secondary)
                                TextField("127.0.0.1", text: $formHost)
                                    .textFieldStyle(.roundedBorder)
                            }

                            GridRow {
                                Text("Port:")
                                    .foregroundStyle(.secondary)
                                TextField("64738", text: $formPort)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 100)
                            }

                            GridRow {
                                Text("Username:")
                                    .foregroundStyle(.secondary)
                                TextField("Nickname", text: $formUsername)
                                    .textFieldStyle(.roundedBorder)
                            }

                            GridRow {
                                Text("Password:")
                                    .foregroundStyle(.secondary)
                                SecureField("Optional", text: $formPassword)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        if formHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                           formUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Server host and username are required to connect.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }

                        HStack {
                            Button("Save Changes") {
                                saveCurrentForm()
                            }
                            .buttonStyle(.bordered)
                            .disabled(selectedBookmark == nil)

                            Spacer()

                            Button("Connect") {
                                connectToCurrent()
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(store.accentTint)
                            .keyboardShortcut(.defaultAction)
                            .disabled(formHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                                      formUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }

                        Divider()

                        // Client Certificate Info
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Client X.509 Certificate")
                                    .font(.subheadline.bold())
                                Spacer()
                                Button(copiedFingerprint ? "Copied!" : "Copy Fingerprint") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.setString(store.certFingerprint, forType: .string)
                                    copiedFingerprint = true
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                        copiedFingerprint = false
                                    }
                                }
                                .font(.caption)
                                .buttonStyle(.bordered)
                            }

                            Text("SHA-1 Fingerprint:")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(store.certFingerprint)
                                .font(.system(.caption, design: .monospaced))
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
                                .textSelection(.enabled)

                            Text("Your certificate is securely persisted in the macOS Keychain and authenticates you on Murmur servers without passwords.")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .padding(24)
                }
            }
        }

    private func selectBookmark(_ bm: ServerBookmark) {
        selectedBookmarkId = bm.id
        loadForm(bm)
        Task {
            await store.pingBookmark(bm)
        }
    }

    private func loadForm(_ bm: ServerBookmark) {
        formName = bm.name
        formHost = bm.host
        formPort = "\(bm.port)"
        formUsername = bm.username
        formPassword = bm.password ?? KeychainHelper.loadServerPassword(bookmarkId: bm.id) ?? ""
    }

    private func saveCurrentForm() {
        guard let id = selectedBookmarkId,
              let idx = store.bookmarks.firstIndex(where: { $0.id == id }) else { return }

        let port = UInt16(formPort) ?? 64738
        var updated = store.bookmarks[idx]
        updated.name = formName
        updated.host = formHost
        updated.port = port
        updated.username = formUsername
        updated.password = formPassword.isEmpty ? nil : formPassword

        store.saveBookmark(updated)
        Task {
            await store.pingBookmark(updated)
        }
    }

    private func createNewBookmark() {
        let newBm = ServerBookmark(
            name: "New Server",
            host: "127.0.0.1",
            port: 64738,
            username: "User"
        )
        store.addBookmark(newBm)
        selectBookmark(newBm)
    }

    private func duplicateSelectedBookmark() {
        guard let bm = selectedBookmark else { return }
        let copy = ServerBookmark(
            id: UUID(),
            name: "\(bm.name) (Copy)",
            host: bm.host,
            port: bm.port,
            username: bm.username,
            password: bm.password,
            isFavorite: false
        )
        store.addBookmark(copy)
        selectBookmark(copy)
    }

    private func deleteSelectedBookmark() {
        guard let bm = selectedBookmark else { return }
        store.deleteBookmark(bm)
        if let next = store.bookmarks.first {
            selectBookmark(next)
        } else {
            selectedBookmarkId = nil
        }
    }

    private func connectToCurrent() {
        saveCurrentForm()
        if let bm = selectedBookmark {
            store.connect(bookmark: bm)
            dismiss()
        }
    }
}

struct BookmarkRow: View {
    let bookmark: ServerBookmark
    @Bindable var store: MumbleStore
    var onConnect: (() -> Void)? = nil

    private var pingKey: String {
        store.pingKey(for: bookmark)
    }

    private var pingInfo: ServerPingInfo? {
        store.serverPingResults[pingKey]
    }

    private var pingFailed: Bool {
        store.serverPingFailed[pingKey] ?? false
    }

    private var isCurrentlyConnected: Bool {
        store.connectionStatus == .connected &&
        (store.activeBookmark?.id == bookmark.id ||
         (store.activeBookmark?.host.lowercased() == bookmark.host.lowercased() &&
          store.activeBookmark?.port == bookmark.port))
    }

    var body: some View {
        HStack {
            Image(systemName: "server.rack")
                .foregroundStyle(store.accentTint)

            VStack(alignment: .leading, spacing: 2) {
                Text(bookmark.name)
                    .font(.body.bold())
                HStack(spacing: 6) {
                    Text("\(bookmark.host):\(bookmark.port)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)

                    if isCurrentlyConnected {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Connected")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                        Text("\(Int(store.tcpPingMs)) ms")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Text("(\(store.users.count) user\(store.users.count == 1 ? "" : "s"))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    } else if let ping = pingInfo {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("\(Int(ping.latencyMs)) ms")
                            .font(.caption2.bold())
                            .foregroundStyle(.green)
                        if ping.maxUsers > 0 {
                            Text("(\(ping.currentUsers)/\(ping.maxUsers))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("(Online)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    } else if pingFailed {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Offline")
                            .font(.caption2)
                            .foregroundStyle(.red)
                    } else {
                        Text("•")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                        Text("Checking...")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            Button(action: {
                store.toggleFavoriteBookmark(bookmark)
            }) {
                Image(systemName: bookmark.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(bookmark.isFavorite ? Color.yellow : Color.secondary)
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                store.connect(bookmark: bookmark)
                onConnect?()
            }
        )
        .task(id: "\(pingKey)-\(isCurrentlyConnected)") {
            if isCurrentlyConnected { return }
            await store.pingBookmark(bookmark)
        }
    }
}
