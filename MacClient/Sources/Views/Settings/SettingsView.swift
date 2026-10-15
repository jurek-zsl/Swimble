import SwiftUI

/// Native macOS Settings Window View hosting all configuration tabs.
public struct SettingsView: View {
    @Bindable public var store: MumbleStore
    @State private var newTokenText: String = ""
    private var deviceManager = CoreAudioDeviceManager.shared

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        TabView(selection: $store.selectedSettingsTab) {
            GeneralSettingsTab(store: store)
                .tabItem {
                    Label(SettingsTab.general.rawValue, systemImage: SettingsTab.general.iconName)
                }
                .tag(SettingsTab.general)

            AudioSettingsTab(store: store, deviceManager: deviceManager)
                .tabItem {
                    Label(SettingsTab.audio.rawValue, systemImage: SettingsTab.audio.iconName)
                }
                .tag(SettingsTab.audio)

            ShortcutsSettingsTab(store: store)
                .tabItem {
                    Label(SettingsTab.shortcuts.rawValue, systemImage: SettingsTab.shortcuts.iconName)
                }
                .tag(SettingsTab.shortcuts)

            AccessTokensSettingsTab(store: store, newTokenText: $newTokenText)
                .tabItem {
                    Label(SettingsTab.tokens.rawValue, systemImage: SettingsTab.tokens.iconName)
                }
                .tag(SettingsTab.tokens)

            CertificatesSettingsTab(store: store)
                .tabItem {
                    Label(SettingsTab.certificates.rawValue, systemImage: SettingsTab.certificates.iconName)
                }
                .tag(SettingsTab.certificates)
        }
        .frame(width: 620, height: 560)
    }
}
