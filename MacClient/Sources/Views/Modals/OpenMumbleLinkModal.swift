import SwiftUI

/// Modal dialog for opening and connecting to a Mumble URL link.
public struct OpenMumbleLinkModal: View {
    @Bindable public var store: MumbleStore
    @State private var urlInput: String = ""
    @Environment(\.dismiss) private var dismiss

    private var parsedInfo: MumbleLinkInfo? {
        MumbleURLParser.parse(string: urlInput)
    }

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(spacing: 12) {
                Image(systemName: "link.badge.plus")
                    .font(.title2)
                    .foregroundStyle(store.accentTint)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Open Mumble Link")
                        .font(.headline)
                    Text("Enter or paste a standard mumble:// server or channel link.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button {
                    store.activeModal = nil
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                // Input TextField
                VStack(alignment: .leading, spacing: 6) {
                    Text("Mumble URL")
                        .font(.subheadline.bold())

                    HStack {
                        Image(systemName: "link")
                            .foregroundStyle(.secondary)
                        TextField("mumble://[username[:password]@]host[:port][/channel]", text: $urlInput)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                connectIfValid()
                            }

                        if !urlInput.isEmpty {
                            Button {
                                urlInput = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }

                        Button("Paste") {
                            if let clip = NSPasteboard.general.string(forType: .string) {
                                urlInput = clip.trimmingCharacters(in: .whitespacesAndNewlines)
                            }
                        }
                        .controlSize(.small)
                    }
                    .padding(8)
                    .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(parsedInfo != nil ? store.accentTint : Color.secondary.opacity(0.2), lineWidth: 1)
                    )
                }

                // Parsed Preview Card
                if let info = parsedInfo {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Link Preview")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)

                        VStack(spacing: 6) {
                            previewRow(label: "Server Host", value: "\(info.host):\(info.port)")
                            if let user = info.username, !user.isEmpty {
                                previewRow(label: "Username", value: user)
                            }
                            if let title = info.title, !title.isEmpty {
                                previewRow(label: "Server Title", value: title)
                            }
                            if !info.channelPath.isEmpty {
                                previewRow(label: "Target Channel", value: "/" + info.channelPath.joined(separator: "/"))
                            }
                            if info.password != nil {
                                previewRow(label: "Password", value: "••••••••")
                            }
                        }
                        .padding(10)
                        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                } else if !urlInput.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Please enter a valid mumble:// URL")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer(minLength: 8)

                // Actions
                HStack {
                    Button("Cancel") {
                        store.activeModal = nil
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button {
                        connectIfValid()
                    } label: {
                        Text("Connect")
                            .padding(.horizontal, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(store.accentTint)
                    .disabled(parsedInfo == nil)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding()
        }
        .frame(width: 480, height: 310)
        .onAppear {
            // Check if clipboard contains a mumble URL
            if let clip = NSPasteboard.general.string(forType: .string),
               clip.lowercased().starts(with: "mumble://") {
                urlInput = clip.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
    }

    private func previewRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.monospaced())
                .bold()
        }
    }

    private func connectIfValid() {
        guard let info = parsedInfo else { return }
        store.activeModal = nil
        dismiss()
        store.handleMumbleLink(info)
    }
}
