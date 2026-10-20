import SwiftUI
import AppKit

struct AudioQualitySettings: View {
    @Bindable private var preferences = ClientPreferences.shared
    var body: some View {
        SettingsCard {
            SettingsSectionHeader("Encoding Quality", systemImage: "waveform", subtitle: "Swimble lowers the bitrate when required by the server's bandwidth limit.")
            HStack { Text("Opus bitrate"); Spacer(); Text("\(preferences.bitrateKbps) kbit/s") }
            Slider(value: Binding(get: { Double(preferences.bitrateKbps) }, set: { preferences.bitrateKbps = Int($0) }), in: 6...128, step: 2)
            Picker("Audio per packet", selection: $preferences.packetDurationMs) {
                ForEach([10, 20, 40, 60], id: \.self) { Text("\($0) ms").tag($0) }
            }
            Toggle("Opus forward error correction", isOn: $preferences.forwardErrorCorrection)
            Text("Shorter packets reduce latency. Longer packets reduce transport overhead. FEC helps recover isolated lost packets.").font(.caption).foregroundStyle(.secondary)
        }
    }
}
struct PositionalAudioSettings: View {
    @Bindable var store: MumbleStore
    @Bindable private var preferences = ClientPreferences.shared
    @State private var pluginStatus = ""
    @State private var diagnostics = ""
    var body: some View {
        SettingsCard {
            SettingsSectionHeader("Positional Audio Controls", systemImage: "location.circle", subtitle: "Distances use game-world meters. Stereo rendering does not use head tracking.")
            HStack {
                TextField("Near distance", value: $preferences.minimumDistance, format: .number)
                TextField("Far distance", value: $preferences.maximumDistance, format: .number)
            }
            HStack { Text("Volume at far distance"); Slider(value: $preferences.farVolume, in: 0...1) }
            HStack { Text("Near-field stereo spread"); Slider(value: $preferences.positionalBloom, in: 0...1) }
            DisclosureGroup("Manual positioning") {
                Toggle("Use manual game position", isOn: $preferences.manualPositionEnabled)
                TextField("Shared context (same world/server)", text: $preferences.manualContext)
                HStack {
                    TextField("X", value: $preferences.manualX, format: .number)
                    TextField("Y", value: $preferences.manualY, format: .number)
                    TextField("Z", value: $preferences.manualZ, format: .number)
                    TextField("Heading °", value: $preferences.manualHeading, format: .number)
                }
            }
            DisclosureGroup("Native game plugins") {
                ForEach(preferences.pluginPaths, id: \.self) { path in
                    HStack {
                        Text(URL(fileURLWithPath: path).lastPathComponent)
                        Spacer()
                        Button("Enable") { pluginStatus = store.client.loadPositionalPlugin(path: path) }
                        Button("Remove") { store.client.unloadPositionalPlugin(); preferences.pluginPaths.removeAll { $0 == path } }
                    }
                }
                HStack {
                    Button("Add Plugin…") {
                        let panel = NSOpenPanel(); panel.allowsMultipleSelection = false; panel.canChooseDirectories = false
                        if panel.runModal() == .OK, let url = panel.url {
                            pluginStatus = store.client.loadPositionalPlugin(path: url.path)
                            if pluginStatus.hasPrefix("Loaded"), !preferences.pluginPaths.contains(url.path) { preferences.pluginPaths.append(url.path) }
                        }
                    }
                    Button("Unlink Plugin") { store.client.unloadPositionalPlugin(); pluginStatus = "Plugin unlinked." }
                }
                Text("Load trusted native macOS Mumble positional plugins. Windows binaries and game processes that macOS does not permit reading cannot be used.").font(.caption).foregroundStyle(.secondary)
                if !pluginStatus.isEmpty { Text(pluginStatus).font(.caption).textSelection(.enabled) }
            }
            Button("Refresh Positioning Diagnostics") { diagnostics = store.client.positioningDiagnostics() }
            if !diagnostics.isEmpty { Text(diagnostics).font(.caption.monospaced()).textSelection(.enabled) }
        }
    }
}
