import SwiftUI

/// Registered Users management dialog displaying registered accounts on the server.
public struct RegisteredUsersModal: View {
    @Bindable public var store: MumbleStore
    @Environment(\.dismiss) private var dismiss
    @State private var searchText: String = ""
    @State private var userToUnregister: RegisteredUser? = nil
    @State private var showConfirmUnregister: Bool = false

    public init(store: MumbleStore) {
        self.store = store
    }

    private var myUserId: UInt32? {
        guard let mySession = store.mySessionId,
              let me = store.users.first(where: { $0.sessionId == mySession }) else {
            return nil
        }
        return me.userId
    }

    private var registeredUsers: [RegisteredUser] {
        if searchText.isEmpty {
            return store.registeredUsers
        }
        return store.registeredUsers.filter { user in
            user.name.localizedCaseInsensitiveContains(searchText) ||
            "\(user.userId)".contains(searchText)
        }
    }

    private var isMeRegistered: Bool {
        store.isSelfRegistered
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "person.crop.circle.badge.checkmark")
                        .font(.title2)
                        .foregroundStyle(store.accentTint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Registered Users")
                            .font(.headline.bold())
                        Text("All user accounts permanently registered on this server database.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    store.requestRegisteredUsers()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh registered users list")

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))

            Divider()

            VStack(spacing: 14) {
                // Self registration banner
                HStack(spacing: 12) {
                    Image(systemName: isMeRegistered ? "checkmark.seal.fill" : "person.badge.plus")
                        .font(.title2)
                        .foregroundStyle(isMeRegistered ? .green : store.accentTint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(isMeRegistered ? "You are registered on this server" : "Your nickname is not yet registered")
                            .font(.subheadline.bold())
                        Text(isMeRegistered ? "Your username is permanently secured by your client certificate." : "Register your name so nobody else can take it on this server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !isMeRegistered {
                        Button("Register Myself") {
                            store.registerUser()
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(store.accentTint)
                        .disabled(store.connectionStatus != .connected)
                    } else {
                        Text("REGISTERED")
                            .font(.system(size: 10, weight: .bold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.15), in: Capsule())
                            .foregroundStyle(.green)
                    }
                }
                .padding(12)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(isMeRegistered ? Color.green.opacity(0.2) : store.accentTint.opacity(0.2), lineWidth: 0.8)
                }

                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("Filter registered users by name or ID...", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                // Users Count Banner
                HStack {
                    Text("\(registeredUsers.count) Registered Account\(registeredUsers.count == 1 ? "" : "s")")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                // Users Table
                if registeredUsers.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "person.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary.opacity(0.4))
                            .padding(.top, 32)
                        Text("No Registered Users Found")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)
                        Text(searchText.isEmpty ? "The server has no registered user accounts, or query is pending." : "No accounts matched '\(searchText)'.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(registeredUsers) { user in
                            let onlineUser = store.users.first(where: { $0.userId == user.userId })
                            let isMe = (myUserId != nil && user.userId == myUserId)

                            HStack(spacing: 12) {
                                Circle()
                                    .fill(onlineUser != nil ? Color.green : Color.secondary.opacity(0.4))
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 2) {
                                    HStack(spacing: 6) {
                                        Text(user.name)
                                            .font(.subheadline.bold())

                                        if isMe {
                                            Text("YOU")
                                                .font(.system(size: 9, weight: .heavy))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(store.accentTint.opacity(0.18), in: Capsule())
                                                .foregroundStyle(store.accentTint)
                                        }

                                        if onlineUser != nil {
                                            Text("ONLINE")
                                                .font(.system(size: 9, weight: .bold))
                                                .padding(.horizontal, 5)
                                                .padding(.vertical, 1)
                                                .background(Color.green.opacity(0.18), in: Capsule())
                                                .foregroundStyle(.green)
                                        }
                                    }

                                    HStack(spacing: 6) {
                                        Text("ID: #\(user.userId)")
                                            .font(.caption2.monospaced())
                                            .foregroundStyle(.secondary)

                                        if let online = onlineUser {
                                            Text("• In: \(store.channelName(for: online.channelId))")
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        } else if let lastSeen = user.lastSeen, !lastSeen.isEmpty {
                                            Text("• Last seen: \(formatLastSeen(lastSeen))")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }

                                Spacer()

                                if !isMe {
                                    Button(role: .destructive) {
                                        userToUnregister = user
                                        showConfirmUnregister = true
                                    } label: {
                                        Image(systemName: "trash")
                                            .foregroundStyle(.red.opacity(0.8))
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Unregister user from server")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.inset)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 540, height: 520)
        .onAppear {
            store.requestRegisteredUsers()
        }
        .confirmationDialog(
            "Unregister User",
            isPresented: $showConfirmUnregister,
            presenting: userToUnregister
        ) { target in
            Button("Unregister '\(target.name)'", role: .destructive) {
                store.removeRegisteredUser(userId: target.userId)
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("Are you sure you want to remove the registration for '\(target.name)' (ID: #\(target.userId))? This will delete their account credentials on the server.")
        }
    }

    private func formatLastSeen(_ raw: String) -> String {
        // Formats ISO date "2026-10-16T12:00:00" to a friendly readable format
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: raw) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: raw) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return raw.prefix(10).description
    }
}
