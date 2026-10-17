import SwiftUI
import AppKit

/// Dialog allowing the user to update their personal comment/bio on the Mumble server with rich text, HTML, and images.
public struct ChangeCommentModal: View {
    @Bindable public var store: MumbleStore
    @Environment(\.dismiss) private var dismiss

    @State private var commentText: String = ""
    @State private var selectedTab: Int = 0 // 0 = Edit, 1 = Preview
    @State private var isDropTargeted: Bool = false
    @State private var statusNotice: String? = nil

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
                        Text("Set a status message, bio, or images visible to everyone on the server.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                // Edit / Preview Segments
                Picker("Mode", selection: $selectedTab) {
                    Label("Edit", systemImage: "pencil").tag(0)
                    Label("Preview", systemImage: "eye").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .background(Color(NSColor.windowBackgroundColor).opacity(0.8))

            Divider()

            VStack(spacing: 14) {
                if selectedTab == 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Comment / Bio (Supports Text & HTML):")
                                .font(.subheadline.bold())

                            Spacer()

                            if containsImages(commentText) {
                                Label("Contains Images", systemImage: "photo.badge.checkmark")
                                    .font(.caption2)
                                    .foregroundStyle(.green)
                            }
                        }

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $commentText)
                                .font(.system(size: 13, design: .monospaced))
                                .frame(minHeight: 180, maxHeight: .infinity)
                                .padding(6)
                                .background(Color(NSColor.controlBackgroundColor).opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
                                .overlay {
                                    RoundedRectangle(cornerRadius: 8)
                                        .strokeBorder(isDropTargeted ? store.accentTint : Color.primary.opacity(0.12), lineWidth: isDropTargeted ? 2 : 0.8)
                                }

                            if commentText.isEmpty {
                                Text("Enter your comment or click 'Add Image...' below...")
                                    .font(.system(size: 13))
                                    .foregroundStyle(.tertiary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                        }
                        .onDrop(of: [.fileURL, .image], isTargeted: $isDropTargeted) { providers in
                            handleIncomingDrop(providers)
                        }

                        // Toolbar for adding/pasting images
                        HStack(spacing: 10) {
                            Button(action: addImageFromFile) {
                                Label("Add Image...", systemImage: "photo.badge.plus")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            Button(action: pasteImageFromClipboard) {
                                Label("Paste Image", systemImage: "doc.on.clipboard")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)

                            if let notice = statusNotice {
                                Text(notice)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            Text("Drop image files here to embed")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                } else {
                    // Preview Tab
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Live Preview:")
                            .font(.subheadline.bold())

                        ScrollView {
                            if commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                Text("No comment content.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(20)
                            } else {
                                RichDescriptionView(rawHtml: commentText, accentTint: store.accentTint)
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                        .frame(minHeight: 210, maxHeight: .infinity)
                        .background(Color(NSColor.controlBackgroundColor).opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.8)
                        }
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
        .frame(width: 540, height: 400)
        .onAppear {
            if let myId = store.mySessionId,
               let me = store.users.first(where: { $0.sessionId == myId }),
               let c = me.comment {
                commentText = c
            }
        }
    }

    private func addImageFromFile() {
        guard let img = ChatImageHelper.pickImageFile() else { return }
        embedImage(img)
    }

    private func pasteImageFromClipboard() {
        guard let img = ChatImageHelper.loadImageFromPasteboard() else {
            statusNotice = "No image found on clipboard."
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { statusNotice = nil }
            return
        }
        embedImage(img)
    }

    private func handleIncomingDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            if provider.canLoadObject(ofClass: NSImage.self) {
                _ = provider.loadObject(ofClass: NSImage.self) { img, _ in
                    if let nsImg = img as? NSImage {
                        DispatchQueue.main.async {
                            embedImage(nsImg)
                        }
                    }
                }
                return true
            }
            if provider.hasItemConformingToTypeIdentifier("public.file-url") {
                provider.loadItem(forTypeIdentifier: "public.file-url", options: nil) { item, _ in
                    if let data = item as? Data,
                       let url = URL(dataRepresentation: data, relativeTo: nil),
                       let img = NSImage(contentsOf: url) {
                        DispatchQueue.main.async {
                            embedImage(img)
                        }
                    }
                }
                return true
            }
        }
        return false
    }

    private func embedImage(_ image: NSImage) {
        guard let b64 = ChatImageHelper.prepareImageForMumble(image: image, maxDimension: 600, maxBytes: 70_000) else {
            statusNotice = "Failed to compress image."
            return
        }
        let tag = "<p><img src=\"data:image/jpeg;base64,\(b64)\" /></p>"
        if commentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commentText = tag
        } else {
            commentText += "\n" + tag
        }
        statusNotice = "Image embedded successfully!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { statusNotice = nil }
    }

    private func saveComment() {
        store.setComment(comment: commentText)
        dismiss()
    }
}
