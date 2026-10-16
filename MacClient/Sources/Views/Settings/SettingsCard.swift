import SwiftUI
import AppKit

/// Reusable grouped container for settings sections matching macOS 26 Liquid Glass style.
public struct SettingsCard<Content: View>: View {
    private let content: Content

    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            content
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.55))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                }
                .shadow(color: Color.black.opacity(0.03), radius: 4, x: 0, y: 1)
        }
    }
}

/// Standardized header for settings cards with title, SF Symbol, and optional subtitle.
public struct SettingsSectionHeader: View {
    let title: String
    let systemImage: String
    let subtitle: String?

    public init(_ title: String, systemImage: String, subtitle: String? = nil) {
        self.title = title
        self.systemImage = systemImage
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Label {
                Text(title)
                    .font(.headline)
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(Color.accentColor)
            }

            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Standardized label for settings rows with title and optional subtitle.
public struct SettingsRowLabel: View {
    let title: String
    let subtitle: String?

    public init(title: String, subtitle: String? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.subheadline.bold())
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Standardized row for settings toggles ensuring all switches are aligned on the far right column.
public struct SettingsToggleRow<LabelContent: View>: View {
    @Binding var isOn: Bool
    private let content: LabelContent

    public init(isOn: Binding<Bool>, @ViewBuilder content: () -> LabelContent) {
        self._isOn = isOn
        self.content = content()
    }

    public init(_ title: String, subtitle: String? = nil, isOn: Binding<Bool>) where LabelContent == SettingsRowLabel {
        self._isOn = isOn
        self.content = SettingsRowLabel(title: title, subtitle: subtitle)
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 16) {
            content
                .frame(maxWidth: .infinity, alignment: .leading)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
    }
}

