import SwiftUI
import Charts
import AppKit

public enum MumistSortOption: String, CaseIterable, Identifiable {
    case users = "Most People"
    case fullness = "Fullest"
    case name = "Name (A-Z)"
    case country = "Location (A-Z)"
    case uptime = "Highest Uptime"

    public var id: String { rawValue }
}

/// Rich public server browser integrated with Mumist (https://mumist.eu).
public struct MumistPublicServersView: View {
    @Bindable public var store: MumbleStore
    public var onConnect: () -> Void

    @State private var service = MumistService.shared
    @State private var selectedServerId: String? = nil
    @State private var searchText: String = ""
    @State private var selectedContinent: String = "All"
    @State private var minUsersFilter: Int = 0
    @State private var sortOption: MumistSortOption = .users
    @State private var chartRange: String = "24h"
    @State private var serverHistory: [MumistHistoryPoint] = []
    @State private var isLoadingHistory: Bool = false
    @State private var bookmarkedToastServerId: String? = nil

    private let continents = ["All", "Europe", "North America", "Asia", "South America", "Oceania", "Africa"]

    public init(store: MumbleStore, onConnect: @escaping () -> Void) {
        self.store = store
        self.onConnect = onConnect
    }

    private var selectedServer: MumistServer? {
        if let id = selectedServerId {
            return filteredServers.first(where: { $0.id == id }) ?? service.servers.first(where: { $0.id == id })
        }
        return filteredServers.first
    }

    private var filteredServers: [MumistServer] {
        var list = service.servers

        // 1. Min users filter (only applied when live activity data is available)
        if service.isDataAvailable && minUsersFilter > 0 {
            list = list.filter { ($0.users ?? 0) >= minUsersFilter }
        }

        // 2. Continent filter
        if selectedContinent != "All" {
            list = list.filter { $0.continentName == selectedContinent }
        }

        // 3. Search query
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !query.isEmpty {
            list = list.filter { s in
                s.name.lowercased().contains(query) ||
                s.displayAddress.lowercased().contains(query) ||
                s.locationDisplay.lowercased().contains(query) ||
                (s.country?.lowercased().contains(query) ?? false) ||
                (s.region?.lowercased().contains(query) ?? false)
            }
        }

        // 4. Sorting
        switch sortOption {
        case .users:
            if service.isDataAvailable {
                list.sort { ($0.users ?? 0) > ($1.users ?? 0) }
            } else {
                list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        case .fullness:
            if service.isDataAvailable {
                list.sort { $0.fillRatio > $1.fillRatio }
            } else {
                list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        case .name:
            list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .country:
            list.sort { $0.locationDisplay.localizedCaseInsensitiveCompare($1.locationDisplay) == .orderedAscending }
        case .uptime:
            if service.isDataAvailable {
                list.sort { ($0.uptime_7d ?? 0.0) > ($1.uptime_7d ?? 0.0) }
            } else {
                list.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            }
        }

        return list
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Live Stats & Freshness Banner
            headerStatsBar

            Divider()

            // Notice banner when Mumist is unavailable (showing list without live data)
            if !service.isDataAvailable && !service.servers.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("Mumist.eu is currently unavailable. Showing server list without live user counts, capacity, or activity charts.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button {
                        Task { await service.fetchServers(force: true) }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.clockwise")
                            Text("Retry Mumist")
                        }
                        .font(.caption2)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.08))

                Divider()
            }

            // Filter & Search Controls Bar
            filterToolbar

            Divider()

