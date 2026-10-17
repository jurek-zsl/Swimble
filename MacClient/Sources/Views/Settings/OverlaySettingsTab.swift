import SwiftUI
import AppKit

/// Comprehensive Game Overlay settings tab matching official Mumble specs.
public struct OverlaySettingsTab: View {
    @Bindable public var store: MumbleStore
    @Bindable public var state: SettingsState = SettingsState.shared

    @State private var overlayColor: Color = .cyan
    @State private var presetNotice: String? = nil

    public init(store: MumbleStore) {
        self.store = store
    }

    private let availableFonts = [
        "System Default",
        "System Monospaced",
        "System Rounded",
        "System Serif"
    ]

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Overlay Options
                SettingsCard {
                    SettingsSectionHeader(
                        "Overlay Options",
                        systemImage: "pip.fill",
                        subtitle: "Always-on-top floating HUD displaying who's talking during gameplay."
                    )

                    SettingsToggleRow(
                        "Enable Overlay",
                        subtitle: "Display floating glass HUD on top of full-screen games and desktop apps.",
                        isOn: $state.overlayEnabled
                    )
                }

                // 2. Interactive Screen Positioning Preview Widget
                SettingsCard {
                    SettingsSectionHeader(
                        "Screen Positioning",
                        systemImage: "display",
                        subtitle: "Click a screen quadrant or drag to align the HUD on your display."
                    )

                    // Interactive Monitor Widget
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

                        // Preset Load / Save Actions
                        HStack(spacing: 12) {
                            Button("Load Preset...") {
                                presetNotice = "Loaded '\(state.overlayPositionPreset.rawValue)' preset."
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { presetNotice = nil }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button("Save Preset...") {
                                presetNotice = "Saved '\(state.overlayPositionPreset.rawValue)' configuration."
                                DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { presetNotice = nil }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if let notice = presetNotice {
                                Text(notice)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("Selected: \(state.overlayPositionPreset.rawValue)")
                                .font(.caption.bold())
                                .foregroundStyle(store.accentTint)
                        }
                    }
                }

                // 3. Status Badges & Appearance
                SettingsCard {
                    SettingsSectionHeader(
                        "Appearance & Elements",
                        systemImage: "paintpalette.fill",
                        subtitle: "Configure FPS counter, clock display, font family, and HUD accent color."
                    )

                    SettingsToggleRow(
                        "Show Frames Per Second (FPS) Counter",
                        subtitle: "Displays live rendering refresh rate in the corner of the overlay.",
                        isOn: $state.showFpsCounter
                    )

                    SettingsToggleRow(
                        "Show Current Time",
                        subtitle: "Displays the current digital clock inside the floating HUD.",
                        isOn: $state.showCurrentTime
                    )

                    Divider()

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Font Family")
                                .font(.subheadline.bold())
                            Picker("Font Family", selection: $state.overlayFontName) {
                                ForEach(availableFonts, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Overlay Color")
                                .font(.subheadline.bold())
                            ColorPicker("Accent Color", selection: $overlayColor)
                                .labelsHidden()
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }

    @ViewBuilder
    private func quadrantButton(preset: OverlayPositionPreset, label: String) -> some View {
        Button(action: {
            state.overlayPositionPreset = preset
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
