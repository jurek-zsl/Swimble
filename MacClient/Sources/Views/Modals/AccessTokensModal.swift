import SwiftUI

/// Access Tokens dialog allowing users to enter passwords and tokens for restricted channels.
public struct AccessTokensModal: View {
    @Bindable public var store: MumbleStore
    @Environment(\.dismiss) private var dismiss
    @State private var newToken: String = ""

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "key.fill")
                        .font(.title2)
                        .foregroundStyle(store.accentTint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Channel Access Tokens")
                            .font(.headline.bold())
                        Text("Add passwords and access keys to enter restricted channels.")
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
                // Add Token Input
                HStack {
                    TextField("Enter channel password / token...", text: $newToken)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit {
                            addNewToken()
                        }

                    Button("Add Token") {
                        addNewToken()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(store.accentTint)
                    .disabled(newToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                // Tokens List
                if store.accessTokens.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "lock.open.trianglebadge.exclamationmark")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary.opacity(0.5))
                            .padding(.top, 24)

                        Text("No Access Tokens Added")
                            .font(.subheadline.bold())
                            .foregroundStyle(.secondary)

                        Text("If a channel requires a password, add the token above to gain access.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(Array(store.accessTokens.enumerated()), id: \.offset) { index, token in
                            HStack {
                                Image(systemName: "key.horizontal.fill")
                                    .foregroundStyle(store.accentTint)

                                Text(token)
                                    .font(.system(.body, design: .monospaced))

                                Spacer()

                                Button(role: .destructive) {
                                    store.removeAccessToken(at: index)
                                } label: {
                                    Image(systemName: "trash")
                                        .foregroundStyle(.red)
                                }
                                .buttonStyle(.borderless)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    .listStyle(.inset)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                    }
                }

                HStack {
                    Text("\(store.accessTokens.count) active token\(store.accessTokens.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !store.accessTokens.isEmpty {
                        Button("Clear All Tokens", role: .destructive) {
                            for token in store.accessTokens {
                                store.removeAccessToken(token)
                            }
                        }
                        .font(.caption)
                        .buttonStyle(.link)
                    }
                }
            }
            .padding(20)
        }
        .frame(width: 480, height: 420)
    }

    private func addNewToken() {
        let trimmed = newToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        store.addAccessToken(trimmed)
        newToken = ""
    }
}