            // Main Master-Detail Content
            if service.isLoading && service.servers.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.regular)
                    Text("Fetching public servers...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = service.errorMessage, service.servers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "wifi.exclamationmark")
                        .font(.system(size: 36))
                        .foregroundStyle(.orange)
                    Text("Could not reach public servers")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Try Again") {
                        Task { await service.fetchServers(force: true) }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(store.accentTint)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HSplitView {
                    // Left Column: Server Table / List
                    serverListColumn
                        .frame(minWidth: 360, maxWidth: .infinity)

                    // Right Column: Server Inspector & History Chart
                    serverInspectorColumn
                        .frame(minWidth: 320, idealWidth: 340, maxWidth: 420)
                }
            }
        }
        .task {
            await service.fetchServers()
            if selectedServerId == nil, let first = filteredServers.first {
                selectedServerId = first.id
            }
        }
        .onChange(of: selectedServerId) { _, newId in
            if let server = selectedServer {
                loadHistory(for: server)
            }
        }
        .onChange(of: chartRange) { _, _ in
            if let server = selectedServer {
                loadHistory(for: server)
            }
        }
    }

    // MARK: - Subviews

    private var headerStatsBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Circle()
                    .fill(service.isDataAvailable ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(service.isDataAvailable ? "Mumist.eu Live Directory" : "Official Mumble Directory")
                    .font(.caption.bold())

                if !service.isDataAvailable {
                    Text("List Only • No Live Data")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.orange)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.orange.opacity(0.18), in: Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background((service.isDataAvailable ? Color.green : Color.orange).opacity(0.12), in: Capsule())

            if service.isDataAvailable && service.totalUsersInVoice > 0 {
                Text("\(service.totalUsersInVoice) people in voice")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("•")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Text("\(service.totalServersAnswering) servers online")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if !service.isDataAvailable {
                Text("\(service.servers.count) servers listed")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Small button linking directly to mumist.eu
            Link(destination: URL(string: "https://mumist.eu")!) {
                HStack(spacing: 4) {
                    Image(systemName: "safari")
                        .font(.caption2)
                    Text("mumist.eu")
                        .font(.caption.bold())
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .bold))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.primary.opacity(0.06), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Open mumist.eu website in browser")

            if service.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            Menu {
                Button {
                    Task { await service.fetchServers(force: true) }
                } label: {
                    Label("Refresh Directory", systemImage: "arrow.clockwise")
                }

                if service.isDataAvailable {
                    Button {
                        service.switchToFallbackMode()
                    } label: {
                        Label("Preview List-Only Mode", systemImage: "eye.slash")
                    }
                } else {
                    Button {
                        Task { await service.fetchServers(force: true) }
                    } label: {
                        Label("Retry Mumist.eu Live Stats", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 18)
            .help("Directory options")

            Button {
                Task {
                    await service.fetchServers(force: true)
                }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(service.isLoading)
            .help("Refresh public server list")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    private var filterToolbar: some View {
        HStack(spacing: 10) {
            // Search field
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Search name, address or country...", text: $searchText)
                    .textFieldStyle(.plain)
                    .font(.caption)

                if !searchText.isEmpty {
                    Button {
                        searchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Color(nsColor: .controlBackgroundColor).opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
            .frame(maxWidth: 240)

            // Continent dropdown
            Picker("", selection: $selectedContinent) {
                ForEach(continents, id: \.self) { c in
                    Text(c).tag(c)
                }
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .controlSize(.small)
            .frame(width: 125)

            // Min users chip group (only available when live data is provided by Mumist)
            if service.isDataAvailable {
                HStack(spacing: 4) {
                    minUserChip(label: "Any", min: 0)
                    minUserChip(label: "1+", min: 1)
                    minUserChip(label: "5+", min: 5)
                    minUserChip(label: "20+", min: 20)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "person.slash")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text("Live count filter disabled")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: Capsule())
            }

            Spacer()

            // Sort option picker
            Picker("Sort:", selection: $sortOption) {
                ForEach(MumistSortOption.allCases) { opt in
                    Text(opt.rawValue).tag(opt)
                }
            }
            .pickerStyle(.menu)
            .controlSize(.small)
            .frame(width: 150)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func minUserChip(label: String, min: Int) -> some View {
        Button {
            minUsersFilter = min
        } label: {
            Text(label)
                .font(.caption2.bold())
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    minUsersFilter == min
                        ? store.accentTint.opacity(0.2)
                        : Color(nsColor: .controlBackgroundColor).opacity(0.5),
                    in: Capsule()
                )
                .overlay(
                    Capsule()
                        .stroke(minUsersFilter == min ? store.accentTint : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Server List Column

    private var serverListColumn: some View {
        VStack(spacing: 0) {
            if filteredServers.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("No servers match your filters")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection: $selectedServerId) {
                    ForEach(filteredServers) { server in
                        serverRow(server)
                            .tag(server.id)
                            .contextMenu {
                                Button("Connect") {
                                    connectToServer(server)
                                }
                                Button("Add to Bookmarks") {
                                    addServerToBookmarks(server)
                                }
                                Button("Copy Address") {
                                    copyToClipboard(server.displayAddress)
                                }
                                if let url = server.mumbleURL {
                                    Button("Copy Mumble Link") {
                                        copyToClipboard(url.absoluteString)
                                    }
                                }
                                if let web = server.url, let u = URL(string: web) {
                                    Button("Visit Website") {
                                        NSWorkspace.shared.open(u)
                                    }
                                }
                            }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private func serverRow(_ server: MumistServer) -> some View {
        HStack(spacing: 10) {
            // Country flag
            Text(server.flagEmoji)
                .font(.title3)

            // Name & Address
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(server.name)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                    if service.isDataAvailable && (server.uptime_7d ?? 0) >= 0.99 {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.caption2)
                            .foregroundStyle(store.accentTint)
                            .help("High availability server (>99% uptime)")
                    }
                }

                HStack(spacing: 4) {
                    Text(server.displayAddress)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                    Text("•")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    Text(server.locationDisplay)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            // User capacity pill or List-only badge
            if service.isDataAvailable && server.hasLiveData {
                VStack(alignment: .trailing, spacing: 3) {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                            .foregroundStyle((server.users ?? 0) > 0 ? store.accentTint : .secondary)
                        Text("\(server.users ?? 0)")
                            .font(.subheadline.monospacedDigit().bold())
                            .foregroundStyle((server.users ?? 0) > 0 ? .primary : .secondary)
                        if let max = server.max, max > 0 {
                            Text("/ \(max)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.tertiary)
                        }
                    }

                    // Mini capacity bar
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.secondary.opacity(0.15))
                                .frame(height: 3)
                            Capsule()
                                .fill(server.fillRatio > 0.8 ? Color.orange : store.accentTint)
                                .frame(width: max(2, geo.size.width * server.fillRatio), height: 3)
                        }
                    }
                    .frame(width: 54, height: 3)
                }
            } else {
                HStack(spacing: 4) {
                    Image(systemName: "list.bullet")
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                    Text("List only")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 4))
            }

            // Quick Connect Button
            Button {
                connectToServer(server)
            } label: {
                Image(systemName: "bolt.fill")
                    .font(.caption)
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(store.accentTint, in: Circle())
            }
            .buttonStyle(.plain)
            .help("Connect immediately")
        }
        .padding(.vertical, 4)
    }

    // MARK: - Server Inspector Column

    private var serverInspectorColumn: some View {
        ScrollView {
            if let server = selectedServer {
                VStack(alignment: .leading, spacing: 16) {
                    // Header Card
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(server.flagEmoji)
                                .font(.system(size: 28))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(server.name)
                                    .font(.headline)
                                    .lineLimit(2)
                                Text(server.locationDisplay)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        // Quick Action Buttons
                        HStack(spacing: 8) {
                            Button {
                                connectToServer(server)
                            } label: {
                                Label("Connect", systemImage: "bolt.fill")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(store.accentTint)

                            Button {
                                addServerToBookmarks(server)
                            } label: {
                                Image(systemName: isBookmarked(server) ? "star.fill" : "star")
                                    .foregroundStyle(isBookmarked(server) ? Color.yellow : Color.secondary)
                            }
                            .buttonStyle(.bordered)
                            .help(isBookmarked(server) ? "Already in Bookmarks" : "Add to Bookmarks")

                            Button {
                                copyToClipboard(server.displayAddress)
                            } label: {
                                Image(systemName: "doc.on.doc")
                            }
                            .buttonStyle(.bordered)
                            .help("Copy Server Address")

                            if let web = server.url, let u = URL(string: web) {
                                Button {
                                    NSWorkspace.shared.open(u)
                                } label: {
                                    Image(systemName: "globe")
                                }
                                .buttonStyle(.bordered)
                                .help("Open Server Website")
                            }
                        }
                        .padding(.top, 6)

                        if bookmarkedToastServerId == server.id {
                            HStack(spacing: 4) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("Saved to Bookmarks!")
                                    .font(.caption.bold())
                                    .foregroundStyle(.green)
                            }
                            .padding(.top, 2)
                            .transition(.opacity)
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))

                    // Key Metrics Grid
                    if service.isDataAvailable && server.hasLiveData {
                        VStack(spacing: 8) {
                            HStack {
                                metricItem(
                                    title: "People in Voice",
                                    value: "\(server.onlineUsersCount)",
                                    subtitle: server.maxUsersCount > 0 ? "of \(server.maxUsersCount) slots" : "slots unlimited",
                                    icon: "person.2.fill"
                                )
                                metricItem(
                                    title: "24h Peak",
                                    value: server.peak_24h != nil ? "\(server.peak_24h!)" : "—",
                                    subtitle: "peak activity",
                                    icon: "chart.line.uptrend.xyaxis"
                                )
                            }

                            HStack {
                                metricItem(
                                    title: "7-Day Uptime",
                                    value: server.uptimePercentage != nil ? String(format: "%.1f%%", server.uptimePercentage!) : "—",
                                    subtitle: "reliability score",
                                    icon: "shield.checkerboard"
                                )
                                metricItem(
                                    title: "Version",
                                    value: server.version ?? "1.5+",
                                    subtitle: "mumble protocol",
                                    icon: "cpu"
                                )
                            }
                        }
                    } else {
                        // Notice card explaining list-only mode
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 6) {
                                Image(systemName: "chart.bar.xaxis")
                                    .foregroundStyle(.orange)
                                Text("Live Metrics Unavailable")
                                    .font(.subheadline.bold())
                            }
                            Text("Mumist.eu is currently unavailable. This server was loaded from the directory without live user counts, capacity limits, or reliability ratings.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)

                            Divider()

                            HStack {
                                metricItem(
                                    title: "Directory Type",
                                    value: "List Only",
                                    subtitle: "fallback mode",
                                    icon: "list.bullet.rectangle"
                                )
                                metricItem(
                                    title: "Direct Connect",
                                    value: "Ready",
                                    subtitle: "click Connect above",
                                    icon: "bolt.fill"
                                )
                            }
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Historical Activity Chart
                    if service.isDataAvailable && server.hasLiveData {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("People Over Time")
                                        .font(.subheadline.bold())
                                    Text("Live telemetry from Mumist")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                Picker("", selection: $chartRange) {
                                    Text("24h").tag("24h")
                                    Text("7d").tag("7d")
                                    Text("30d").tag("30d")
                                }
                                .pickerStyle(.segmented)
                                .controlSize(.mini)
                                .frame(width: 120)
                            }

                            if isLoadingHistory {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("Loading chart...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .frame(height: 100)
                            } else if serverHistory.isEmpty {
                                VStack(spacing: 4) {
                                    Text("No recent history data recorded")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(maxWidth: .infinity)
                                .frame(height: 90)
                            } else {
                                Chart(serverHistory) { point in
                                    AreaMark(
                                        x: .value("Time", point.date),
                                        y: .value("Users", point.users)
                                    )
                                    .foregroundStyle(
                                        LinearGradient(
                                            colors: [store.accentTint.opacity(0.35), store.accentTint.opacity(0.02)],
                                            startPoint: .top,
                                            endPoint: .bottom
                                        )
                                    )

                                    LineMark(
                                        x: .value("Time", point.date),
                                        y: .value("Users", point.users)
                                    )
                                    .foregroundStyle(store.accentTint)
                                    .lineStyle(StrokeStyle(lineWidth: 2))
                                }
                                .chartXAxis {
                                    AxisMarks(values: .automatic(desiredCount: 4)) {
                                        AxisValueLabel(format: .dateTime.hour().minute())
                                    }
                                }
                                .chartYAxis {
                                    AxisMarks(values: .automatic(desiredCount: 3))
                                }
                                .frame(height: 110)
                            }
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
                    } else {
                        // Explanatory card for unavailable chart
                        VStack(alignment: .leading, spacing: 8) {
                            Text("People Over Time")
                                .font(.subheadline.bold())

                            HStack(spacing: 10) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.title2)
                                    .foregroundStyle(.secondary.opacity(0.5))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Activity chart unavailable")
                                        .font(.caption.bold())
                                    Text("Historical voice curves are collected exclusively by Mumist.eu. In list-only mode, graphs cannot be plotted.")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 6)
                        }
                        .padding(12)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                    }

                    // Address Info Details
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Connection Details")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        HStack {
                            Text("Host:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(server.effectiveHost)
                                .font(.caption.monospaced())
                                .textSelection(.enabled)
                        }

                        HStack {
                            Text("Port:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("\(server.effectivePort)")
                                .font(.caption.monospaced())
                        }

                        HStack {
                            Text("Data Mode:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(server.hasLiveData ? "Live Telemetry" : "Directory List Only")
                                .font(.caption.bold())
                                .foregroundStyle(server.hasLiveData ? .green : .orange)
                        }

                        HStack {
                            Text("Status:")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            HStack(spacing: 4) {
                                Circle()
                                    .fill(server.isAnswering ? Color.green : Color.orange)
                                    .frame(width: 6, height: 6)
                                Text(server.isAnswering ? "Answering" : "Quiet / Not Answering")
                                    .font(.caption)
                            }
                        }
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(14)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.left.circle")
                        .font(.title)
                        .foregroundStyle(.secondary)
                    Text("Select a server from the list to view live statistics")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).opacity(0.5))
    }

    private func metricItem(title: String, value: String, subtitle: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(store.accentTint)
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.headline.monospacedDigit())
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Actions

    private func loadHistory(for server: MumistServer) {
        isLoadingHistory = true
        Task {
            let points = await service.fetchHistory(for: server, range: chartRange)
            self.serverHistory = points
            self.isLoadingHistory = false
        }
    }

    private func connectToServer(_ server: MumistServer) {
        let fallbackUser = store.bookmarks.first?.username ?? "User"
        let bookmark = server.toBookmark(defaultUsername: fallbackUser)
        store.activeModal = nil
        onConnect()
        store.connect(bookmark: bookmark)
    }

    private func isBookmarked(_ server: MumistServer) -> Bool {
        store.bookmarks.contains { $0.host.caseInsensitiveCompare(server.effectiveHost) == .orderedSame && $0.port == server.effectivePort }
    }

    private func addServerToBookmarks(_ server: MumistServer) {
        if !isBookmarked(server) {
            let fallbackUser = store.bookmarks.first?.username ?? "User"
            let bm = server.toBookmark(defaultUsername: fallbackUser)
            store.addBookmark(bm)
        }
        withAnimation {
            bookmarkedToastServerId = server.id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                if bookmarkedToastServerId == server.id {
                    bookmarkedToastServerId = nil
                }
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
