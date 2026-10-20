import SwiftUI

private let channelPermissions: [(UInt32, String)] = [
    (0x1, "Write ACL"), (0x2, "Traverse"), (0x4, "Enter"), (0x8, "Speak"),
    (0x10, "Mute / Deafen"), (0x20, "Move Users"), (0x40, "Create Channels"),
    (0x80, "Link Channels"), (0x100, "Whisper"), (0x200, "Send Text"),
    (0x400, "Create Temporary Channels"), (0x800, "Listen"),
    (0x10000, "Kick"), (0x20000, "Ban"), (0x40000, "Register Users"),
    (0x80000, "Register Self"), (0x100000, "Reset User Content")
]

struct ChannelPrivilegesModal: View {
    @Bindable var store: MumbleStore
    let channel: ChannelInfo
    @Environment(\.dismiss) private var dismiss
    @State private var draft: ChannelAcl?
    @State private var selectedEntry: Int?
    @State private var groupName = "all"
    @State private var userId = ""
    @State private var targetsUser = false
    @State private var newGroupName = ""
    @State private var status = ""
    @State private var membershipText: [String: String] = [:]

    private var canWrite: Bool { store.canEditChannelPrivileges(in: channel.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Channel Privileges · \(channel.name)").font(.title2.bold())
            Text("Murmur applies these rules to every client. User rules and group members use registered user IDs, tied to each user's certificate identity.")
                .font(.caption).foregroundStyle(.secondary)
            if let acl = draft {
                Toggle("Inherit parent channel ACLs", isOn: Binding(
                    get: { draft?.inheritAcls ?? true }, set: { draft?.inheritAcls = $0 }
                )).disabled(!canWrite)
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading) {
                        Text("Rules (evaluated in order)").font(.headline)
                        List(selection: $selectedEntry) {
                            ForEach(acl.entries.indices, id: \.self) { index in
                                let entry = acl.entries[index]
                                Text("\(entry.inherited ? "Inherited · " : "")\(targetName(entry))")
                                    .tag(index)
                            }
                        }.frame(width: 240, height: 290)
                        HStack {
                            Button("Move Up") { moveEntry(-1) }.disabled(!editableSelection || selectedEntry == 0)
                            Button("Move Down") { moveEntry(1) }.disabled(!editableSelection || selectedEntry == acl.entries.count - 1)
                            Button("Remove", role: .destructive) {
                                if let index = selectedEntry { draft?.entries.remove(at: index); selectedEntry = nil }
                            }.disabled(!editableSelection)
                        }
                    }
                    if let index = selectedEntry, acl.entries.indices.contains(index) {
                        VStack(alignment: .leading, spacing: 8) {
                            Toggle("Apply to this channel", isOn: entryBool(index, \.applyHere))
                            Toggle("Apply to subchannels", isOn: entryBool(index, \.applySubs))
                            ScrollView {
                                ForEach(channelPermissions.filter { channel.id == 0 || $0.0 < 0x10000 }, id: \.0) { bit, name in
                                    HStack {
                                        Text(name).frame(maxWidth: .infinity, alignment: .leading)
                                        Picker(name, selection: permissionBinding(index, bit)) {
                                            Text("Inherit").tag(0)
                                            Text("Allow").tag(1)
                                            Text("Deny").tag(2)
                                        }.labelsHidden().frame(width: 110)
                                    }
                                }
                            }.frame(height: 265)
                        }.disabled(!editableSelection)
                    } else {
                        ContentUnavailableView("Select a Rule", systemImage: "person.badge.shield.checkmark")
                            .frame(maxWidth: .infinity, minHeight: 290)
                    }
                }
                HStack {
                    Toggle("Registered user", isOn: $targetsUser).toggleStyle(.checkbox)
                    if targetsUser {
                        TextField("Registered user ID", text: $userId).frame(width: 130)
                        Menu("Choose User") {
                            ForEach(store.registeredUsers, id: \.userId) { user in
                                Button("\(user.name) (#\(user.userId))") { userId = String(user.userId) }
                            }
                            ForEach(store.users.filter { $0.userId != nil }, id: \.sessionId) { user in
                                Button("\(user.name) (#\(user.userId!))") { userId = String(user.userId!) }
                            }
                        }
                    } else {
                        TextField("Group (all, auth, admin, @token…)", text: $groupName)
                    }
                    Button("Add Rule") { addRule() }
                        .disabled(targetsUser ? UInt32(userId) == nil : groupName.trimmingCharacters(in: .whitespaces).isEmpty)
                }.disabled(!canWrite)
                DisclosureGroup("Groups and Registered Members") {
                    ScrollView {
                        ForEach(acl.groups.indices, id: \.self) { index in
                            groupEditor(index, acl.groups[index])
                        }
                    }.frame(maxHeight: 150)
                    HStack {
                        TextField("New group name", text: $newGroupName)
                        Button("Add Group") {
                            let name = newGroupName.trimmingCharacters(in: .whitespaces)
                            guard !name.isEmpty, draft?.groups.contains(where: { $0.name == name }) == false else { return }
                            draft?.groups.append(ChannelAclGroup(name: name, inherited: false, inherit: true, inheritable: true, add: [], remove: [], inheritedMembers: []))
                            newGroupName = ""
                        }
                    }.disabled(!canWrite)
                }
            } else {
                ProgressView("Requesting channel ACL from Murmur…").frame(maxWidth: .infinity, minHeight: 250)
                Text("If access is denied, the server will report it in chat. ACL access requires Write ACL permission.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            if hasInvalidMembership {
                Text("Group members must be registered user IDs separated by commas.")
                    .font(.caption).foregroundStyle(.red)
            }
            if !status.isEmpty { Text(status).font(.caption).foregroundStyle(.secondary) }
            HStack {
                Button("Done") { dismiss() }
                Spacer()
                Button("Reload") { store.requestChannelAcl(channelId: channel.id) }
                Button("Apply to Server") {
                    if let draft { store.client.setChannelAcl(acl: draft); status = "Sent to Murmur. Waiting for the server's ACL response…" }
                }.disabled(!canWrite || draft == nil || hasInvalidMembership)
            }
        }
        .padding(24).frame(width: 800)
        .onAppear { store.requestChannelAcl(channelId: channel.id) }
        .onChange(of: store.channelAcl) { _, acl in
            guard acl?.channelId == channel.id else { return }
            draft = acl; selectedEntry = nil; membershipText.removeAll()
            status = "Channel ACL received from Murmur."
        }
        .onDisappear { store.aclChannelId = nil }
    }

    private var editableSelection: Bool {
        guard canWrite, let index = selectedEntry, let draft, draft.entries.indices.contains(index) else { return false }
        return !draft.entries[index].inherited
    }
    private func targetName(_ entry: ChannelAclEntry) -> String {
        if let id = entry.userId {
            let name = store.registeredUsers.first { $0.userId == id }?.name ?? store.users.first { $0.userId == id }?.name
            return "\(name ?? "User") (#\(id))"
        }
        return "Group: \(entry.group ?? "all")"
    }
    private func addRule() {
        draft?.entries.append(ChannelAclEntry(applyHere: true, applySubs: true, inherited: false,
            userId: targetsUser ? UInt32(userId) : nil,
            group: targetsUser ? nil : groupName.trimmingCharacters(in: .whitespaces), grant: 0, deny: 0))
        selectedEntry = (draft?.entries.count ?? 1) - 1
    }
    private func moveEntry(_ offset: Int) {
        guard let index = selectedEntry, let draft else { return }
        let destination = index + offset
        guard draft.entries.indices.contains(destination), !draft.entries[destination].inherited else { return }
        self.draft?.entries.swapAt(index, destination); selectedEntry = destination
    }
    private func entryBool(_ index: Int, _ key: WritableKeyPath<ChannelAclEntry, Bool>) -> Binding<Bool> {
        Binding(get: { draft?.entries[index][keyPath: key] ?? false }, set: { draft?.entries[index][keyPath: key] = $0 })
    }
    private func permissionBinding(_ index: Int, _ bit: UInt32) -> Binding<Int> {
        Binding(get: {
            guard let entry = draft?.entries[index] else { return 0 }
            return entry.deny & bit != 0 ? 2 : (entry.grant & bit != 0 ? 1 : 0)
        }, set: { value in
            draft?.entries[index].grant &= ~bit; draft?.entries[index].deny &= ~bit
            if value == 1 { draft?.entries[index].grant |= bit }
            if value == 2 { draft?.entries[index].deny |= bit }
        })
    }
    private var hasInvalidMembership: Bool {
        membershipText.values.contains { value in
            value.split(separator: ",").contains { UInt32($0.trimmingCharacters(in: .whitespaces)) == nil }
        }
    }

    private func idsBinding(_ index: Int, _ key: WritableKeyPath<ChannelAclGroup, [UInt32]>) -> Binding<String> {
        let field = "\(index)-\(key == \ChannelAclGroup.add ? "add" : "remove")"
        return Binding(get: {
            membershipText[field] ?? (draft?.groups[index][keyPath: key] ?? []).map(String.init).joined(separator: ", ")
        }, set: { text in
            membershipText[field] = text
            let parts = text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.allSatisfy({ UInt32($0) != nil }) else { return }
            draft?.groups[index][keyPath: key] = parts.compactMap(UInt32.init)
        })
    }
    private func groupEditor(_ index: Int, _ group: ChannelAclGroup) -> some View {
        VStack(alignment: .leading) {
            Text("\(group.name)\(group.inherited ? " · inherited" : "")").bold()
            HStack {
                Toggle("Inherit members", isOn: Binding(get: { draft?.groups[index].inherit ?? true }, set: { draft?.groups[index].inherit = $0 }))
                Toggle("Inheritable", isOn: Binding(get: { draft?.groups[index].inheritable ?? true }, set: { draft?.groups[index].inheritable = $0 }))
            }
            TextField("Add registered IDs (comma separated)", text: idsBinding(index, \.add))
            TextField("Remove registered IDs (comma separated)", text: idsBinding(index, \.remove))
            if !group.inheritedMembers.isEmpty { Text("Inherited IDs: \(group.inheritedMembers.map(String.init).joined(separator: ", "))").font(.caption) }
        }.disabled(!canWrite)
    }
}
