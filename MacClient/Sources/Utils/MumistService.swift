import Foundation
import Observation

/// Service for fetching public Mumble server directory data from Mumist (https://mumist.eu).
@Observable
@MainActor
public final class MumistService {
    public static let shared = MumistService()

    public private(set) var servers: [MumistServer] = []
    public private(set) var isLoading: Bool = false
    public private(set) var lastFetchDate: Date? = nil
    public private(set) var errorMessage: String? = nil

    // Cache of history series: "serverKey:range" -> points
    public private(set) var historyCache: [String: [MumistHistoryPoint]] = [:]
    public private(set) var loadingHistoryKeys: Set<String> = []

    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        self.session = URLSession(configuration: config)
    }

    public var totalUsersInVoice: Int {
        servers.reduce(0) { $0 + ($1.users ?? 0) }
    }

    public var totalServersAnswering: Int {
        servers.filter { $0.isAnswering }.count
    }

    /// Fetches the latest list of public Mumble servers.
    public func fetchServers(force: Bool = false) async {
        // Debounce if fetched within the last 60 seconds unless forced
        if !force, let last = lastFetchDate, Date().timeIntervalSince(last) < 60, !servers.isEmpty {
            return
        }

        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil

        defer { isLoading = false }

        guard let url = URL(string: "https://mumist.eu/api/stats") else {
            errorMessage = "Invalid API URL"
            return
        }

        do {
            var request = URLRequest(url: url)
            request.setValue("Swimble/1.0 (macOS; MumbleClient)", forHTTPHeaderField: "User-Agent")
            request.cachePolicy = .reloadIgnoringLocalCacheData

            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                errorMessage = "Server returned error code"
                return
            }

            let stats = try JSONDecoder().decode(MumistStatsResponse.self, from: data)
            if stats.ok {
                self.servers = stats.results
                self.lastFetchDate = Date()
                self.errorMessage = nil
            } else {
                self.errorMessage = "Mumist API returned ok: false"
            }
        } catch {
            print("[MumistService] Failed to load servers: \(error)")
            if servers.isEmpty {
                self.errorMessage = error.localizedDescription
            }
        }
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
