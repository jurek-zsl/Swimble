import SwiftUI
import AppKit

/// User Statistics modal displaying connection information, ping statistics,
/// UDP packet metrics, and bandwidth usage, replicating the iconic Mumble diagnostic tool.
public struct UserStatsModal: View {
    @Bindable public var store: MumbleStore
    @Environment(\.dismiss) private var dismiss
    @State private var showCertDetails: Bool = false

    public init(store: MumbleStore) {
        self.store = store
    }

    private var stats: UserStatsInfo? {
        store.currentUserStats
    }

    private var isMe: Bool {
        guard let s = stats else { return false }
        return s.sessionId == store.mySessionId
    }

    // MARK: - Metric Fallbacks & Effective Values

    private var effectiveTcpPackets: UInt32 {
        guard let s = stats else { return 0 }
        if s.tcpPackets > 0 { return s.tcpPackets }
        if isMe {
            return store.connectionInfo?.tcpPacketsSent ?? 0
        }
        return 0
    }

    private var effectiveTcpPingAvg: Float {
        guard let s = stats else { return 0.0 }
        if s.tcpPingAvg > 0.0 { return s.tcpPingAvg }
        if isMe && store.tcpPingMs > 0.0 {
            return store.tcpPingMs
        }
        return 0.0
    }

    private var effectiveTcpPingDev: Float {
        guard let s = stats else { return 0.0 }
        if s.tcpPingVar > 0.0 { return s.tcpPingVar.squareRoot() }
        return 0.0
    }

    private var effectiveUdpPackets: UInt32 {
        guard let s = stats else { return 0 }
        if s.udpPackets > 0 { return s.udpPackets }
        if isMe {
            return store.connectionInfo?.udpPacketsSent ?? 0
        }
        return 0
    }

    private var effectiveUdpPingAvg: Float {
        guard let s = stats else { return 0.0 }
        if s.udpPingAvg > 0.0 { return s.udpPingAvg }
        if isMe && store.udpPingMs > 0.0 {
            return store.udpPingMs
        }
        return 0.0
    }

    private var effectiveUdpPingDev: Float {
        guard let s = stats else { return 0.0 }
        if s.udpPingVar > 0.0 { return s.udpPingVar.squareRoot() }
        return 0.0
    }

    private var effectiveFromClientGood: UInt32 {
        guard let s = stats else { return 0 }
        if s.fromClient.good > 0 { return s.fromClient.good }
        if isMe { return store.connectionInfo?.goodPackets ?? 0 }
        return 0
    }

    private var effectiveFromClientLate: UInt32 {
        guard let s = stats else { return 0 }
        if s.fromClient.late > 0 { return s.fromClient.late }
        if isMe { return store.connectionInfo?.latePackets ?? 0 }
        return 0
    }

    private var effectiveFromClientLost: UInt32 {
        guard let s = stats else { return 0 }
        if s.fromClient.lost > 0 { return s.fromClient.lost }
        if isMe { return store.connectionInfo?.lostPackets ?? 0 }
        return 0
    }

    private var effectiveFromClientResync: UInt32 {
        guard let s = stats else { return 0 }
        if s.fromClient.resync > 0 { return s.fromClient.resync }
        if isMe { return store.connectionInfo?.resyncPackets ?? 0 }
        return 0
    }

    private func formatPercent(_ count: UInt32, total: UInt32) -> String {
        guard total > 0 else { return "0.00" }
        let pct = (Double(count) / Double(total)) * 100.0
        return String(format: "%.2f", pct)
    }

    private func formatDuration(seconds: UInt32) -> String {
        if seconds < 60 {
            return "\(seconds)s"
        } else if seconds < 3600 {
            let mins = seconds / 60
            let secs = seconds % 60
            return "\(mins)m \(secs)s"
        } else {
            let hrs = seconds / 3600
            let mins = (seconds % 3600) / 60
            return "\(hrs)h \(mins)m"
        }
    }

