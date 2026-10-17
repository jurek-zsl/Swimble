import SwiftUI
import AppKit

/// Helper function to quickly check if an HTML or text string contains embedded or remote images.
public func containsImages(_ text: String) -> Bool {
    text.contains("<img") ||
    text.contains("data:image/") ||
    text.contains("![](") ||
    text.contains("![") ||
    text.contains(".png") ||
    text.contains(".jpg") ||
    text.contains(".jpeg") ||
    text.contains(".webp") ||
    text.contains(".gif")
}

/// View that renders rich text alongside embedded Base64 images and remote URLs
/// found in channel descriptions, user bios/comments, or server notices.
public struct RichDescriptionView: View {
    public let rawHtml: String
    public let accentTint: Color
    public var maxImageHeight: CGFloat = 200

    @State private var previewImageItem: IdentifiableImage? = nil

    public init(rawHtml: String, accentTint: Color = .cyan, maxImageHeight: CGFloat = 200) {
        self.rawHtml = rawHtml
        self.accentTint = accentTint
        self.maxImageHeight = maxImageHeight
    }

    private var cleanAttributedText: AttributedString {
        let stripped = cleanChatMessageText(from: rawHtml)
        return parseChatMessageBody(stripped)
    }

    private var dataUriImages: [NSImage] {
        extractDataUriImages(from: rawHtml)
    }

    private var remoteImageUrls: [URL] {
        extractRemoteImageUrls(from: rawHtml)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Render text portion
            if !cleanAttributedText.characters.isEmpty {
                Text(cleanAttributedText)
                    .font(.system(size: 13))
                    .lineSpacing(3)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Render inline Base64 data-uri images
            if !dataUriImages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(dataUriImages.enumerated()), id: \.offset) { _, img in
                        Image(nsImage: img)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxHeight: maxImageHeight)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .strokeBorder(Color.primary.opacity(0.12), lineWidth: 0.5)
                            }
                            .shadow(color: Color.black.opacity(0.08), radius: 4, x: 0, y: 2)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                previewImageItem = IdentifiableImage(image: img)
                            }
                            .contextMenu {
                                Button("Copy Image") {
                                    NSPasteboard.general.clearContents()
                                    NSPasteboard.general.writeObjects([img])
                                }
                                Button("Save Image to Downloads...") {
                                    ChatImageHelper.saveImageToDisk(img)
                                }
                            }
                    }
                }
            }

            // Render remote URL images
            if !remoteImageUrls.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(remoteImageUrls, id: \.self) { url in
                        RemoteChatImageView(url: url) { selectedImg in
                            previewImageItem = IdentifiableImage(image: selectedImg)
                        }
                    }
                }
            }
        }
        .sheet(item: $previewImageItem) { item in
            ImagePreviewModal(image: item.image)
        }
    }
}
