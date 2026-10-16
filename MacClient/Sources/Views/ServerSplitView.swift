import SwiftUI

/// Main application view container hosting the ChannelTreeSidebar, ChatAndActivityView,
/// and the overlaid FloatingVoiceHUD.
public struct ServerSplitView: View {
    @Bindable public var store: MumbleStore
    @State private var showConnectSheet: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @Environment(\.openSettings) private var openSettings

    public init(store: MumbleStore) {
        self.store = store
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ChannelTreeSidebar(store: store, showConnectSheet: $showConnectSheet)
                .frame(minWidth: 220, idealWidth: 260)
        } detail: {
            ChatAndActivityView(store: store, showConnectSheet: $showConnectSheet)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .sheet(isPresented: $showConnectSheet) {
            ServerConnectSheet(store: store)
        }
        .sheet(item: $store.activeModal) { modal in
            Group {
                switch modal {
                case .serverConnect:
                    ServerConnectSheet(store: store)
                case .serverInfo:
                    ServerInformationModal(store: store)
                case .accessTokens:
                    AccessTokensModal(store: store)
                case .registeredUsers:
                    RegisteredUsersModal(store: store)
                case .banList:
                    BanListModal(store: store)
                case .changeComment:
                    ChangeCommentModal(store: store)
                case .audioStatistics:
                    AudioStatisticsModal(store: store)
                case .audioWizard:
                    AudioWizardModal(store: store)
                case .certificateWizard:
                    CertificateWizardModal(store: store)
                case .ttsSettings:
                    TTSModal(store: store)
                case .overlaySettings:
                    OverlaySettingsModal(store: store)
                }
            }
        }
        .toolbar {
            if store.isRecordingAudio {
                ToolbarItem(placement: .status) {
                    Button(action: {
                        store.toggleAudioRecording()
                    }) {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(Color.red)
                                .frame(width: 8, height: 8)
                            Text("REC \(formatDuration(store.recordingDuration))")
                                .font(.caption.monospacedDigit().bold())
                                .foregroundStyle(.red)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Voice chat recording in progress. Click to stop and save.")
                }
            }

            ToolbarItem(placement: .automatic) {
                Menu {
                    Button(action: { store.activeModal = .serverInfo }) {
                        Label("Server Information", systemImage: "info.circle")
                    }
                    .disabled(store.connectionStatus != .connected)

                    Button(action: { store.activeModal = .accessTokens }) {
                        Label("Access Tokens...", systemImage: "key.fill")
                    }
                    .disabled(store.connectionStatus != .connected)

                    Button(action: { store.activeModal = .registeredUsers }) {
                        Label("Registered Users...", systemImage: "person.2.fill")
                    }
                    .disabled(store.connectionStatus != .connected)

                    Button(action: { store.activeModal = .banList }) {
                        Label("Ban List...", systemImage: "slash.circle.fill")
                    }
                    .disabled(store.connectionStatus != .connected)

                    Divider()

                    Button(action: { store.activeModal = .audioStatistics }) {
                        Label("Audio Statistics...", systemImage: "waveform.path.ecg")
                    }

                    Button(action: { store.activeModal = .audioWizard }) {
                        Label("Audio Wizard...", systemImage: "wand.and.stars")
                    }

                    Button(action: { store.activeModal = .certificateWizard }) {
                        Label("Certificate Wizard...", systemImage: "lock.shield")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .help("Server & Audio Actions")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    FloatingOverlayManager.shared.toggle(store: store)
                }) {
                    Image(systemName: "pip.fill")
                }
                .help("Toggle 'Who's Talking' Game Overlay (Cmd+Shift+O)")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    showConnectSheet = true
                }) {
                    Image(systemName: "server.rack")
                }
                .help("Manage Servers & Bookmarks")
            }

            ToolbarItem(placement: .automatic) {
                Button(action: {
                    store.selectedSettingsTab = .general
                    openSettings()
                }) {
                    Image(systemName: "gearshape")
                }
                .help("Settings (Cmd+,)")
            }
        }
    }
}
