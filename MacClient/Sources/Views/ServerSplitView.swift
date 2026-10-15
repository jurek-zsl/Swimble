import SwiftUI

/// Main application view container hosting the ChannelTreeSidebar, ChatAndActivityView,
/// and the overlaid FloatingVoiceHUD.
public struct ServerSplitView: View {
    @Bindable public var store: MumbleStore
    @State private var showConnectSheet: Bool = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            ChannelTreeSidebar(store: store, showConnectSheet: $showConnectSheet)
                .frame(minWidth: 200, idealWidth: 240)
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
                .help("Toggle 'Who's Talking' Game Overlay")
            }
        }
    }
}
