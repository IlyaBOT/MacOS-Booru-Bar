import SwiftUI
import WebKit

struct MobileGalleryCardView: View {
    let image: BooruImage
    let playAnimatedMedia: Bool

    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview

            HStack(spacing: 8) {
                Text("#\(image.id)")
                    .font(.headline)

                if let author = image.authorName {
                    Text(author)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let score = image.score {
                    Label(
                        "\(score)",
                        systemImage: "arrow.up.heart"
                    )
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                }
            }

            tags
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(
            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
        )
        .contentShape(Rectangle())
        .onTapGesture {
            openURL(image.pageURL)
        }
    }

    @ViewBuilder
    private var preview: some View {
        ZStack {
            Color(uiColor: .tertiarySystemBackground)

            if playAnimatedMedia,
               image.mediaKind.shouldUsePlaybackView,
               let url = image.imageURL {
                MobileWebMediaPreview(url: url)
            } else if let url = image.previewURL,
                      image.mediaKind != .video {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()

                    case .success(let loadedImage):
                        loadedImage
                            .resizable()
                            .scaledToFit()

                    default:
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Image(
                    systemName:
                        image.mediaKind == .video
                        ? "play.rectangle"
                        : "photo"
                )
                .font(.largeTitle)
                .foregroundColor(.secondary)
            }
        }
        .aspectRatio(previewAspectRatio, contentMode: .fit)
        .frame(maxWidth: .infinity)
        .clipShape(
            RoundedRectangle(
                cornerRadius: 8,
                style: .continuous
            )
        )
    }

    private var previewAspectRatio: CGFloat {
        guard let width = image.width,
              let height = image.height,
              width > 0,
              height > 0 else {
            return 16 / 9
        }

        return CGFloat(width) / CGFloat(height)
    }

    private var tags: some View {
        ScrollView(
            .horizontal,
            showsIndicators: false
        ) {
            HStack(spacing: 6) {
                ForEach(
                    Array(image.tags.prefix(20).enumerated()),
                    id: \.offset
                ) { _, tag in
                    Text(tag)
                        .font(.caption)
                        .lineLimit(1)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Color(
                                uiColor:
                                    .tertiarySystemBackground
                            )
                        )
                        .clipShape(
                            RoundedRectangle(
                                cornerRadius: 6
                            )
                        )
                }
            }
        }
    }
}

private struct MobileWebMediaPreview:
    UIViewRepresentable {

    let url: URL

    func makeUIView(
        context: Context
    ) -> WKWebView {
        let configuration =
            WKWebViewConfiguration()

        configuration
            .mediaTypesRequiringUserActionForPlayback = []

        configuration
            .allowsInlineMediaPlayback = true

        let view = WKWebView(
            frame: .zero,
            configuration: configuration
        )

        view.isOpaque = false
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false

        load(url, in: view)

        return view
    }

    func updateUIView(
        _ uiView: WKWebView,
        context: Context
    ) {
    }

    private func load(
        _ url: URL,
        in webView: WKWebView
    ) {
        let escaped =
            url.absoluteString
                .replacingOccurrences(
                    of: "&",
                    with: "&amp;"
                )
                .replacingOccurrences(
                    of: "\"",
                    with: "&quot;"
                )

        let html = """
        <!doctype html>
        <html>
        <head>
        <meta name="viewport"
              content="width=device-width,
                       initial-scale=1">
        <style>
        html, body {
            margin: 0;
            width: 100%;
            height: 100%;
            background: transparent;
            overflow: hidden;
        }

        img, video {
            width: 100%;
            height: 100%;
            object-fit: contain;
        }
        </style>
        </head>
        <body>
        <video
            src="\(escaped)"
            autoplay
            muted
            loop
            playsinline>
        </video>
        <img
            src="\(escaped)"
            alt="">
        </body>
        </html>
        """

        webView.loadHTMLString(
            html,
            baseURL: nil
        )
    }
}
