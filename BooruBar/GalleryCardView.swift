import AppKit
import SwiftUI
import WebKit

@available(macOS 12.0, *)
struct GalleryCardView: View {
    let image: BooruImage
    let playAnimatedMedia: Bool
    let site: BooruSite?
    @ObservedObject var settingsStore: SettingsStore
    let onOpenComments: (BooruImage) -> Void

    @State private var measuredContentWidth: CGFloat = 0
    @State private var showsAllTags = false
    private let fallbackPreviewWidth: CGFloat = 400
    private let maxPreviewHeight: CGFloat = 648
    private let collapsedTagLimit = 6
    private let tagSpacing: CGFloat = 6

    init(
        image: BooruImage,
        playAnimatedMedia: Bool,
        site: BooruSite?,
        settingsStore: SettingsStore,
        onOpenComments: @escaping (BooruImage) -> Void
    ) {
        self.image = image
        self.playAnimatedMedia = playAnimatedMedia
        self.site = site
        self.onOpenComments = onOpenComments
        _settingsStore = ObservedObject(wrappedValue: settingsStore)
    }

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

            Divider()

            MacInteractionBarView(
                image: image,
                site: site,
                settingsStore: settingsStore,
                onOpenComments: {
                    onOpenComments(image)
                }
            )
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
        VStack(alignment: .leading, spacing: tagSpacing) {
            ForEach(Array(tagRows.enumerated()), id: \.offset) { _, row in
                HStack(spacing: tagSpacing) {
                    ForEach(row, id: \.self) { entry in
                        switch entry {
                        case .tag(_, let tag):
                            tagChip(tag)
                        case .toggle:
                            Button {
                                showsAllTags.toggle()
                            } label: {
                                tagToggleLabel
                            }
                            .buttonStyle(.plain)
                            .help(showsAllTags ? "Collapse tags" : "Show all tags")
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var tagRows: [[TagFlowEntry]] {
        let availableWidth = max(measuredContentWidth, fallbackPreviewWidth)
        var rows: [[TagFlowEntry]] = []
        var currentRow: [TagFlowEntry] = []
        var currentWidth: CGFloat = 0

        for entry in tagEntries {
            let width = estimatedWidth(for: entry)
            let proposedWidth = currentRow.isEmpty ? width : currentWidth + tagSpacing + width

            if !currentRow.isEmpty, proposedWidth > availableWidth {
                rows.append(currentRow)
                currentRow = [entry]
                currentWidth = width
            } else {
                currentRow.append(entry)
                currentWidth = proposedWidth
            }
        }

        if !currentRow.isEmpty {
            rows.append(currentRow)
        }

        return rows
    }

    private var tagEntries: [TagFlowEntry] {
        var entries = Array(visibleTags.enumerated()).map { index, tag in
            TagFlowEntry.tag(index, tag)
        }

        if image.tags.count > collapsedTagLimit {
            entries.append(.toggle)
        }

        return entries
    }

    private func estimatedWidth(for entry: TagFlowEntry) -> CGFloat {
        let text: String
        let weight: NSFont.Weight

        switch entry {
        case .tag(_, let tag):
            text = tag
            weight = .regular
        case .toggle:
            text = showsAllTags ? "^" : "+\(image.tags.count - collapsedTagLimit)"
            weight = .semibold
        }

        let font = NSFont.systemFont(ofSize: NSFont.smallSystemFontSize, weight: weight)
        let textWidth = ceil((text as NSString).size(withAttributes: [.font: font]).width)
        return textWidth + 14
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

private enum TagFlowEntry: Hashable {
    case tag(Int, String)
    case toggle
}

private struct GalleryCardContentWidthPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
