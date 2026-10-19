import SwiftUI
import AppKit

/// User Statistics modal displaying connection information, ping statistics,
/// UDP packet metrics, and bandwidth usage, identical to original Mumble client.
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
            // Title Header Bar
            HStack {
                Text(stats?.userName ?? "User Statistics")
                    .font(.headline.bold())

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.85))

            Divider()

            ScrollView {
                VStack(spacing: 16) {
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

                        // 2. Ping Statistics
                        statsCard("Ping Statistics") {
                            VStack(spacing: 8) {
                                HStack {
                                    Spacer().frame(width: 100)
                                    Text("Pings received")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 90, alignment: .trailing)
                                    Text("Average ping")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 85, alignment: .trailing)
                                    Text("Ping deviation")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 90, alignment: .trailing)
                                }

                                Divider()

                                HStack {
                                    Text("TCP (Control)")
                                        .font(.system(size: 12.5))
                                        .frame(width: 100, alignment: .leading)
                                    Text("\(s.tcpPackets)")
                                        .font(.system(size: 12.5).monospacedDigit())
                                        .frame(width: 90, alignment: .trailing)
                                    Text(String(format: "%.2f", s.tcpPingAvg))
                                        .font(.system(size: 12.5).monospacedDigit())
                                        .frame(width: 85, alignment: .trailing)
                                    Text(String(format: "%.2f", s.tcpPingVar.squareRoot()))
                                        .font(.system(size: 12.5).monospacedDigit())
                                        .frame(width: 90, alignment: .trailing)
                                }

                                HStack {
                                    Text("UDP (Voice)")
                                        .font(.system(size: 12.5))
                                        .frame(width: 100, alignment: .leading)
                                    Text("\(s.udpPackets)")
                                        .font(.system(size: 12.5).monospacedDigit())
                                        .frame(width: 90, alignment: .trailing)
                                    Text(String(format: "%.2f", s.udpPingAvg))
                                        .font(.system(size: 12.5).monospacedDigit())
                                        .frame(width: 85, alignment: .trailing)
                                    Text(String(format: "%.2f", s.udpPingVar.squareRoot()))
                                        .font(.system(size: 12.5).monospacedDigit())
                                        .frame(width: 90, alignment: .trailing)
                                }
                            }
                        }

                        // 3. UDP Network statistics
                        statsCard("UDP Network statistics") {
                            VStack(spacing: 8) {
                                HStack {
                                    Spacer().frame(width: 85)
                                    Text("Good")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, alignment: .trailing)
                                    Text("Late")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, alignment: .trailing)
                                    Text("%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, alignment: .trailing)
                                    Text("Lost")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, alignment: .trailing)
                                    Text("%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 44, alignment: .trailing)
                                    Text("Resync")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .frame(width: 48, alignment: .trailing)
                                }

                                Divider()

                                let fc = s.fromClient
                                let fcTotal = fc.good + fc.late + fc.lost
                                HStack {
                                    Text("From Client")
                                        .font(.system(size: 12))
                                        .frame(width: 85, alignment: .leading)
                                    Text("\(fc.good)")
                                        .font(.system(size: 12).monospacedDigit())
                                        .frame(width: 44, alignment: .trailing)
                                    Text("\(fc.late)")
                                        .font(.system(size: 12).monospacedDigit())
                                        .frame(width: 44, alignment: .trailing)
                                    Text(formatPercent(fc.late, total: fcTotal))
                                        .font(.system(size: 12).monospacedDigit())
                                        .frame(width: 44, alignment: .trailing)
                                    Text("\(fc.lost)")
                                        .font(.system(size: 12).monospacedDigit())
                                        .frame(width: 44, alignment: .trailing)
                                    Text(formatPercent(fc.lost, total: fcTotal))
                                        .font(.system(size: 12).monospacedDigit())
                                        .frame(width: 44, alignment: .trailing)
                                    Text("\(fc.resync)")
                                        .font(.system(size: 12).monospacedDigit())
                                        .frame(width: 48, alignment: .trailing)
                                }

                                let fs = s.fromServer
                                let fsTotal = fs.good + fs.late + fs.lost
                                HStack {
                                    Text("To Client")
                                        .font(.system(size: 12))
                                        .frame(width: 85, alignment: .leading)
                                    Text("\(fs.good)")
                                        .font(.system(size: 12).monospacedDigit())
                                        .frame(width: 44, alignment: .trailing)
                                    Text("\(fs.late)")
                                        .font(.system(size: 12).monospacedDigit())
                                        .frame(width: 44, alignment: .trailing)
                                    Text(formatPercent(fs.late, total: fsTotal))
                                        .font(.system(size: 12).monospacedDigit())
                                        .frame(width: 44, alignment: .trailing)
                                    Text("\(fs.lost)")
                                        .font(.system(size: 12).monospacedDigit())
                                        .frame(width: 44, alignment: .trailing)
                                    Text(formatPercent(fs.lost, total: fsTotal))
                                        .font(.system(size: 12).monospacedDigit())
                                        .frame(width: 44, alignment: .trailing)
                                    Text("\(fs.resync)")
                                        .font(.system(size: 12).monospacedDigit())
                                        .frame(width: 48, alignment: .trailing)
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
                .padding(20)
            }
        }
        .frame(width: 420, height: 600)
        .sheet(isPresented: $showCertDetails) {
            certificateDetailsSheet
        }
    }

    @ViewBuilder
    private func statsCard<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline.bold())

            content()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.6))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private var certificateDetailsSheet: some View {
        VStack(spacing: 16) {
            HStack {
                Text("Certificate Details")
                    .font(.headline.bold())
                Spacer()
                Button("Done") {
                    showCertDetails = false
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if let der = stats?.certificateDer, let secCert = SecCertificateCreateWithData(nil, der as CFData) {
                    if let summary = SecCertificateCopySubjectSummary(secCert) as String? {
                        HStack {
                            Text("Subject:")
                                .bold()
                            Text(summary)
                        }
                    }
                    HStack {
                        Text("Size:")
                            .bold()
                        Text("\(der.count) bytes (DER)")
                    }
                } else {
                    Text(stats?.certificateDetails ?? "No certificate details available.")
                        .font(.body)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer()
        }
        .padding(20)
        .frame(width: 380, height: 260)
    }
}
