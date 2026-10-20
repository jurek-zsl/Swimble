import SwiftUI

struct EditChannelModal: View {
    @Bindable var store: MumbleStore
    let channel: ChannelInfo
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var parent: UInt32
    @State private var position: Int
    @State private var capacity: Int
    init(store: MumbleStore, channel: ChannelInfo) {
        self.store = store; self.channel = channel
        _name = State(initialValue: channel.name); _parent = State(initialValue: channel.parentId ?? 0)
        _position = State(initialValue: Int(channel.position)); _capacity = State(initialValue: Int(channel.maxUsers))
    }
    private var possibleParents: [ChannelInfo] {
        store.channels.filter { candidate in
            var cursor: UInt32? = candidate.id
            var visited = Set<UInt32>()
            while let id = cursor, visited.insert(id).inserted {
                if id == channel.id { return false }
                cursor = store.channels.first { $0.id == id }?.parentId
            }
            return true
        }
    }
    var body: some View {
        Form {
            Text("Edit Channel").font(.title2.bold())
            TextField("Name", text: $name).disabled(channel.id == 0)
            if channel.id != 0 { Picker("Parent", selection: $parent) { ForEach(possibleParents, id: \.id) { Text($0.name).tag($0.id) } } }
            TextField("Sort position", value: $position, format: .number)
            TextField("User limit (0 uses server default)", value: $capacity, format: .number)
            HStack {
                Button("Cancel") { dismiss() }
                Spacer()
                Button("Apply to Server") {
                    store.client.editChannel(channelId: channel.id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), parent: channel.id == 0 ? nil : parent,
                                             position: Int32(clamping: position), maxUsers: UInt32(clamping: max(0, capacity)))
                    dismiss()
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 440)
    }
}
