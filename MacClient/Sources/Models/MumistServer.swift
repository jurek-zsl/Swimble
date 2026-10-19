import Foundation

/// Public Mumble server record retrieved from Mumist (https://mumist.eu).
public struct MumistServer: Identifiable, Codable, Equatable, Hashable, Sendable {
    public var id: String { key ?? "\(effectiveHost):\(effectivePort)" }

    public let name: String
    public let url: String?
    public let ip: String?
    public let host: String?
    public let port: Int?
    public let region: String?
    public let country: String?
    public let country_code: String?
    public let continent_code: String?
    public let users: Int?
    public let max: Int?
    public let ok: Int?
    public let last_seen: Int64?
    public let listed_at: Int64?
    public let version: String?
    public let key: String?
    public let uptime_7d: Double?
    public let peak_24h: Int?

    public init(
        name: String,
        url: String? = nil,
        ip: String? = nil,
        host: String? = nil,
        port: Int? = 64738,
        region: String? = nil,
        country: String? = nil,
        country_code: String? = nil,
        continent_code: String? = nil,
        users: Int? = 0,
        max: Int? = 0,
        ok: Int? = 1,
        last_seen: Int64? = nil,
        listed_at: Int64? = nil,
        version: String? = nil,
        key: String? = nil,
        uptime_7d: Double? = nil,
        peak_24h: Int? = nil
    ) {
        self.name = name
        self.url = url
        self.ip = ip
        self.host = host
        self.port = port
        self.region = region
        self.country = country
        self.country_code = country_code
        self.continent_code = continent_code
        self.users = users
        self.max = max
        self.ok = ok
        self.last_seen = last_seen
        self.listed_at = listed_at
        self.version = version
        self.key = key
        self.uptime_7d = uptime_7d
        self.peak_24h = peak_24h
    }

    public var effectiveHost: String {
        if let h = host, !h.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return h.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let i = ip, !i.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return i.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return "127.0.0.1"
    }

    public var effectivePort: UInt16 {
        UInt16(port ?? 64738)
    }

    public var displayAddress: String {
        effectivePort == 64738 ? effectiveHost : "\(effectiveHost):\(effectivePort)"
    }

    public var isAnswering: Bool {
        ok == 1
    }

    public var onlineUsersCount: Int {
        users ?? 0
    }

    public var maxUsersCount: Int {
        max ?? 0
    }

    public var fillRatio: Double {
        guard let max = max, max > 0, let users = users else { return 0 }
        return Swift.min(1.0, Swift.max(0.0, Double(users) / Double(max)))
    }

    public var uptimePercentage: Double? {
        guard let u = uptime_7d else { return nil }
        return Swift.min(100.0, Swift.max(0.0, u * 100.0))
    }

    public var flagEmoji: String {
        guard let cc = country_code, cc.count == 2 else { return "🌐" }
        let base: UInt32 = 127397
        var s = ""
        for scalar in cc.uppercased().unicodeScalars {
            if let sc = UnicodeScalar(base + scalar.value) {
                s.append(String(sc))
            }
        }
        return s.isEmpty ? "🌐" : s
    }

    public var locationDisplay: String {
        let parts = [region, country].compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if parts.isEmpty {
            return "Unknown Location"
        }
        return parts.joined(separator: ", ")
    }

    public var continentName: String {
        switch continent_code?.uppercased() {
        case "EU": return "Europe"
        case "NA": return "North America"
        case "AS": return "Asia"
        case "SA": return "South America"
        case "OC": return "Oceania"
        case "AF": return "Africa"
        default: return "Other"
        }
    }

    public var mumbleURL: URL? {
        let scheme = "mumble://"
        let hostPart = effectiveHost.contains(":") && !effectiveHost.hasPrefix("[")
            ? "[\(effectiveHost)]"
            : effectiveHost
        return URL(string: "\(scheme)\(hostPart):\(effectivePort)/")
    }

    public func toBookmark(defaultUsername: String = "User") -> ServerBookmark {
        ServerBookmark(
            id: UUID(),
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? displayAddress : name,
            host: effectiveHost,
            port: effectivePort,
            username: defaultUsername,
            password: nil,
            isFavorite: false
        )
    }
}

/// A historical user count measurement point for a public server.
public struct MumistHistoryPoint: Identifiable, Codable, Equatable, Sendable {
    public var id: Int64 { timestamp }
    public let timestamp: Int64
    public let users: Int
    public let ok: Int?

    public var date: Date {
        Date(timeIntervalSince1970: TimeInterval(timestamp) / 1000.0)
    }
}

/// JSON response envelope from `https://mumist.eu/api/stats`.
public struct MumistStatsResponse: Codable, Sendable {
    public let ok: Bool
    public let count: Int
    public let lastUpdated: Int64?
    public let results: [MumistServer]
}

/// JSON response envelope from `https://mumist.eu/api/servers/{key}/history`.
public struct MumistHistoryResponse: Codable, Sendable {
    public let ok: Bool
    public let key: String?
    public let range: String?
    public let history: [MumistHistoryPoint]?
}
