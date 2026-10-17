import SwiftUI
import AppKit

/// Native User Interface configuration tab embracing macOS 26 Liquid Glass styling.
public struct UserInterfaceSettingsTab: View {
    @Bindable public var store: MumbleStore
    @Bindable public var state: SettingsState = SettingsState.shared

    public init(store: MumbleStore) {
        self.store = store
    }

    private let availableThemes = ["System Default", "Dark", "Light"]
    private let availableAccents = ["Cyan", "Emerald", "Sapphire", "Amethyst", "Amber", "Ruby"]

    public var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // 1. Appearance & Liquid Glass
                SettingsCard {
                    SettingsSectionHeader(
                        "Appearance & Accent",
                        systemImage: "paintpalette.fill",
                        subtitle: "Personalize Liquid Glass highlights and window appearance themes."
                    )

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Liquid Glass Accent Color")
                            .font(.subheadline.bold())

                        HStack(spacing: 12) {
                            ForEach(availableAccents, id: \.self) { colorName in
                                let color = MumbleStore.colorFromName(colorName)
                                let isSelected = store.accentColorName == colorName

                                Button(action: {
                                    store.accentColorName = colorName
                                }) {
                                    HStack(spacing: 6) {
                                        Circle()
                                            .fill(color)
                                            .frame(width: 14, height: 14)
                                        Text(colorName)
                                            .font(.caption.bold())
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(isSelected ? color.opacity(0.2) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 8)
                                            .strokeBorder(isSelected ? color : Color.primary.opacity(0.12), lineWidth: isSelected ? 1.5 : 0.8)
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    Divider()

                    HStack(spacing: 16) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Theme")
                                .font(.subheadline.bold())
                            Picker("Theme", selection: $state.uiTheme) {
                                ForEach(availableThemes, id: \.self) { Text($0).tag($0) }
                            }
                            .labelsHidden()
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Divider()

                    SettingsToggleRow(
                        "Display Quit Confirmation Dialog on Close",
                        subtitle: "Prompts for confirmation before quitting when actively connected to a voice server.",
                        isOn: $state.displayQuitConfirmation
                    )

                    SettingsToggleRow(
                        "Include Unread Message Count in Dock Icon",
                        subtitle: "Shows a badge on the macOS Dock icon with the count of unread chat messages.",
                        isOn: $state.includeUnreadCountInTaskbar
                    )
                }

                // 2. Channel Tree
                SettingsCard {
                    SettingsSectionHeader(
                        "Channel Tree",
                        systemImage: "folder.fill.badge.gearshape",
                        subtitle: "Participant sorting, volume adjustments, and channel visibility."
                    )

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
                        subtitle: "Displays an inline volume slider when hovering over any participant in the tree.",
                        isOn: $state.hoverUserShowsVolume
                    )

                    SettingsToggleRow(
                        "Always Show Channel User Count",
                        subtitle: "Displays the active participant count badge next to every channel.",
                        isOn: $state.alwaysShowChannelUserCount
                    )

                    SettingsToggleRow(
                        "Filter Hides Empty Channels",
                        subtitle: "Hide channels with no active users when searching or filtering.",
                        isOn: $state.filterHidesEmptyChannels
                    )
                }

                // 3. Menu Bar Extra
                SettingsCard {
                    SettingsSectionHeader(
                        "Menu Bar Extra",
                        systemImage: "menubar.rectangle",
                        subtitle: "macOS menu bar companion showing live speaking states and speakers."
                    )

                    SettingsToggleRow(
                        "Show Talking Status in Menu Bar Icon",
                        subtitle: "Glows the menu bar icon green whenever someone in your channel is talking.",
                        isOn: $state.showTalkingStatusInTray
                    )

                    SettingsToggleRow(
                        "Show User Name When Talking",
                        subtitle: "Displays the active speaker's nickname directly in the macOS menu bar title.",
                        isOn: $state.showUserNameWhenTalking
                    )
                }

                // 4. Server Bookmarks
                SettingsCard {
                    SettingsSectionHeader(
                        "Server Bookmarks",
                        systemImage: "star.circle.fill",
                        subtitle: "Server bookmark browser sorting and list priority."
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
