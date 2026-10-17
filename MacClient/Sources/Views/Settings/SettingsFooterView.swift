import SwiftUI
import AppKit

/// Standardized Settings dialog footer bar hosting state and persistence actions.
public struct SettingsFooterView: View {
    @Bindable public var store: MumbleStore
    @Bindable public var state: SettingsState = SettingsState.shared
    public let currentTab: SettingsTab
    public let onDismiss: () -> Void

    @State private var feedbackText: String? = nil

    public init(store: MumbleStore, currentTab: SettingsTab, onDismiss: @escaping () -> Void) {
        self.store = store
        self.currentTab = currentTab
        self.onDismiss = onDismiss
    }

    public var body: some View {
        HStack(spacing: 10) {
            // Left Group: Reversion & Defaults
            Button("Reset") {
                state.resetToSnapshot()
                showFeedback("Reverted unsaved changes.")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Revert unsaved changes to the values when settings were opened.")

            Button("Restore Defaults") {
                state.restoreDefaults(for: currentTab)
                showFeedback("Restored defaults for \(currentTab.rawValue).")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Restore default values for the current active tab.")

            Button("Defaults (All)") {
                state.restoreAllDefaults()
                showFeedback("Restored defaults for all settings.")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Restore default values across all settings tabs.")

            if let fb = feedbackText {
                Text(fb)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
            }

            Spacer()

            // Right Group: Persistence & Dismissal
            Button("Apply") {
                state.apply(to: store)
                showFeedback("Settings applied.")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Apply changes immediately without closing the settings window.")

            Button("Cancel") {
                state.resetToSnapshot()
                onDismiss()
            }
            .keyboardShortcut(.cancelAction)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("Discard unsaved changes and close settings.")

            Button("OK") {
                state.apply(to: store)
                onDismiss()
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(store.accentTint)
            .help("Save all settings and close.")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.95))
    }

    private func showFeedback(_ text: String) {
        feedbackText = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            if feedbackText == text {
                feedbackText = nil
            }
        }
    }
}
