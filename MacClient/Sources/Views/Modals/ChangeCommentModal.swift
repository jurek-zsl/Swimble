import SwiftUI

/// Dialog allowing the user to update their personal comment/bio on the Mumble server.
public struct ChangeCommentModal: View {
    @Bindable public var store: MumbleStore
    @Environment(\.dismiss) private var dismiss

    @State private var commentText: String = ""

    public init(store: MumbleStore) {
        self.store = store
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                HStack(spacing: 8) {
                    Image(systemName: "text.bubble.fill")
                        .font(.title2)
                        .foregroundStyle(store.accentTint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Change User Comment")
                            .font(.headline.bold())
                        Text("Set a status message or bio visible to everyone on the server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))

            Divider()

            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Comment / Bio (Supports Text & HTML):")
                        .font(.subheadline.bold())

                    TextEditor(text: $commentText)
                        .font(.body)
                        .frame(height: 140)
                        .padding(4)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
                        }
                }

                HStack {
                    Button("Clear Comment", role: .destructive) {
                        commentText = ""
                        saveComment()
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button("Save Comment") {
                        saveComment()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(store.accentTint)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(20)
        }
        .frame(width: 480, height: 290)
        .onAppear {
            if let myId = store.mySessionId,
               let me = store.users.first(where: { $0.sessionId == myId }),
               let c = me.comment {
                commentText = c
            }
        }
    }

    private func saveComment() {
        store.setComment(comment: commentText)
        dismiss()
    }
}
