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

    /// Pre-configured bookmark for the local Docker Murmur test server.
    public static let localDefault = ServerBookmark(
        id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!,
        name: "Local Murmur (Docker)",
        host: "127.0.0.1",
        port: 64738,
        username: "AntigravityTester",
        password: nil,
        isFavorite: true
    )
}
