import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if SettingsState.shared.displayQuitConfirmation, let store = MumbleStore.shared, store.connectionStatus == .connected {
            let alert = NSAlert()
            alert.messageText = "Quit Swimble?"
            alert.informativeText = "You are currently connected to a server. Are you sure you want to disconnect and quit?"
            alert.alertStyle = .warning
            alert.addButton(withTitle: "Quit")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertSecondButtonReturn {
                return .terminateCancel
            }
        }

        if SettingsState.shared.clearChatWindowOnExit {
            MumbleStore.shared?.chatMessages.removeAll()
        }
        return .terminateNow
    }
}

@main
struct SwimbleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var store = MumbleStore()

    init() {
        switch SettingsState.shared.uiTheme {
        case "Dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case "Light":
            NSApp.appearance = NSAppearance(named: .aqua)
        default:
            NSApp.appearance = nil
        }
    }

    private var trayIcon: String {
        if SettingsState.shared.showTalkingStatusInTray && (store.audioEngine?.isTransmitting == true || store.users.contains(where: { $0.isTalking })) {
            return "mic.fill"
        } else if store.isSelfMuted {
            return "mic.slash.fill"
        } else if store.connectionStatus == .connected {
            return "waveform.circle.fill"
        } else {
            return "waveform.circle"
        }
    }

    var body: some Scene {
        // Main Application Window
        WindowGroup("Swimble") {
            ServerSplitView(store: store)
                .frame(minWidth: 820, minHeight: 540)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandMenu("Server") {
                Button("Connect...") {
                    store.activeModal = .serverConnect
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Disconnect") {
                    store.disconnect()
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(store.connectionStatus != .connected)

                Divider()

                Button("Information") {
                    store.activeModal = .serverInfo
                }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(store.connectionStatus != .connected)

                Button("Access Tokens...") {
                    store.activeModal = .accessTokens
                }
                .disabled(store.connectionStatus != .connected)

                Button("Registered Users...") {
                    store.activeModal = .registeredUsers
                }
                .disabled(store.connectionStatus != .connected)

                Button("Ban List...") {
                    store.activeModal = .banList
                }
                .disabled(store.connectionStatus != .connected)
            }

            CommandMenu("Self") {
                Button(store.isSelfMuted ? "Unmute Self" : "Mute Self") {
                    store.toggleSelfMute()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button(store.isSelfDeafened ? "Undeafen Self" : "Deafen Self") {
                    store.toggleSelfDeaf()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button(store.isMyPrioritySpeaker ? "Disable Priority Speaker" : "Enable Priority Speaker") {
                    store.toggleSelfPrioritySpeaker()
                }
                .disabled(store.connectionStatus != .connected)

                Button(store.isRecordingAudio ? "Stop Recording" : "Start Recording") {
                    store.toggleAudioRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Change Comment...") {
                    store.activeModal = .changeComment
                }
                .disabled(store.connectionStatus != .connected)

                Button("Remove Avatar") {
                    store.removeAvatar()
                }
                .disabled(store.connectionStatus != .connected)

                Button(store.isSelfRegistered ? "Registered" : "Register...") {
                    store.registerSelf()
                }
                .disabled(store.connectionStatus != .connected || store.isSelfRegistered)

                Divider()

                Button("Audio Statistics...") {
                    store.activeModal = .audioStatistics
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }

            CommandMenu("Configure") {
                Button("Audio Wizard...") {
                    store.activeModal = .audioWizard
                }

                Button("Certificate Wizard...") {
                    store.activeModal = .certificateWizard
                }

                Button("Text-to-Speech (TTS)...") {
                    store.activeModal = .ttsSettings
                }

                Button("Overlay...") {
                    store.activeModal = .overlaySettings
                }

                Divider()

                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
        }

        // Native Dedicated Settings Window (Cmd+,)
        Settings {
            SettingsView(store: store)
        }

        // Menu Bar Companion for Gaming & Background Control
        MenuBarExtra("Swimble", systemImage: trayIcon) {
            // Connection & Channel Status
            if store.connectionStatus == .connected {
                Text(store.activeBookmark?.name ?? "Connected")
                if let channelId = store.myChannelId {
                    Text("#\(store.channelName(for: channelId))")
                }
            } else if store.connectionStatus == .connecting {
                Text("Connecting...")
            } else {
                Text("Disconnected")
            }

            if SettingsState.shared.showUserNameWhenTalking {
                let talkingUsers = store.users.filter { $0.isTalking }.map { $0.name }
                if !talkingUsers.isEmpty {
                    Text("🗣️ " + talkingUsers.joined(separator: ", "))
                        .font(.caption)
                }
            }

            Divider()

            // Server Submenu
            Menu("Server") {
                if store.connectionStatus == .connected {
                    Button("Disconnect") {
                        store.disconnect()
                    }
                } else if let firstBm = store.bookmarks.first {
                    Button("Connect to \(firstBm.name)") {
                        store.connect(bookmark: firstBm)
                    }
                }

                Button("Server List...") {
                    store.activeModal = .serverConnect
                }

                Divider()

                Button("Information") {
                    store.activeModal = .serverInfo
                }
                .disabled(store.connectionStatus != .connected)

                Button("Access Tokens...") {
                    store.activeModal = .accessTokens
                }
                .disabled(store.connectionStatus != .connected)

                Button("Registered Users...") {
                    store.activeModal = .registeredUsers
                }
                .disabled(store.connectionStatus != .connected)

                Button("Ban List...") {
                    store.activeModal = .banList
                }
                .disabled(store.connectionStatus != .connected)
            }

            // Self Submenu
            Menu("Self") {
                Button(store.isSelfMuted ? "Unmute Self" : "Mute Self") {
                    store.toggleSelfMute()
                }

                Button(store.isSelfDeafened ? "Undeafen Self" : "Deafen Self") {
                    store.toggleSelfDeaf()
                }

                Divider()

                Button(store.isMyPrioritySpeaker ? "Disable Priority Speaker" : "Enable Priority Speaker") {
                    store.toggleSelfPrioritySpeaker()
                }
                .disabled(store.connectionStatus != .connected)

                Button(store.isRecordingAudio ? "Stop Recording" : "Start Recording") {
                    store.toggleAudioRecording()
                }

                Divider()

                Button("Change Comment...") {
                    store.activeModal = .changeComment
                }
                .disabled(store.connectionStatus != .connected)

                Button("Remove Avatar") {
                    store.removeAvatar()
                }
                .disabled(store.connectionStatus != .connected)

                Button(store.isSelfRegistered ? "Registered" : "Register...") {
                    store.registerSelf()
                }
                .disabled(store.connectionStatus != .connected || store.isSelfRegistered)

                Divider()

                Button("Audio Statistics...") {
                    store.activeModal = .audioStatistics
                }
            }

            // Configure Submenu
            Menu("Configure") {
                Button("Audio Wizard...") {
                    store.activeModal = .audioWizard
                }

                Button("Certificate Wizard...") {
                    store.activeModal = .certificateWizard
                }

                Button("Text-to-Speech (TTS)...") {
                    store.activeModal = .ttsSettings
                }

                Button("Overlay...") {
                    store.activeModal = .overlaySettings
                }

                Divider()

                Button("Settings...") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
            }

            Divider()

            // Quick Voice Toggles
            Button(store.isSelfMuted ? "Unmute Microphone" : "Mute Microphone") {
                store.toggleSelfMute()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])

            Button(store.isSelfDeafened ? "Undeafen Audio" : "Deafen Audio") {
                store.toggleSelfDeaf()
            }
            .keyboardShortcut("d", modifiers: [.command, .shift])

            Button("Toggle 'Who's Talking' Overlay") {
                FloatingOverlayManager.shared.toggle(store: store)
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Divider()

            Button("Quit Swimble") {
                if SettingsState.shared.displayQuitConfirmation && store.connectionStatus == .connected {
                    let alert = NSAlert()
                    alert.messageText = "Quit Swimble?"
                    alert.informativeText = "You are currently connected to a server. Are you sure you want to disconnect and quit?"
                    alert.alertStyle = .warning
                    alert.addButton(withTitle: "Quit")
                    alert.addButton(withTitle: "Cancel")
                    if alert.runModal() == .alertFirstButtonReturn {
                        NSApplication.shared.terminate(nil)
                    }
                } else {
                    NSApplication.shared.terminate(nil)
                }
            }
            .keyboardShortcut("q", modifiers: [.command])
        }
    }
}
