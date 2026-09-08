import AppKit
import SwiftUI
import WebKit

struct GalleryCardView: View {
    let image: BooruImage
    let playAnimatedMedia: Bool
    @State private var measuredContentWidth: CGFloat = 0
    @State private var showsAllTags = false
    private let fallbackPreviewWidth: CGFloat = 400
    private let maxPreviewHeight: CGFloat = 648
    private let collapsedTagLimit = 6

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
                .onTapGesture(perform: openImagePage)

            HStack(spacing: 8) {
                Text("#\(image.id)")
                    .font(.headline)
                    .fixedSize()

                if let authorName = image.authorName {
                    Text(authorName)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .layoutPriority(0)
                }

                if let score = image.score {
                    Label("\(score)", systemImage: "arrow.up.heart")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }

                Spacer()

                if let width = image.width, let height = image.height {
                    Text("\(width)x\(height)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                }
            }
            .onTapGesture(perform: openImagePage)

            tagList
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: GalleryCardContentWidthPreferenceKey.self,
                    value: proxy.size.width
                )
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onPreferenceChange(GalleryCardContentWidthPreferenceKey.self) { width in
            guard width > 0, abs(width - measuredContentWidth) > 0.5 else {
                return
            }
            measuredContentWidth = width
        }
        .help("Open image page")
    }

    private func openImagePage() {
        NSWorkspace.shared.open(image.pageURL)
    }

    @ViewBuilder
    private var preview: some View {
        if playAnimatedMedia,
           image.mediaKind.shouldUsePlaybackView,
           let mediaURL = image.imageURL {
            WebMediaPreview(url: mediaURL, mediaKind: image.mediaKind)
                .frame(width: previewSize.width, height: previewSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    mediaBadge
                }
                .frame(maxWidth: .infinity)
        } else if let previewURL = image.previewURL,
                  BooruMediaKind(url: previewURL) != .video {
            stillImagePreview(url: previewURL)
        } else {
            placeholder
                .overlay {
                    mediaPlaceholderIcon
                }
                .frame(width: previewSize.width, height: previewSize.height)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .frame(maxWidth: .infinity)
        }
    }

    private var placeholder: some View {
        Rectangle()
            .fill(Color(nsColor: .underPageBackgroundColor))
    }

