import Foundation

/// Hierarchical channel node containing subchannels and active users.
public struct ChannelTreeNode: Identifiable, Hashable, Equatable, Sendable {
    public var id: UInt32 { channel.id }
    public let channel: ChannelInfo
    public var children: [ChannelTreeNode]
    public var users: [UserInfo]

    public init(channel: ChannelInfo, children: [ChannelTreeNode] = [], users: [UserInfo] = []) {
        self.channel = channel
        self.children = children
        self.users = users
    }

    /// Recursively constructs the hierarchical channel tree from flat channel and user lists.
    public static func buildTree(
        channels: [ChannelInfo],
        users: [UserInfo],
        userSort: UserSortMode = .alphabetically,
        filterHidesEmpty: Bool = false
    ) -> [ChannelTreeNode] {
        // Group users by channel_id
        var usersByChannel: [UInt32: [UserInfo]] = [:]
        for user in users {
            usersByChannel[user.channelId, default: []].append(user)
        }

        // Group channels by parent_id
        var childrenByParent: [UInt32: [ChannelInfo]] = [:]
        var rootChannels: [ChannelInfo] = []

        let channelIds = Set(channels.map { $0.id })

        for ch in channels {
            if let pid = ch.parentId, channelIds.contains(pid), pid != ch.id {
                childrenByParent[pid, default: []].append(ch)
            } else {
                rootChannels.append(ch)
            }
        }

        // Sort root channels by position then name
        rootChannels.sort {
            if $0.position != $1.position { return $0.position < $1.position }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }

        func buildNode(_ ch: ChannelInfo) -> ChannelTreeNode? {
            var subchannels = childrenByParent[ch.id] ?? []
            subchannels.sort {
                if $0.position != $1.position { return $0.position < $1.position }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
            let childNodes = subchannels.compactMap { buildNode($0) }
            var channelUsers = usersByChannel[ch.id] ?? []
            if userSort == .byId {
                channelUsers.sort { $0.sessionId < $1.sessionId }
            } else {
                channelUsers.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            }

            if filterHidesEmpty && channelUsers.isEmpty && childNodes.isEmpty && ch.parentId != nil {
                return nil
            }

            return ChannelTreeNode(channel: ch, children: childNodes, users: channelUsers)
        }

        return rootChannels.compactMap { buildNode($0) }
    }
}
