import SwiftUI
import AppKit

struct ShortcutRowView: View {
    let title: String
    let subtitle: String
    let action: KeybindAction
    let keybind: PTTKeybind?
    let defaultKeybind: PTTKeybind?
    let globalPTT: GlobalPTT
    let onResetOrClear: () -> Void

    var isRecording: Bool {
        globalPTT.activeRecordingAction == action
    }

    var displayLabel: String {
        if isRecording {
            return globalPTT.recordingPreviewString(for: action)
        }
        return keybind?.displayString ?? "None"
    }

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.bold())
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: {
                if isRecording {
                    globalPTT.activeRecordingAction = nil
                } else {
                    globalPTT.activeRecordingAction = action
                }
            }) {
                HStack(spacing: 6) {
                    if isRecording {
                        Image(systemName: "record.circle")
                            .symbolEffect(.pulse)
                    }
                    Text(displayLabel)
                        .bold()
                }
                .frame(minWidth: 140)
            }
            .buttonStyle(.borderedProminent)
            .tint(isRecording ? .orange : (keybind != nil ? .accentColor : .secondary.opacity(0.3)))

            if let defaultKey = defaultKeybind {
                if keybind != defaultKey {
                    Button("Reset") {
                        onResetOrClear()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            } else if keybind != nil {
                Button("Clear") {
                    onResetOrClear()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

/// Shortcuts settings tab featuring multi-column binding table, global shortcut toggles, and live hotkey recorder.
public struct ShortcutsSettingsTab: View {
    @Bindable public var store: MumbleStore
    @Bindable public var state: SettingsState = SettingsState.shared

    @State private var selectedShortcutId: UUID? = nil
    @State private var showingAddModal = false
    @State private var newFunction = "Push-to-Talk"
    @State private var newData = ""
    @State private var newShortcut = "Ctrl+Shift+T"
    @State private var newSuppress = false

    public init(store: MumbleStore) {
        self.store = store
    }

    private var globalPTT: GlobalPTT {
        store.globalPTT
    }

    private let availableFunctions = [
        "Push-to-Talk",
        "Push-to-Mute",
        "Toggle Self Mute",
        "Toggle Self Deafen",
        "Toggle Priority Speaker",
        "Whisper / Shout",
        "Volume Up",
        "Volume Down",
        "Toggle Game Overlay"
    ]

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Shortcut Bindings Table
                SettingsCard {
                    SettingsSectionHeader(
                        "Shortcut Bindings",
                        systemImage: "tablecells",
                        subtitle: "Assigned function hotkeys with optional channel/user target data and event suppression."
                    )

                    // Multi-Column Table
                    VStack(spacing: 0) {
                        // Header Row
                        HStack(spacing: 8) {
                            Text("Function")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 160, alignment: .leading)

                            Text("Data")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 110, alignment: .leading)

                            Text("Shortcut")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("Suppress")
                                .font(.caption.bold())
                                .foregroundStyle(.secondary)
                                .frame(width: 70, alignment: .center)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.8))

                        Divider()

                        // Rows
                        ForEach(state.shortcuts) { item in
                            HStack(spacing: 8) {
                                Text(item.function)
                                    .font(.system(size: 13, weight: .medium))
                                    .frame(width: 160, alignment: .leading)

                                Text(item.data.isEmpty ? "—" : item.data)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 110, alignment: .leading)

                                Text(item.shortcut)
                                    .font(.system(size: 12, design: .monospaced).bold())
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
                                    .frame(maxWidth: .infinity, alignment: .leading)

                                Image(systemName: item.suppress ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.suppress ? store.accentTint : Color.secondary.opacity(0.4))
                                    .frame(width: 70, alignment: .center)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(selectedShortcutId == item.id ? store.accentTint.opacity(0.15) : Color.clear)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                selectedShortcutId = item.id
                            }

                            Divider()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
                    }

                    // Add / Remove Buttons
                    HStack(spacing: 12) {
                        Button(action: { showingAddModal = true }) {
                            Label("Add Shortcut...", systemImage: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        Button(action: removeSelectedShortcut) {
                            Label("Remove", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(selectedShortcutId == nil)

                        Spacer()
                    }
                }

                // 2. Global Shortcut Controls
                SettingsCard {
                    SettingsSectionHeader(
                        "Global Shortcut Controls",
                        systemImage: "keyboard.fill",
                        subtitle: "Configure global keyboard hooking and auxiliary mouse button handling."
                    )

                    SettingsToggleRow(
                        "Enable Global Shortcuts",
                        subtitle: "Allows hotkeys to trigger even when other full-screen games or apps have focus.",
                        isOn: $state.enableGlobalShortcuts
                    )

                    SettingsToggleRow(
                        "Handle Side Mouse Buttons Inside Mumble",
                        subtitle: "Intercept mouse button 4 and 5 clicks for Push-to-Talk or whisper binds.",
                        isOn: $state.handleSideMouseButtons
                    )
                }

                // 3. Quick Hotkey Setup (PTT & Mute)
                SettingsCard {
                    SettingsSectionHeader(
                        "Quick Hotkeys",
                        systemImage: "command",
                        subtitle: "Quickly record Push-to-Talk and Mute hotkeys with single or multi-key combinations."
                    )

                    ShortcutRowView(
                        title: "Push-to-Talk",
                        subtitle: "Hold key combination to transmit audio while gaming.",
                        action: .ptt,
                        keybind: globalPTT.currentKeybind,
                        defaultKeybind: .defaultGrave,
                        globalPTT: globalPTT,
                        onResetOrClear: { globalPTT.currentKeybind = .defaultGrave }
                    )

                    Divider()

                    ShortcutRowView(
                        title: "Toggle Mute",
                        subtitle: "Mute or unmute your microphone globally.",
                        action: .mute,
                        keybind: globalPTT.muteToggleKeybind,
                        defaultKeybind: nil,
                        globalPTT: globalPTT,
                        onResetOrClear: { globalPTT.muteToggleKeybind = nil }
                    )

                    Divider()

                    ShortcutRowView(
                        title: "Toggle Deafen",
                        subtitle: "Mute all incoming audio and your microphone globally.",
                        action: .deafen,
                        keybind: globalPTT.deafenToggleKeybind,
                        defaultKeybind: nil,
                        globalPTT: globalPTT,
                        onResetOrClear: { globalPTT.deafenToggleKeybind = nil }
                    )
                }

                // 4. Accessibility Status
                SettingsCard {
                    HStack(spacing: 12) {
                        Image(systemName: globalPTT.isAccessibilityTrusted ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                            .font(.title2)
                            .foregroundStyle(globalPTT.isAccessibilityTrusted ? .green : .orange)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(globalPTT.isAccessibilityTrusted ? "Accessibility Permission Granted" : "Accessibility Permission Required")
                                .font(.headline)
                            Text("macOS requires Accessibility permissions for Swimble to intercept Push-to-Talk and hotkeys in the background while full-screen games are focused.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Check Again") {
                            globalPTT.refreshAccessibilityStatus()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }

                    if !globalPTT.isAccessibilityTrusted {
                        Button(action: {
                            globalPTT.openAccessibilitySettings()
                        }) {
                            Label("Open macOS System Settings", systemImage: "gearshape")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
        .sheet(isPresented: $showingAddModal) {
            VStack(spacing: 16) {
                Text("Add New Shortcut")
                    .font(.headline)

                Form {
                    Picker("Function", selection: $newFunction) {
                        ForEach(availableFunctions, id: \.self) { Text($0).tag($0) }
                    }

                    TextField("Target Data (Channel/User)", text: $newData)

                    TextField("Shortcut Keys (e.g. Space, Cmd+M)", text: $newShortcut)

                    Toggle("Suppress Event", isOn: $newSuppress)
                }
                .formStyle(.grouped)

                HStack {
                    Button("Cancel") { showingAddModal = false }
                    Spacer()
                    Button("Add") {
                        let newItem = ShortcutBindingItem(
                            function: newFunction,
                            data: newData,
                            shortcut: newShortcut,
                            suppress: newSuppress
                        )
                        state.shortcuts.append(newItem)
                        showingAddModal = false
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding(20)
            .frame(width: 400, height: 280)
        }
    }

    private func removeSelectedShortcut() {
        guard let id = selectedShortcutId else { return }
        state.shortcuts.removeAll(where: { $0.id == id })
        selectedShortcutId = nil
    }
}
