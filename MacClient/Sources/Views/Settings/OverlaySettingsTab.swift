import SwiftUI
import AppKit

/// Native Game Overlay settings tab with interactive screen quadrant positioning and appearance controls.
public struct OverlaySettingsTab: View {
    @Bindable public var store: MumbleStore
    @Bindable public var state: SettingsState = SettingsState.shared

    @State private var overlayColor: Color = .cyan

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Overlay Options
                SettingsCard {
                    SettingsSectionHeader(
                        "Overlay Status",
                        systemImage: "pip.fill",
                        subtitle: "Always-on-top floating HUD displaying who's talking during gameplay."
                    )

                    SettingsToggleRow(
                        "Enable Game Overlay",
                        subtitle: "Display floating Liquid Glass HUD on top of full-screen games and desktop apps.",
                        isOn: $state.overlayEnabled
                    )
                }

                // 2. Interactive Screen Positioning Preview Widget
                SettingsCard {
                    SettingsSectionHeader(
                        "Screen Positioning",
                        systemImage: "display",
                        subtitle: "Click a screen quadrant to align the HUD on your display."
                    )

                    VStack(spacing: 12) {
                        ZStack {
                            // Monitor Bezel
                            RoundedRectangle(cornerRadius: 12)
                                .fill(Color(NSColor.windowBackgroundColor).opacity(0.85))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 12)
                                        .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1.5)
                                }
                                .frame(height: 180)

                            // 4 Quadrants Clickable Grid
                            VStack(spacing: 8) {
                                HStack(spacing: 8) {
                                    quadrantButton(preset: .topLeft, label: "Top-Left")
                                    quadrantButton(preset: .topRight, label: "Top-Right")
                                }
                                HStack(spacing: 8) {
                                    quadrantButton(preset: .bottomLeft, label: "Bottom-Left")
                                    quadrantButton(preset: .bottomRight, label: "Bottom-Right")
                                }
                            }
                            .padding(14)
                        }

                        HStack {
                            Text("Current Position: \(state.overlayPositionPreset.rawValue)")
                                .font(.caption.bold())
                                .foregroundStyle(store.accentTint)
                            Spacer()
                            Text("You can also freely drag the HUD across screens.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // 3. Status Badges & Appearance
                SettingsCard {
                    SettingsSectionHeader(
                        "Appearance & Elements",
                        systemImage: "paintpalette.fill",
                        subtitle: "Configure FPS counter, clock display, and HUD accent color."
                    )

                    SettingsToggleRow(
                        "Show Frames Per Second (FPS) Counter",
                        subtitle: "Displays live rendering refresh rate in the corner of the overlay.",
                        isOn: $state.showFpsCounter
                    )

                    SettingsToggleRow(
                        "Show Digital Clock",
                        subtitle: "Displays the current digital time inside the floating HUD.",
                        isOn: $state.showCurrentTime
                    )

                    Divider()

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Overlay Accent Color")
                                .font(.subheadline.bold())
                            ColorPicker("Accent Color", selection: $overlayColor)
                                .labelsHidden()
                                .onChange(of: overlayColor) { _, newColor in
                                    state.overlayColorHex = newColor.toSwimbleHex()
                                }
                        }
                        Spacer()
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .onAppear {
                overlayColor = Color.swimbleHex(state.overlayColorHex)
            }
        }
    }

    @ViewBuilder
    private func quadrantButton(preset: OverlayPositionPreset, label: String) -> some View {
        Button(action: {
            state.overlayPositionPreset = preset
            FloatingOverlayManager.shared.applyPosition(preset: preset)
        }) {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(state.overlayPositionPreset == preset ? store.accentTint.opacity(0.2) : Color.primary.opacity(0.04))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(state.overlayPositionPreset == preset ? store.accentTint : Color.primary.opacity(0.12), lineWidth: state.overlayPositionPreset == preset ? 1.5 : 0.8)
                    }

                VStack(spacing: 4) {
                    Image(systemName: iconForQuadrant(preset))
                        .font(.title3)
                        .foregroundStyle(state.overlayPositionPreset == preset ? store.accentTint : Color.secondary)
                    Text(label)
                        .font(.caption.bold())
                        .foregroundStyle(state.overlayPositionPreset == preset ? Color.primary : Color.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func iconForQuadrant(_ preset: OverlayPositionPreset) -> String {
        switch preset {
        case .topLeft: return "arrow.up.left.circle.fill"
        case .topRight: return "arrow.up.right.circle.fill"
        case .bottomLeft: return "arrow.down.left.circle.fill"
        case .bottomRight: return "arrow.down.right.circle.fill"
        case .custom: return "hand.point.up.left.fill"
        }
    }
}
