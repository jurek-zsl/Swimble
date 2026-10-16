import SwiftUI

/// Server Ban List dialog allowing administrators to view, add, and remove IP/user bans.
public struct BanListModal: View {
    @Bindable public var store: MumbleStore
    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @State private var showAddSheet: Bool = false
    @State private var newIp: String = ""
    @State private var newMask: Int = 32
    @State private var newReason: String = ""
    @State private var selectedDurationPreset: DurationPreset = .oneDay
    @State private var customDurationHours: Int = 24
    @State private var banToRemove: BanEntryInfo? = nil
    @State private var showConfirmRemove: Bool = false

    public enum DurationPreset: String, CaseIterable, Identifiable {
        case oneHour = "1 Hour"
        case oneDay = "24 Hours"
        case oneWeek = "7 Days"
        case oneMonth = "30 Days"
        case permanent = "Permanent"
        case custom = "Custom"

        public var id: String { rawValue }

        public var hours: UInt32 {
            match: switch self {
            case .oneHour: return 1
            case .oneDay: return 24
            case .oneWeek: return 24 * 7
            case .oneMonth: return 24 * 30
            case .permanent: return 0
            case .custom: return 24
            }
        }
    }

    public init(store: MumbleStore) {
        self.store = store
    }

    private var filteredBans: [BanEntryInfo] {
        if searchText.isEmpty {
            return store.banList
        }
        return store.banList.filter { ban in
            ban.ip.localizedCaseInsensitiveContains(searchText) ||
            ban.reason.localizedCaseInsensitiveContains(searchText) ||
            ban.name.localizedCaseInsensitiveContains(searchText)
        }
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "slash.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.red)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Server Ban List")
                            .font(.headline.bold())
                        Text("Manage network IP bans, certificate bans, and timeouts on this server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    store.requestBanList()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh ban list from server")

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))

            Divider()

            VStack(spacing: 14) {
                // Action Bar
                HStack {
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("Filter bans by IP or reason...", text: $searchText)
                            .textFieldStyle(.plain)
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(8)
                    .background(Color(NSColor.controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))

                    Button {
                        newIp = ""
                        newMask = 32
                        newReason = ""
                        selectedDurationPreset = .oneDay
                        showAddSheet = true
                    } label: {
                        Label("Add Ban", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                }

                HStack {
                    Text("\(filteredBans.count) Active Ban\(filteredBans.count == 1 ? "" : "s")")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                // Ban list table
                if filteredBans.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.raised.slash")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary.opacity(0.4))
                            .padding(.top, 36)

                        Text("No Active Bans")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        Text(searchText.isEmpty ? "There are currently no active bans on this server." : "No bans matched '\(searchText)'.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(filteredBans) { ban in
                            HStack(spacing: 12) {
                                Image(systemName: "shield.slash.fill")
                                    .foregroundStyle(.red)
                                    .font(.title3)

                                VStack(alignment: .leading, spacing: 3) {
                                    HStack(spacing: 6) {
                                        Text(formatIpWithMask(ip: ban.ip, mask: ban.mask))
                                            .font(.system(.body, design: .monospaced).bold())

                                        if !ban.name.isEmpty {
                                            Text("(\(ban.name))")
                                                .font(.caption.bold())
                                                .foregroundStyle(.secondary)
                                        }

                                        Text(formatDuration(seconds: ban.duration))
                                            .font(.system(size: 9, weight: .bold))
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 1)
                                            .background(ban.duration == 0 ? Color.red.opacity(0.18) : Color.orange.opacity(0.18), in: Capsule())
                                            .foregroundStyle(ban.duration == 0 ? Color.red : Color.orange)
                                    }

                                    HStack(spacing: 6) {
                                        if !ban.reason.isEmpty {
                                            Text("Reason: \(ban.reason)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        } else {
                                            Text("No reason specified")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }

                                        if !ban.start.isEmpty {
                                            Text("• Since: \(formatDate(ban.start))")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }

                                Spacer()

                                Button(role: .destructive) {
                                    banToRemove = ban
                                    showConfirmRemove = true
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red.opacity(0.8))
                                }
                                .buttonStyle(.borderless)
                                .help("Remove ban")
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.inset)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 560, height: 500)
        .onAppear {
            store.requestBanList()
        }
        .confirmationDialog(
            "Remove Ban",
            isPresented: $showConfirmRemove,
            presenting: banToRemove
        ) { target in
            Button("Remove Ban on '\(formatIpWithMask(ip: target.ip, mask: target.mask))'", role: .destructive) {
                store.removeBan(ip: target.ip, mask: target.mask)
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            Text("Are you sure you want to lift the ban on \(formatIpWithMask(ip: target.ip, mask: target.mask))?")
        }
        .sheet(isPresented: $showAddSheet) {
            VStack(spacing: 16) {
                HStack {
                    Text("Add IP Address Ban")
                        .font(.headline.bold())
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Target IP Address")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    HStack {
                        TextField("e.g. 192.168.1.100 or 10.0.0.0", text: $newIp)
                            .textFieldStyle(.roundedBorder)

                        Text("/")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        TextField("Mask", value: $newMask, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 55)
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ban Reason (optional)")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    TextField("Reason shown to banned user", text: $newReason)
                        .textFieldStyle(.roundedBorder)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Ban Duration")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)

                    Picker("Duration", selection: $selectedDurationPreset) {
                        ForEach(DurationPreset.allCases) { preset in
                            Text(preset.rawValue).tag(preset)
                        }
                    }
                    .pickerStyle(.segmented)

                    if selectedDurationPreset == .custom {
                        Stepper("Custom duration: \(customDurationHours) hour\(customDurationHours == 1 ? "" : "s")", value: $customDurationHours, in: 1...8760)
                            .font(.caption)
                    }
                }

                HStack {
                    Button("Cancel") {
                        showAddSheet = false
                    }
                    Spacer()
                    Button("Add Ban") {
                        let trimmed = newIp.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty {
                            let hours: UInt32 = selectedDurationPreset == .custom
                                ? UInt32(max(1, customDurationHours))
                                : selectedDurationPreset.hours
                            store.addBan(ip: trimmed, mask: UInt32(newMask), reason: newReason, durationHours: hours)
                            showAddSheet = false
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .disabled(newIp.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(.top, 8)
            }
            .padding(20)
            .frame(width: 420)
        }
    }

    private func formatIpWithMask(ip: String, mask: UInt32) -> String {
        if mask == 32 || mask == 128 {
            return ip
        }
        return "\(ip)/\(mask)"
    }

    private func formatDuration(seconds: UInt32) -> String {
        if seconds == 0 {
            return "PERMANENT"
        }
        let hours = seconds / 3600
        if hours < 24 {
            return "\(hours)h"
        }
        let days = hours / 24
        return "\(days)d"
    }

    private func formatDate(_ raw: String) -> String {
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFormatter.date(from: raw) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        isoFormatter.formatOptions = [.withInternetDateTime]
        if let date = isoFormatter.date(from: raw) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return raw.prefix(10).description
    }
}
