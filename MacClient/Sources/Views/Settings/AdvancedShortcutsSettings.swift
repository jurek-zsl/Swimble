import SwiftUI

struct AdvancedShortcutsSettings: View {
    @Bindable var store: MumbleStore
    @Bindable private var preferences = ClientPreferences.shared
    var body: some View {
        SettingsCard {
            SettingsSectionHeader("Actions and Whisper Presets", systemImage: "keyboard", subtitle: "Shortcuts control the last focused Swimble server window while a game is active.")
            ForEach($preferences.shortcuts) { $item in
                HStack {
                    Picker("Action", selection: $item.command) { ForEach(ShortcutCommand.allCases) { Text($0.rawValue).tag($0) } }.labelsHidden()
                    if item.command == .joinChannel || item.command == .toggleListening { channelPicker($item.channelId) }
                    ShortcutCaptureButton(shortcut: $item.shortcut)
                    Button("Remove") { preferences.shortcuts.removeAll { $0.id == item.id } }
                }
            }
            Button("Add Action") { var item = ActionShortcut(); item.serverKey = store.serverPreferenceKey; preferences.shortcuts.append(item) }
            Divider()
            ForEach($preferences.whisperPresets) { $preset in
                DisclosureGroup(preset.name) {
                    TextField("Name", text: $preset.name)
                    Text("Server: \(preset.serverKey)").font(.caption).foregroundStyle(.secondary)
                    Picker("Target channel", selection: $preset.channelId) {
                        Text("Only selected users").tag(UInt32?.none)
                        ForEach(store.channels, id: \.id) { Text($0.name).tag(Optional($0.id)) }
                    }
                    TextField("ACL group (optional)", text: $preset.group)
                    Toggle("Include subchannels", isOn: $preset.children)
                    Toggle("Include linked channels", isOn: $preset.links)
                    ForEach(store.users.filter { $0.certHash != nil }, id: \.sessionId) { user in
                        Toggle(store.displayName(user), isOn: Binding(get: { preset.userHashes.contains(user.certHash!) }, set: { selected in
                            if selected { preset.userHashes.append(user.certHash!) } else { preset.userHashes.removeAll { $0 == user.certHash! } }
                        }))
                    }
                    HStack { ShortcutCaptureButton(shortcut: $preset.shortcut); Spacer(); Button("Remove Preset") { preferences.whisperPresets.removeAll { $0.id == preset.id } } }
                }
            }
            Button("Add Whisper Preset") { var preset = WhisperPreset(); preset.serverKey = store.serverPreferenceKey; preferences.whisperPresets.append(preset) }.disabled(preferences.whisperPresets.count >= 28 || store.activeBookmark == nil)
        }
    }
    private func channelPicker(_ value: Binding<UInt32>) -> some View {
        Picker("Channel", selection: value) { ForEach(store.channels, id: \.id) { Text($0.name).tag($0.id) } }.labelsHidden()
    }
}
struct ShortcutCaptureButton: View {
    @Binding var shortcut: PTTKeybind?
    @State private var recording = false
    var body: some View {
        Button(recording ? "Press a key or mouse button…" : shortcut?.displayString ?? "Record shortcut") {
            recording = true
            GlobalPTT.shared.customRecorder = { value in shortcut = value; recording = false }
            GlobalPTT.shared.activeRecordingAction = .custom
        }
        .onChange(of: GlobalPTT.shared.activeRecordingAction) { _, action in
            if action != .custom { recording = false }
        }
        .onDisappear { if recording { GlobalPTT.shared.customRecorder = nil; GlobalPTT.shared.activeRecordingAction = nil } }
    }
}
