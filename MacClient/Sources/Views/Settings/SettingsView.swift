import SwiftUI
import AppKit

private struct RemoveSettingsToolbar: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.toolbar = nil
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            if window.toolbar != nil {
                window.toolbar = nil
            }
        }
    }
}

/// Native macOS Settings Window View hosting all configuration tabs and footer actions.
public struct SettingsView: View {
    @Bindable public var store: MumbleStore
    @State private var newTokenText: String = ""
    @Environment(\.dismiss) private var dismiss

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        NavigationSplitView(columnVisibility: .constant(.all)) {
            List(SettingsTab.allCases, selection: $store.selectedSettingsTab) { tab in
                Label(tab.rawValue, systemImage: tab.iconName)
                    .font(.system(size: 13, weight: .medium))
                    .padding(.vertical, 2)
                    .tag(tab)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
            .toolbar(removing: .sidebarToggle)
        } detail: {
            VStack(spacing: 0) {
                // Header Bar
                HStack {
                    HStack(spacing: 8) {
                        Image(systemName: store.selectedSettingsTab.iconName)
                            .font(.title3)
                            .foregroundStyle(store.accentTint)
                        Text(store.selectedSettingsTab.rawValue)
                            .font(.title3.bold())
                    }
                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 14)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.85))

                Divider()

                // Content View for Selected Tab
                Group {
                    switch store.selectedSettingsTab {
                    case .audioInput:
                        AudioInputSettingsTab(store: store)
                    case .audioOutput:
                        AudioOutputSettingsTab(store: store)
                    case .userInterface:
                        UserInterfaceSettingsTab(store: store)
                    case .shortcuts:
                        ShortcutsSettingsTab(store: store)
                    case .network:
                        NetworkSettingsTab(store: store)
                    case .messages:
                        MessagesSettingsTab(store: store)
                    case .overlay:
                        OverlaySettingsTab(store: store)
                    case .tokens:
                        AccessTokensSettingsTab(store: store, newTokenText: $newTokenText)
                    case .certificates:
                        CertificatesSettingsTab(store: store)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                Divider()

                // 8. Settings Footer Actions
                SettingsFooterView(store: store, currentTab: store.selectedSettingsTab) {
                    dismiss()
                }
            }
        }
        .toolbar(removing: .sidebarToggle)
        .background(RemoveSettingsToolbar())
        .frame(minWidth: 840, idealWidth: 900, minHeight: 620, idealHeight: 680)
        .modifier(AudioPreviewLifecycle(store: store, tab: store.selectedSettingsTab))
        .onDisappear {
            SettingsState.shared.apply(to: store)
        }
    }
}
