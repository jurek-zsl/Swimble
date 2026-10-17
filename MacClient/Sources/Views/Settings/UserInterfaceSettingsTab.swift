import SwiftUI
import AppKit

/// Comprehensive User Interface settings tab matching official Mumble specs.
public struct UserInterfaceSettingsTab: View {
    @Bindable public var store: MumbleStore
    @Bindable public var state: SettingsState = SettingsState.shared

    public init(store: MumbleStore) {
        self.store = store
    }

    private let availableStyles = ["macOS Liquid Glass", "Default", "Compact", "High Contrast"]
    private let availableThemes = ["System Default", "Dark", "Light"]
    private let availableLanguages = ["System Default", "English", "Deutsch", "Français", "Español", "Polski", "日本語"]
    private let availableLayouts = ["Classic", "Stacked", "Hybrid", "Custom"]
    private let availableExpands = ["All", "None", "Only with Users"]
    private let availableDrags = ["Move", "Copy", "Disabled"]

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Application
                SettingsCard {
                    SettingsSectionHeader(
                        "Application",
                        systemImage: "app.badge.fill",
                        subtitle: "Visual style, appearance theme, language, and desktop badges."
                    )

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Style")
                                .font(.subheadline.bold())
                            Picker("Style", selection: $state.uiStyle) {
                                ForEach(availableStyles, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Theme")
                                .font(.subheadline.bold())
                            Picker("Theme", selection: $state.uiTheme) {
                                ForEach(availableThemes, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Language")
                                .font(.subheadline.bold())
                            Picker("Language", selection: $state.uiLanguage) {
                                ForEach(availableLanguages, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Divider()

                    SettingsToggleRow(
                        "Display Quit Confirmation Dialog on Close",
                        subtitle: "Prompts for confirmation before quitting when connected to a server.",
                        isOn: $state.displayQuitConfirmation
                    )

                    SettingsToggleRow(
                        "Include Unread Message Count in Taskbar / Dock Icon",
                        subtitle: "Shows a badge on the macOS Dock icon with the unread chat count.",
                        isOn: $state.includeUnreadCountInTaskbar
                    )
                }

                // 2. Layout
                SettingsCard {
                    SettingsSectionHeader(
                        "Layout",
                        systemImage: "macwindow.on.rectangle",
                        subtitle: "Window structure, layout presets, and menu bar shortcuts."
                    )

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Preset Layout")
                            .font(.subheadline.bold())
                        Picker("Layout", selection: $state.layoutPreset) {
                            ForEach(availableLayouts, id: \.self) { Text($0).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }

                    Divider()

                    SettingsToggleRow(
                        "Lock Layout",
                        subtitle: "Prevent accidental resizing or rearranging of sidebar columns.",
                        isOn: $state.lockLayout
                    )

                    SettingsToggleRow(
                        "Show Context Menu on Menu Bar",
                        subtitle: "Include channel and user action menus directly in the macOS menu bar.",
                        isOn: $state.showContextMenuOnMenuBar
                    )

                    SettingsToggleRow(
                        "Make Minimal View Look Like a Tooltip",
                        subtitle: "Display a minimal borderless floating widget instead of the full client.",
                        isOn: $state.minimalViewTooltip
                    )
                }

                // 3. Channel Tree
                SettingsCard {
                    SettingsSectionHeader(
                        "Channel Tree",
                        systemImage: "folder.fill.badge.gearshape",
                        subtitle: "Hierarchy expansion, sorting, drag & drop, and user tooltips."
                    )

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Expand Channels")
                                .font(.subheadline.bold())
                            Picker("Expand", selection: $state.channelTreeExpand) {
                                ForEach(availableExpands, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Channel Drag Action")
                                .font(.subheadline.bold())
                            Picker("Drag", selection: $state.channelDrag) {
                                ForEach(availableDrags, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("User Sort Order")
                            .font(.subheadline.bold())

                        HStack(spacing: 24) {
                            ForEach(UserSortMode.allCases) { mode in
                                HStack(spacing: 6) {
                                    Image(systemName: state.userSort == mode ? "largecircle.fill.circle" : "circle")
                                        .foregroundStyle(state.userSort == mode ? store.accentTint : .secondary)
                                    Text(mode.rawValue)
                                        .font(.body)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    state.userSort = mode
                                }
                            }
                        }
                    }

                    Divider()

                    SettingsToggleRow(
                        "Hover Over User Shows Volume Adjustment",
                        subtitle: "Displays an inline volume slider when hovering over any participant.",
                        isOn: $state.hoverUserShowsVolume
                    )

                    SettingsToggleRow(
                        "Ask Before Dragging Into a Channel",
                        subtitle: "Display a confirmation modal before moving users between channels.",
                        isOn: $state.askBeforeDraggingChannel
                    )

                    SettingsToggleRow(
                        "Always Show Channel User Count",
                        subtitle: "Displays the active participant count pill next to every channel.",
                        isOn: $state.alwaysShowChannelUserCount
                    )

                    SettingsToggleRow(
                        "Filter Hides Empty Channels",
                        subtitle: "Hide channels with no active users when searching or filtering.",
                        isOn: $state.filterHidesEmptyChannels
                    )

                    SettingsToggleRow(
                        "Show User's Avatar in Tooltip",
                        subtitle: "Display large profile avatars when hovering over users in the tree.",
                        isOn: $state.showUserAvatarInTooltip
                    )
                }

                // 4. Tray Icon (macOS Menu Bar)
                SettingsCard {
                    SettingsSectionHeader(
                        "Tray Icon (macOS Menu Bar)",
                        systemImage: "menubar.rectangle",
                        subtitle: "Menu bar status item showing speaking state and user names."
                    )

                    SettingsToggleRow(
                        "Show Talking Status in Tray Icon",
                        subtitle: "Glows the macOS menu bar icon green whenever someone in your channel talks.",
                        isOn: $state.showTalkingStatusInTray
                    )

                    SettingsToggleRow(
                        "Show User Name When Talking",
                        subtitle: "Displays the active speaker's nickname directly in the macOS menu bar.",
                        isOn: $state.showUserNameWhenTalking
                    )
                }

                // 5. Server Connect Dialog
                SettingsCard {
                    SettingsSectionHeader(
                        "Server Connect Dialog",
                        systemImage: "star.circle.fill",
                        subtitle: "Favorite servers and connection history organization."
                    )

                    SettingsToggleRow(
                        "Highlight Favorite Entries on Top of Lists",
                        subtitle: "Pins bookmarked and favorite servers at the very top of server lists.",
                        isOn: $state.highlightFavoriteEntriesOnTop
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
        }
    }
}