    private func formatBandwidth(_ bandwidth: UInt32) -> String {
        if bandwidth == 0 {
            return "0.0 kbit/s"
        }
        let kbps = Double(bandwidth) / 1000.0
        return String(format: "%.1f kbit/s", kbps)
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header Bar
            HStack(spacing: 10) {
                Image(systemName: "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(store.accentTint)

                VStack(alignment: .leading, spacing: 2) {
                    Text(stats?.userName ?? "User Statistics")
                        .font(.headline.weight(.semibold))
                    if let s = stats {
                        Text(isMe ? "Your Connection Diagnostics" : "Session #\(s.sessionId)")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Close (Esc)")
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.85))

            Divider()

            ScrollView {
                VStack(spacing: 14) {
                    if let s = stats {
                        // 1. Connection Information
                        statsCard("Connection Information") {
                            VStack(spacing: 8) {
                                HStack(alignment: .top) {
                                    Text("Version")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 90, alignment: .leading)
                                    let vStr = s.versionV.isEmpty ? "1.5.0" : s.versionV
                                    let relStr = s.versionRelease.isEmpty ? "" : " (\(s.versionRelease))"
                                    Text("\(vStr)\(relStr)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                HStack(alignment: .top) {
                                    Text("OS")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 90, alignment: .leading)
                                    let osStr = s.versionOs.isEmpty ? "macOS" : s.versionOs
                                    let osVer = s.versionOsVersion.isEmpty ? "(26.0)" : "(\(s.versionOsVersion))"
                                    Text("\(osStr) \(osVer)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                HStack(alignment: .center) {
                                    Text("Certificate")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 90, alignment: .leading)
                                    Text(s.certificateName.isEmpty ? "None" : s.certificateName)
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                    Button("Details") {
                                        showCertDetails = true
                                    }
                                    .buttonStyle(.bordered)
                                    .controlSize(.small)
                                    .disabled(s.certificateDer == nil && s.certificateName == "None")
                                }

                                HStack(alignment: .top) {
                                    Text("IP Address")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 90, alignment: .leading)
                                    Text(s.ipAddress.isEmpty ? "127.0.0.1" : s.ipAddress)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                HStack(alignment: .top) {
                                    Text("Opus")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 90, alignment: .leading)
                                    Text(s.opusSupported ? "Supported" : "Unsupported")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .font(.system(size: 13))
                        }

                        // 2. Ping Statistics (Exact Grid Alignment)
                        statsCard("Ping Statistics") {
                            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                                GridRow {
                                    Color.clear
                                        .frame(width: 105, height: 1)
                                        .gridCellUnsizedAxes([.horizontal, .vertical])

                                    Text("Pings received")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.trailing)

                                    Text("Average ping")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.trailing)

                                    Text("Ping deviation")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.trailing)
                                }

                                Divider()

                                GridRow {
                                    Text("TCP (Control)")
                                        .font(.system(size: 12.5))

                                    Text("\(effectiveTcpPackets)")
                                        .font(.system(size: 12.5).monospacedDigit())

                                    Text(String(format: "%.2f", effectiveTcpPingAvg))
                                        .font(.system(size: 12.5).monospacedDigit())

                                    Text(String(format: "%.2f", effectiveTcpPingDev))
                                        .font(.system(size: 12.5).monospacedDigit())
                                }

                                GridRow {
                                    Text("UDP (Voice)")
                                        .font(.system(size: 12.5))

                                    Text("\(effectiveUdpPackets)")
                                        .font(.system(size: 12.5).monospacedDigit())

                                    Text(String(format: "%.2f", effectiveUdpPingAvg))
                                        .font(.system(size: 12.5).monospacedDigit())

                                    Text(String(format: "%.2f", effectiveUdpPingDev))
                                        .font(.system(size: 12.5).monospacedDigit())
                                }
                            }
                        }

                        // 3. UDP Network statistics (Exact Grid Alignment)
                        statsCard("UDP Network statistics") {
                            let fcGood = effectiveFromClientGood
                            let fcLate = effectiveFromClientLate
                            let fcLost = effectiveFromClientLost
                            let fcResync = effectiveFromClientResync
                            let fcTotal = fcGood + fcLate + fcLost

                            let fs = s.fromServer
                            let fsGood = fs.good
                            let fsLate = fs.late
                            let fsLost = fs.lost
                            let fsResync = fs.resync
                            let fsTotal = fsGood + fsLate + fsLost

                            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 6) {
                                GridRow {
                                    Color.clear
                                        .frame(width: 82, height: 1)
                                        .gridCellUnsizedAxes([.horizontal, .vertical])

                                    Text("Good")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.trailing)

                                    Text("Late")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.trailing)

                                    Text("%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.trailing)

                                    Text("Lost")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.trailing)

                                    Text("%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.trailing)

                                    Text("Resync")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .gridColumnAlignment(.trailing)
                                }

                                Divider()

                                GridRow {
                                    Text("From Client")
                                        .font(.system(size: 12))

                                    Text("\(fcGood)")
                                        .font(.system(size: 12).monospacedDigit())

                                    Text("\(fcLate)")
                                        .font(.system(size: 12).monospacedDigit())

                                    Text(formatPercent(fcLate, total: fcTotal))
                                        .font(.system(size: 12).monospacedDigit())

                                    Text("\(fcLost)")
                                        .font(.system(size: 12).monospacedDigit())

                                    Text(formatPercent(fcLost, total: fcTotal))
                                        .font(.system(size: 12).monospacedDigit())

                                    Text("\(fcResync)")
                                        .font(.system(size: 12).monospacedDigit())
                                }

                                GridRow {
                                    Text("To Client")
                                        .font(.system(size: 12))

                                    Text("\(fsGood)")
                                        .font(.system(size: 12).monospacedDigit())

                                    Text("\(fsLate)")
                                        .font(.system(size: 12).monospacedDigit())

                                    Text(formatPercent(fsLate, total: fsTotal))
                                        .font(.system(size: 12).monospacedDigit())

                                    Text("\(fsLost)")
                                        .font(.system(size: 12).monospacedDigit())

                                    Text(formatPercent(fsLost, total: fsTotal))
                                        .font(.system(size: 12).monospacedDigit())

                                    Text("\(fsResync)")
                                        .font(.system(size: 12).monospacedDigit())
                                }
                            }
                        }

