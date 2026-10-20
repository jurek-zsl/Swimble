import SwiftUI

/// Microphone preview is scoped to audio settings, never unrelated tabs.
struct AudioPreviewLifecycle: ViewModifier {
    @Bindable var store: MumbleStore
    let tab: SettingsTab
    @State private var active = false
    private var needsPreview: Bool { tab == .audioInput || tab == .audioOutput }
    func body(content: Content) -> some View {
        content.onAppear { update() }
            .onChange(of: tab) { _, _ in update() }
            .onDisappear { end() }
    }
    private func update() {
        if needsPreview && !active { active = true; store.audioEngine.beginPreview() }
        else if !needsPreview { end() }
    }
    private func end() {
        guard active else { return }
        active = false
        SettingsState.shared.loopbackMode = .none
        store.client.setLoopbackMode(mode: 0)
        store.audioEngine.endPreview()
    }
}
