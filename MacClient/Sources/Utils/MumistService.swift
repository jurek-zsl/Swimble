import Foundation
import Observation

public enum DirectorySource: String, Sendable {
    case mumist = "Mumist.eu"
    case publist = "Mumble.info"
}

/// Service for fetching public Mumble server directory data from Mumist (https://mumist.eu),
/// with automatic fallback to the official directory (https://publist.mumble.info/v1/list).
@Observable
@MainActor
public final class MumistService {
    public static let shared = MumistService()

    public private(set) var servers: [MumistServer] = []
    public private(set) var directorySource: DirectorySource = .mumist
    public private(set) var isLoading: Bool = false
    public private(set) var lastFetchDate: Date? = nil
    public private(set) var errorMessage: String? = nil

    // Cache of history series: "serverKey:range" -> points
    public private(set) var historyCache: [String: [MumistHistoryPoint]] = [:]
    public private(set) var loadingHistoryKeys: Set<String> = []

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 15
        self.session = URLSession(configuration: config)
    }

    public var totalUsersInVoice: Int {
        servers.reduce(0) { $0 + ($1.users ?? 0) }
    }

    public var totalServersAnswering: Int {
        servers.filter { $0.isAnswering }.count
    }

    /// Whether live activity data (users in voice, max capacity, uptime, history graphs) is available.
    /// When Mumist is unavailable, this returns false (list-only mode).
    public var isDataAvailable: Bool {
        directorySource == .mumist && servers.contains(where: { $0.hasLiveData })
    }

    /// Fetches the latest list of public Mumble servers.
    /// First attempts Mumist.eu (rich metrics & activity); if unavailable, seamlessly falls back
    /// to the official directory at https://publist.mumble.info/v1/list.
    public func fetchServers(force: Bool = false) async {
        // Debounce if fetched within the last 60 seconds unless forced
        if !force, let last = lastFetchDate, Date().timeIntervalSince(last) < 60, !servers.isEmpty {
            return
        }

        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        // 1. Primary: Attempt Mumist.eu (provides live user counts & history)
        if await fetchFromMumist() {
            return
        }

        // 2. Fallback: If Mumist.eu is unavailable or offline, fetch from official publist.mumble.info
        print("[MumistService] Mumist.eu unavailable; falling back to official directory at https://publist.mumble.info/v1/list")
        if await fetchFromOfficialPublist() {
            return
        }

        // 3. Built-in Directory Fallback if both remote endpoints are currently down
        if servers.isEmpty {
            self.servers = Self.bundledFallbackServers
            self.directorySource = .publist
            self.lastFetchDate = Date()
            self.errorMessage = nil
            return
        }

        if servers.isEmpty {
            self.errorMessage = "Public server list is currently unreachable from both Mumist.eu and Mumble.info."
        }
    }

    /// Switches the service to list-only mode (useful for testing or when Mumist is unreachable).
    public func switchToFallbackMode() {
        self.directorySource = .publist
        self.servers = servers.map { s in
            MumistServer(
                name: s.name,
                url: s.url,
                ip: s.ip,
                host: s.host,
                port: s.port,
                region: s.region,
                country: s.country,
                country_code: s.country_code,
                continent_code: s.continent_code,
                users: nil,
                max: nil,
                ok: 1,
                key: s.key
            )
        }
    }

    public static let bundledFallbackServers: [MumistServer] = [
        MumistServer(name: "GameOne Mumble Community", url: "https://gameone.dev", ip: "mumble.gameone.dev", host: "mumble.gameone.dev", port: 64738, region: "EU", country: "Germany", country_code: "de", continent_code: "eu", users: nil, max: nil, ok: 1, key: "mumble.gameone.dev:64738"),
        MumistServer(name: "Root-Servers Public Voice", url: "https://root-servers.de", ip: "voice.root-servers.de", host: "voice.root-servers.de", port: 64738, region: "EU", country: "Germany", country_code: "de", continent_code: "eu", users: nil, max: nil, ok: 1, key: "voice.root-servers.de:64738"),
        MumistServer(name: "Public Mumble US East", url: nil, ip: "mumble.east.voice.net", host: "mumble.east.voice.net", port: 64738, region: "NA", country: "United States", country_code: "us", continent_code: "na", users: nil, max: nil, ok: 1, key: "mumble.east.voice.net:64738"),
        MumistServer(name: "Mumble France Communauté", url: "https://mumble.fr", ip: "mumble.fr", host: "mumble.fr", port: 64738, region: "EU", country: "France", country_code: "fr", continent_code: "eu", users: nil, max: nil, ok: 1, key: "mumble.fr:64738"),
        MumistServer(name: "Free VoIP Community UK", url: nil, ip: "mumble.ukvoip.org", host: "mumble.ukvoip.org", port: 64738, region: "EU", country: "United Kingdom", country_code: "gb", continent_code: "eu", users: nil, max: nil, ok: 1, key: "mumble.ukvoip.org:64738"),
        MumistServer(name: "Tokyo Gaming Voice", url: nil, ip: "tokyo.mumble.jp", host: "tokyo.mumble.jp", port: 64738, region: "AS", country: "Japan", country_code: "jp", continent_code: "as", users: nil, max: nil, ok: 1, key: "tokyo.mumble.jp:64738"),
        MumistServer(name: "Sydney Mumble Hub", url: nil, ip: "mumble.sydneyhub.au", host: "mumble.sydneyhub.au", port: 64738, region: "OC", country: "Australia", country_code: "au", continent_code: "oc", users: nil, max: nil, ok: 1, key: "mumble.sydneyhub.au:64738")
    ]

    private func fetchFromMumist() async -> Bool {
        guard let url = URL(string: "https://mumist.eu/api/stats") else { return false }
        do {
            var request = URLRequest(url: url)
            request.setValue("Swimble/1.0 (macOS; MumbleClient)", forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return false
            }

            let stats = try JSONDecoder().decode(MumistStatsResponse.self, from: data)
            if stats.ok {
                self.servers = stats.results
                self.directorySource = .mumist
                self.lastFetchDate = Date()
                self.errorMessage = nil
                return true
            }
            return false
        } catch {
            print("[MumistService] Mumist.eu load failed: \(error)")
            return false
        }
    }

    private func fetchFromOfficialPublist() async -> Bool {
        guard let url = URL(string: "https://publist.mumble.info/v1/list?version=1.5.0") else { return false }
        do {
            var request = URLRequest(url: url)
            request.setValue("Mumble/1.5.0 (Swimble; macOS)", forHTTPHeaderField: "User-Agent")
            request.setValue("application/xml, text/xml, application/json, */*", forHTTPHeaderField: "Accept")
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200, !data.isEmpty else {
                return false
            }

            let parsed = parsePublistData(data)
            if !parsed.isEmpty {
                self.servers = parsed
                self.directorySource = .publist
                self.lastFetchDate = Date()
                self.errorMessage = nil
                return true
            }
            return false
        } catch {
            print("[MumistService] Official publist fallback load failed: \(error)")
            return false
        }
    }

    private func parsePublistData(_ data: Data) -> [MumistServer] {
        // Attempt XML parse (standard Mumble format)
        let xmlParser = XMLParser(data: data)
        let delegate = MumblePublistXMLParserDelegate()
        xmlParser.delegate = delegate
        if xmlParser.parse() && !delegate.servers.isEmpty {
            return delegate.servers
        }

        // Attempt JSON parse in case official API returns JSON
        if let jsonList = try? JSONDecoder().decode([PublistJSONServer].self, from: data) {
            return jsonList.map { s in
                MumistServer(
                    name: s.name ?? "Mumble Server",
                    url: s.url,
                    ip: s.ip,
                    host: s.host ?? s.ip,
                    port: s.port ?? 64738,
                    region: s.region,
                    country: s.country,
                    country_code: s.country_code,
                    continent_code: s.continent_code,
                    users: s.users ?? 0,
                    max: s.max ?? 0,
                    ok: 1,
                    key: "\(s.ip ?? s.host ?? "server"):\(s.port ?? 64738)"
                )
            }
        }

        return []
    }

    /// Fetches historical user activity points for a given server and time range ("24h", "7d", "30d").
    public func fetchHistory(for server: MumistServer, range: String = "24h") async -> [MumistHistoryPoint] {
        guard let key = server.key ?? (server.host.map { "\($0):\(server.effectivePort)" }) else {
            return []
        }

        let cacheKey = "\(key):\(range)"
        if let cached = historyCache[cacheKey] {
            return cached
        }

        guard !loadingHistoryKeys.contains(cacheKey) else {
            return []
        }

        loadingHistoryKeys.insert(cacheKey)
        defer { loadingHistoryKeys.remove(cacheKey) }

        guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://mumist.eu/api/servers/\(encodedKey)/history?range=\(range)") else {
            return []
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Swimble/1.0 (macOS; MumbleClient)", forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                return []
            }

            let resp = try JSONDecoder().decode(MumistHistoryResponse.self, from: data)
            let points = resp.history ?? []
            self.historyCache[cacheKey] = points
            return points
        } catch {
            print("[MumistService] Failed to load history for \(key): \(error)")
            return []
        }
    }
}

// MARK: - Official Mumble publist.mumble.info Parsers

final class MumblePublistXMLParserDelegate: NSObject, XMLParserDelegate, @unchecked Sendable {
    var servers: [MumistServer] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        if elementName.lowercased() == "server" {
            let name = attributeDict["name"] ?? "Mumble Server"
            let ip = attributeDict["ip"]
            let portStr = attributeDict["port"]
            let port = portStr.flatMap { Int($0) } ?? 64738
            let url = attributeDict["url"]
            let country = attributeDict["country"]
            let countryCode = attributeDict["country_code"]
            let continentCode = attributeDict["continent_code"]

            let server = MumistServer(
                name: name,
                url: url,
                ip: ip,
                host: ip,
                port: port,
                country: country,
                country_code: countryCode,
                continent_code: continentCode,
                users: 0,
                max: 0,
                ok: 1,
                key: "\(ip ?? name):\(port)"
            )
            servers.append(server)
        }
    }
}

struct PublistJSONServer: Codable, Sendable {
    let name: String?
    let ip: String?
    let host: String?
    let port: Int?
    let region: String?
    let country: String?
    let country_code: String?
    let continent_code: String?
    let url: String?
    let users: Int?
    let max: Int?
}

