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
        .toolbar {
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