    private func stillImagePreview(url: URL) -> some View {
        AsyncImage(url: url, transaction: Transaction(animation: .easeInOut(duration: 0.2))) { phase in
            switch phase {
            case .empty:
                placeholder
                    .overlay {
                        ProgressView()
                    }
            case .success(let image):
                image
                    .resizable()
                    .scaledToFit()
            case .failure:
                placeholder
                    .overlay {
                        mediaPlaceholderIcon
                    }
            @unknown default:
                placeholder
            }
        }
        .frame(width: previewSize.width, height: previewSize.height)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if image.mediaKind.shouldUsePlaybackView {
                mediaBadge
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var mediaPlaceholderIcon: some View {
        Image(systemName: image.mediaKind == .video ? "play.rectangle" : "photo")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
    }

    private var mediaBadge: some View {
        Text(mediaBadgeText)
            .font(.caption2.bold())
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .padding(6)
    }

    private var mediaBadgeText: String {
        switch image.mediaKind {
        case .animatedImage:
            return image.imageURL?.pathExtension.uppercased() == "WEBP" ? "WEBP" : "GIF"
        case .video:
            return "VIDEO"
        case .staticImage, .unknown:
            return ""
        }
    }

    private var previewSize: CGSize {
        let previewWidth = measuredContentWidth > 0 ? measuredContentWidth : fallbackPreviewWidth
        let aspectRatio = previewAspectRatio
        var width = previewWidth
        var height = width / aspectRatio

        if height > maxPreviewHeight {
            height = maxPreviewHeight
            width = height * aspectRatio
        }

        return CGSize(width: width.rounded(.down), height: height.rounded(.down))
    }

    private var previewAspectRatio: CGFloat {
        guard let width = image.width,
              let height = image.height,
              width > 0,
              height > 0 else {
            return 16.0 / 9.0
        }

        return CGFloat(width) / CGFloat(height)
    }

    private var tagList: some View {
        TagFlowLayout(horizontalSpacing: 6, verticalSpacing: 6) {
            ForEach(Array(visibleTags.enumerated()), id: \.offset) { _, tag in
                tagChip(tag)
            }

            if image.tags.count > collapsedTagLimit {
                Button {
                    showsAllTags.toggle()
                } label: {
                    tagToggleLabel
                }
                .buttonStyle(.plain)
                .help(showsAllTags ? "Collapse tags" : "Show all tags")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var visibleTags: [String] {
        if showsAllTags {
            return image.tags
        }

        return Array(image.tags.prefix(collapsedTagLimit))
    }

    private var tagToggleLabel: some View {
        Text(showsAllTags ? "^" : "+\(image.tags.count - collapsedTagLimit)")
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }

    private func tagChip(_ tag: String) -> some View {
        Text(tag)
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}

private struct GalleryCardContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct TagFlowLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        arrangeSubviews(proposal: proposal, subviews: subviews).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let arrangement = arrangeSubviews(proposal: proposal, subviews: subviews)

        for index in subviews.indices {
            subviews[index].place(
                at: CGPoint(
                    x: bounds.minX + arrangement.positions[index].x,
                    y: bounds.minY + arrangement.positions[index].y
                ),
                proposal: .unspecified
            )
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (size: CGSize, positions: [CGPoint]) {
        let proposedWidth = proposal.width ?? .greatestFiniteMagnitude
        let maxWidth = proposedWidth > 0 ? proposedWidth : .greatestFiniteMagnitude
        var positions: [CGPoint] = []
        var origin = CGPoint.zero
        var lineHeight: CGFloat = 0
        var layoutWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            if origin.x > 0, origin.x + size.width > maxWidth {
                origin.x = 0
                origin.y += lineHeight + verticalSpacing
                lineHeight = 0
            }

            positions.append(origin)
            layoutWidth = max(layoutWidth, origin.x + size.width)
            lineHeight = max(lineHeight, size.height)
            origin.x += size.width + horizontalSpacing
        }

        let width = proposal.width ?? layoutWidth
        let height = positions.isEmpty ? 0 : origin.y + lineHeight
        return (CGSize(width: width, height: height), positions)
    }
}

private struct WebMediaPreview: NSViewRepresentable {
    let url: URL
    let mediaKind: BooruMediaKind

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsAirPlayForMediaPlayback = false

        let webView = ClickThroughWebView(frame: .zero, configuration: configuration)
        webView.setValue(false, forKey: "drawsBackground")
        webView.navigationDelegate = context.coordinator
        webView.loadHTMLString(html, baseURL: nil)
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if context.coordinator.currentURL != url {
            context.coordinator.currentURL = url
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(currentURL: url)
    }

    static func dismantleNSView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.loadHTMLString("", baseURL: nil)
    }

    private var html: String {
        let escapedURL = url.absoluteString
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")

        let mediaMarkup: String
        if mediaKind == .video {
            mediaMarkup = """
            <video src="\(escapedURL)" autoplay muted loop playsinline></video>
            """
        } else {
            mediaMarkup = """
            <img src="\(escapedURL)" alt="">
            """
        }

        return """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        html, body {
            margin: 0;
            width: 100%;
            height: 100%;
            overflow: hidden;
            background: transparent;
        }
        img, video {
            width: 100%;
            height: 100%;
            object-fit: contain;
            display: block;
            background: transparent;
        }
        </style>
        </head>
        <body>
        \(mediaMarkup)
        </body>
        </html>
        """
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var currentURL: URL

        init(currentURL: URL) {
            self.currentURL = currentURL
        }
    }
}

private final class ClickThroughWebView: WKWebView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }
}
