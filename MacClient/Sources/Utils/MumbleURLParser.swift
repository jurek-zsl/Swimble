import Foundation

/// Structured representation of a parsed `mumble://` URL link.
public struct MumbleLinkInfo: Equatable, Sendable {
    public var host: String
    public var port: UInt16
    public var username: String?
    public var password: String?
    public var channelPath: [String]
    public var title: String?
    public var version: String?
    public var originalURL: URL

    public init(
        host: String,
        port: UInt16 = 64738,
        username: String? = nil,
        password: String? = nil,
        channelPath: [String] = [],
        title: String? = nil,
        version: String? = nil,
        originalURL: URL
    ) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.channelPath = channelPath
        self.title = title
        self.version = version
        self.originalURL = originalURL
    }

    /// Converts this link info into a `ServerBookmark` instance.
    public func makeBookmark(fallbackUsername: String = "User") -> ServerBookmark {
        let bookmarkName: String
        if let t = title?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty {
            bookmarkName = t
        } else if port == 64738 {
            bookmarkName = host
        } else {
            bookmarkName = "\(host):\(port)"
        }

        let effectiveUser: String
        if let u = username?.trimmingCharacters(in: .whitespacesAndNewlines), !u.isEmpty {
            effectiveUser = u
        } else {
            effectiveUser = fallbackUsername
        }

        return ServerBookmark(
            name: bookmarkName,
            host: host,
            port: port,
            username: effectiveUser,
            password: password,
            isFavorite: false
        )
    }
}

/// Robust parser for standard Mumble protocol URLs (`mumble://...`).
/// Format: `mumble://[username[:password]@]host[:port][/channel/subchannel][?version=1.2.0][&title=ServerTitle]`
public enum MumbleURLParser {
    /// Attempts to parse a raw string representing a Mumble URL.
    public static func parse(string: String) -> MumbleLinkInfo? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let directURL = URL(string: trimmed), directURL.scheme?.lowercased() == "mumble" {
            return parse(url: directURL)
        }

        // Try encoding raw spaces / unicode if URL(string:) failed on unencoded characters
        if let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed.union(.urlQueryAllowed).union(.urlPathAllowed)),
           let fallbackURL = URL(string: encoded),
           fallbackURL.scheme?.lowercased() == "mumble" {
            return parse(url: fallbackURL)
        }

        return nil
    }

    /// Parses an existing `URL` with scheme `mumble://`.
    public static func parse(url: URL) -> MumbleLinkInfo? {
        guard let scheme = url.scheme?.lowercased(), scheme == "mumble" else {
            return nil
        }

        guard let comps = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }

        guard let host = comps.host, !host.isEmpty else {
            return nil
        }

        let rawPort = comps.port ?? 64738
        guard (1...65535).contains(rawPort), let port = UInt16(exactly: rawPort) else { return nil }

        // Query parameters parsing
        var queryUsername: String?
        var queryPassword: String?
        var queryTitle: String?
        var queryVersion: String?

        for item in comps.queryItems ?? [] {
            let key = item.name.lowercased()
            let val = sanitizeQueryValue(item.value)
            switch key {
            case "title":
                queryTitle = val
            case "version":
                queryVersion = val
            case "username", "user":
                queryUsername = val
            case "password", "pass":
                queryPassword = val
            default:
                break
            }
        }

        let username = (comps.user?.removingPercentEncoding ?? comps.user) ?? queryUsername
        let password = (comps.password?.removingPercentEncoding ?? comps.password) ?? queryPassword

        // Extract channel path components, e.g. /Lobby/Gaming -> ["Lobby", "Gaming"]
        let channelPath = comps.path
            .split(separator: "/")
            .map { String($0) }
            .compactMap { $0.removingPercentEncoding ?? $0 }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        return MumbleLinkInfo(
            host: host,
            port: port,
            username: username,
            password: password,
            channelPath: channelPath,
            title: queryTitle,
            version: queryVersion,
            originalURL: url
        )
    }

    private static func sanitizeQueryValue(_ raw: String?) -> String? {
        guard let raw = raw else { return nil }
        let withSpaces = raw.replacingOccurrences(of: "+", with: " ")
        return withSpaces.removingPercentEncoding ?? withSpaces
    }
}
