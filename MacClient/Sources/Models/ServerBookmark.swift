import Foundation

/// Saved server connection bookmark.
public struct ServerBookmark: Identifiable, Codable, Hashable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var host: String
    public var port: UInt16
    public var username: String
    public var password: String?
    public var isFavorite: Bool

    public init(
        id: UUID = UUID(),
        name: String,
        host: String,
        port: UInt16 = 64738,
        username: String,
        password: String? = nil,
        isFavorite: Bool = false
    ) {
        self.id = id
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.isFavorite = isFavorite
    }

    private enum CodingKeys: String, CodingKey { case id, name, host, port, username, password, isFavorite }
    // Decode old bookmarks for migration; never serialize credentials again.
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id); try c.encode(name, forKey: .name)
        try c.encode(host, forKey: .host); try c.encode(port, forKey: .port)
        try c.encode(username, forKey: .username); try c.encode(isFavorite, forKey: .isFavorite)
    }
}
