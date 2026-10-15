import SwiftUI
import AppKit

@main
struct SwimbleApp: App {
    @State private var store = MumbleStore()

    var body: some Scene {
        // Main Application Window
        WindowGroup("Swimble") {
            ServerSplitView(store: store)
                .frame(minWidth: 780, minHeight: 520)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)

        // Menu Bar Companion for Gaming & Background Control
        MenuBarExtra("Swimble", systemImage: store.isSelfMuted ? "mic.slash.fill" : "waveform.circle.fill") {
            VStack {
                // Connection & Channel Status
                if store.connectionStatus == .connected {
                    Text("\(store.activeBookmark?.name ?? "Connected")")
                        .font(.headline)

                    let channelName: String = {
                        if let myId = store.mySessionId,
                           let me = store.users.first(where: { $0.sessionId == myId }),
                           let ch = store.channels.first(where: { $0.id == me.channelId }) {
                            return "#\(ch.name)"
                        }
                        return "#Root"
                    }()
                    Text(channelName)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    // Speaking Indicators
                    let speaking = store.users.filter { $0.isTalking }
                    if !speaking.isEmpty {
                        Divider()
                        Text("Talking: \(speaking.map { $0.name }.joined(separator: ", "))")
                            .font(.caption.bold())
                            .foregroundStyle(.green)
                    }
                } else if store.connectionStatus == .connecting {
                    Text("Connecting...")
                        .font(.headline)
                } else {
                    Text("Disconnected")
                        .font(.headline)
                        .foregroundStyle(.secondary)
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

                Divider()

                // "Who's Talking" Game Overlay Toggle
                Button("Toggle 'Who's Talking' Overlay") {
                    FloatingOverlayManager.shared.toggle(store: store)
                }
                .keyboardShortcut("o", modifiers: [.command, .shift])

                Divider()

                // Connection Actions
                if store.connectionStatus == .connected {
                    Button("Disconnect") {
                        store.disconnect()
                    }
                } else if let firstBm = store.bookmarks.first {
                    Button("Connect to \(firstBm.name)") {
                        store.connect(bookmark: firstBm)
                    }
                }

                Divider()

                Button("Quit Swimble") {
                    NSApplication.shared.terminate(nil)
                }
                .keyboardShortcut("q", modifiers: [.command])
            }
        }
    }
}
