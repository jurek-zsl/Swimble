import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        switch SettingsState.shared.uiTheme {
        case "Dark":
            NSApp.appearance = NSAppearance(named: .darkAqua)
        case "Light":
            NSApp.appearance = NSAppearance(named: .aqua)
        default:
            NSApp.appearance = nil
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            MumbleURLHandler.shared.handle(url: url)
        }
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let anyConnected = MumbleStore.activeStores.contains(where: { $0.connectionStatus == .connected })
        if SettingsState.shared.displayQuitConfirmation && anyConnected {
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
            for s in MumbleStore.activeStores {
                s.chatMessages.removeAll()
            }
        }
        return .terminateNow
    }
}

// MARK: - Focused Value for Active Window Store

struct FocusedMumbleStoreKey: FocusedValueKey {
    typealias Value = MumbleStore
}

extension FocusedValues {
    var mumbleStore: MumbleStore? {
        get { self[FocusedMumbleStoreKey.self] }
        set { self[FocusedMumbleStoreKey.self] = newValue }
    }
}

// MARK: - Main Application

@main
struct SwimbleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @FocusedValue(\.mumbleStore) private var focusedStore: MumbleStore?

    private var activeStore: MumbleStore? {
        focusedStore ?? MumbleStore.shared
    }

    private var trayIcon: String {
        let store = activeStore
        if SettingsState.shared.showTalkingStatusInTray && (store?.audioEngine?.isTransmitting == true || store?.users.contains(where: { $0.isTalking }) == true) {
            return "mic.fill"
        } else if store?.isSelfMuted == true {
            return "mic.slash.fill"
        } else if store?.connectionStatus == .connected {
            return "waveform.circle.fill"
        } else {
            return "waveform.circle"
        }
    }

    var body: some Scene {
        // Main Application Window (Multi-Server Tab / Window Support)
        WindowGroup("Swimble") {
            ServerWindowView()
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Server Tab") {
                    NSApp.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("t", modifiers: .command)

                Button("New Server Window") {
                    NSApp.sendAction(#selector(NSDocumentController.newDocument(_:)), to: nil, from: nil)
                }
                .keyboardShortcut("n", modifiers: .command)
            }

            CommandMenu("Server") {
                Button("Connect...") {
                    activeStore?.activeModal = .serverConnect
                }
                .keyboardShortcut("o", modifiers: [.command])

                Button("Open Mumble Link...") {
                    activeStore?.activeModal = .openMumbleLink
                }
                .keyboardShortcut("l", modifiers: [.command])

                Button("Disconnect") {
                    activeStore?.disconnect()
                }
                .keyboardShortcut("d", modifiers: [.command])
                .disabled(activeStore?.connectionStatus != .connected)

                Divider()

                Button("Information") {
                    activeStore?.activeModal = .serverInfo
                }
                .keyboardShortcut("i", modifiers: [.command])
                .disabled(activeStore?.connectionStatus != .connected)

                Button("Access Tokens...") {
                    activeStore?.activeModal = .accessTokens
                }
                .disabled(activeStore?.connectionStatus != .connected)

                Button("Registered Users...") {
                    activeStore?.activeModal = .registeredUsers
                }
                .disabled(activeStore?.connectionStatus != .connected)

                Button("Ban List...") {
                    activeStore?.activeModal = .banList
                }
                .disabled(activeStore?.connectionStatus != .connected)
            }

            CommandMenu("Self") {
                Button(activeStore?.isSelfMuted == true ? "Unmute Self" : "Mute Self") {
                    activeStore?.toggleSelfMute()
                }
                .keyboardShortcut("m", modifiers: [.command, .shift])

                Button(activeStore?.isSelfDeafened == true ? "Undeafen Self" : "Deafen Self") {
                    activeStore?.toggleSelfDeaf()
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Divider()

                Button(activeStore?.isMyPrioritySpeaker == true ? "Disable Priority Speaker" : "Enable Priority Speaker") {
                    activeStore?.toggleSelfPrioritySpeaker()
                }
                .disabled(activeStore?.connectionStatus != .connected)

                Button(activeStore?.isRecordingAudio == true ? "Stop Recording" : "Start Recording") {
                    activeStore?.toggleAudioRecording()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])

                Divider()

                Button("Change Comment...") {
                    activeStore?.activeModal = .changeComment
                }
                .disabled(activeStore?.connectionStatus != .connected)

                Button("Remove Avatar") {
                    activeStore?.removeAvatar()
                }
                .disabled(activeStore?.connectionStatus != .connected)

                Button(activeStore?.isSelfRegistered == true ? "Registered" : "Register...") {
                    activeStore?.registerSelf()
                }
                .disabled(activeStore?.connectionStatus != .connected || activeStore?.isSelfRegistered == true)

                Divider()

                Button("Audio Statistics...") {
                    activeStore?.activeModal = .audioStatistics
                }
                .keyboardShortcut("s", modifiers: [.command, .option])
            }

            CommandMenu("Configure") {
                Button("Audio Wizard...") {
                    activeStore?.activeModal = .audioWizard
                }

                Button("Certificate Wizard...") {
                    activeStore?.activeModal = .certificateWizard
                }

                Button("Text-to-Speech (TTS)...") {
                    activeStore?.activeModal = .ttsSettings
                }

                Button("Overlay...") {
                    activeStore?.activeModal = .overlaySettings
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
            if let store = activeStore {
                SettingsView(store: store)
            } else {
                Text("No active session")
                    .padding(40)
            }
        }

        // Menu Bar Companion for Gaming & Background Control
        MenuBarExtra("Swimble", systemImage: trayIcon) {
            if let store = activeStore {
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
            }

            Divider()

            Button("Quit Swimble") {
                let anyConnected = MumbleStore.activeStores.contains(where: { $0.connectionStatus == .connected })
                if SettingsState.shared.displayQuitConfirmation && anyConnected {
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

// MARK: - Server Window View (Native Tab Container)

struct ServerWindowView: View {
    @State private var store = MumbleStore()
    @State private var didPromptInitialConnect = false

    var body: some View {
        ServerSplitView(store: store)
            .frame(minWidth: 820, minHeight: 540)
            .focusedValue(\.mumbleStore, store)
            .navigationTitle(store.activeBookmark?.name ?? (store.connectionStatus == .connected ? "Connected" : "Swimble"))
            .onOpenURL { url in
                MumbleURLHandler.shared.handle(url: url)
            }
            .onAppear {
                if let pending = MumbleURLHandler.shared.consumePendingLink() {
                    didPromptInitialConnect = true
                    store.activeModal = nil
                    store.handleMumbleLink(pending)
                } else if store.connectionStatus == .disconnected && !didPromptInitialConnect {
                    didPromptInitialConnect = true
                    store.activeModal = .serverConnect
                }
            }
            .onDisappear {
                store.disconnect()
            }
    }
}
