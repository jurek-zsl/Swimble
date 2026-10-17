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

/// Native Shortcuts settings tab with global CGEvent hotkey recorders and Accessibility verification.
public struct ShortcutsSettingsTab: View {
    @Bindable public var store: MumbleStore
    @Bindable public var state: SettingsState = SettingsState.shared

    public init(store: MumbleStore) {
        self.store = store
    }

    private var globalPTT: GlobalPTT {
        store.globalPTT
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Global Controls & Accessibility
                SettingsCard {
                    SettingsSectionHeader(
                        "Global Hotkey Controls",
                        systemImage: "keyboard.fill",
                        subtitle: "Enable background system-wide keyboard interception and mouse side buttons."
                    )

                    SettingsToggleRow(
                        "Enable Global Shortcuts",
                        subtitle: "Allows hotkeys to trigger even when other full-screen games or apps have focus.",
                        isOn: $state.enableGlobalShortcuts
                    )

                    SettingsToggleRow(
                        "Handle Side Mouse Buttons Inside Swimble",
                        subtitle: "Intercept mouse button 4 and 5 clicks for Push-to-Talk or whisper binds.",
                        isOn: $state.handleSideMouseButtons
                    )
                }

                // 2. Global Hotkey Bindings
                SettingsCard {
                    SettingsSectionHeader(
                        "Global Keybinds",
                        systemImage: "command",
                        subtitle: "Click any button below and press a key or modifier combination to record."
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
                        title: "Push-to-Whisper",
                        subtitle: "Hold key combination to whisper directly to target participants.",
                        action: .whisper,
                        keybind: globalPTT.whisperKeybind,
                        defaultKeybind: nil,
                        globalPTT: globalPTT,
                        onResetOrClear: { globalPTT.whisperKeybind = nil }
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

                    Divider()

                    ShortcutRowView(
                        title: "Toggle Game Overlay",
                        subtitle: "Show or hide the floating 'Who's Talking' HUD.",
                        action: .overlay,
                        keybind: globalPTT.overlayToggleKeybind,
                        defaultKeybind: nil,
                        globalPTT: globalPTT,
                        onResetOrClear: { globalPTT.overlayToggleKeybind = nil }
                    )
                }

                // 3. macOS Accessibility Status
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
                        Divider()

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
    }
}