                        // 4. Bandwidth
                        statsCard("Bandwidth") {
                            VStack(spacing: 8) {
                                HStack {
                                    Text("Connection time")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 120, alignment: .leading)
                                    Text("\(formatDuration(seconds: s.onlinesecs)) online (\(formatDuration(seconds: s.idlesecs)) idle)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                HStack {
                                    Text("Bandwidth")
                                        .foregroundStyle(.secondary)
                                        .frame(width: 120, alignment: .leading)
                                    Text(formatBandwidth(s.bandwidth))
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                            }
                            .font(.system(size: 13))
                        }
                    } else {
                        VStack(spacing: 12) {
                            ProgressView()
                            Text("Loading user statistics...")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }
        }
        .frame(width: 440)
        .frame(minHeight: 650, idealHeight: 680, maxHeight: 720)
        .sheet(isPresented: $showCertDetails) {
            certificateDetailsSheet
        }
        .task(id: stats?.sessionId) {
            guard let sessionId = stats?.sessionId else { return }
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { break }
                store.requestUserStats(sessionId: sessionId, statsOnly: true)
            }
        }
    }

    @ViewBuilder
    private func statsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.55))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var certificateDetailsSheet: some View {
        VStack(spacing: 16) {
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.seal.fill")
                        .foregroundStyle(Color.green)
                    Text("Certificate Details")
                        .font(.headline.weight(.semibold))
                }

                Spacer()

                Button("Done") {
                    showCertDetails = false
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                if let der = stats?.certificateDer, let secCert = SecCertificateCreateWithData(nil, der as CFData) {
                    if let summary = SecCertificateCopySubjectSummary(secCert) as String? {
                        HStack(alignment: .top) {
                            Text("Subject:")
                                .font(.subheadline.bold())
                                .frame(width: 80, alignment: .leading)
                            Text(summary)
                                .font(.subheadline)
                        }
                    }
                    HStack {
                        Text("Size:")
                            .font(.subheadline.bold())
                            .frame(width: 80, alignment: .leading)
                        Text("\(der.count) bytes (DER encoded)")
                            .font(.subheadline.monospacedDigit())
                    }
                    HStack {
                        Text("Validation:")
                            .font(.subheadline.bold())
                            .frame(width: 80, alignment: .leading)
                        Text(stats?.strongCertificate == true ? "Strong (CA Verified)" : "Self-Signed / Mumble Native")
                            .font(.subheadline)
                            .foregroundStyle(stats?.strongCertificate == true ? Color.green : Color.orange)
                    }
                } else {
                    Text(stats?.certificateDetails ?? "No certificate details available.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(NSColor.controlBackgroundColor).opacity(0.5))
            }

            Spacer()
        }
        .padding(20)
        .frame(width: 400, height: 260)
    }
}
