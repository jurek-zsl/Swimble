import SwiftUI

/// Overlay Configuration dialog managing the floating "Who's Talking" in-game HUD.
public struct OverlaySettingsModal: View {
    @Bindable public var store: MumbleStore
    @Environment(\.dismiss) private var dismiss

    @ObservedObject private var overlayManager = FloatingOverlayManager.shared

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "pip.fill")
                        .font(.title2)
                        .foregroundStyle(store.accentTint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Game Overlay ('Who's Talking')")
                            .font(.headline.bold())
                        Text("Always-on-top floating HUD showing speaking users and voice state.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))

            Divider()

            VStack(spacing: 16) {
                // 1. Overlay Visibility Toggle
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Overlay Status")
                                .font(.subheadline.bold())
                            Text(overlayManager.isVisible ? "Floating overlay is currently visible on screen." : "Overlay is currently hidden.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button(overlayManager.isVisible ? "Hide Overlay" : "Show Overlay") {
                            overlayManager.toggle(store: store)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(overlayManager.isVisible ? .orange : store.accentTint)
                    }
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }

                // 2. Features & Controls Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Overlay Features & Shortcuts")
                        .font(.subheadline.bold())

                    HStack(spacing: 8) {
                        Image(systemName: "hand.draw.fill")
                            .foregroundStyle(store.accentTint)
                        Text("Drag anywhere on the pill to position it over your game.")
                            .font(.caption)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .foregroundStyle(store.accentTint)
                        Text("Click the expand arrow to toggle between compact pill and full user list.")
                            .font(.caption)
                    }

                    HStack(spacing: 8) {
                        Image(systemName: "command")
                            .foregroundStyle(store.accentTint)
                        Text("Global shortcut: Cmd + Shift + O toggles the overlay instantly.")
                            .font(.caption)
                    }

                    Divider()

                    Button("Reset Overlay Position to Top-Left") {
                        overlayManager.resetPosition()
                    }
                    .buttonStyle(.bordered)
                }
                .padding(14)
                .background(Color(NSColor.controlBackgroundColor).opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
                .overlay {
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
            }
            .padding(20)
        }
        .frame(width: 480, height: 360)
    }
}
