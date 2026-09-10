import SwiftUI
import WebKit

struct MobileGalleryCardView: View {
    let image: BooruImage
    let playAnimatedMedia: Bool
    let site: BooruSite?
    @ObservedObject var settingsStore: SettingsStore

    @Environment(\.openURL) private var openURL

    @State private var interactionState: BooruPostInteractionState
    @State private var isLoadingPostState = false
    @State private var loadingVote: BooruVoteState?
    @State private var showingComments = false
    @State private var errorMessage: String?

    init(
        image: BooruImage,
        playAnimatedMedia: Bool,
        site: BooruSite?,
        settingsStore: SettingsStore
    ) {
        self.image = image
        self.playAnimatedMedia = playAnimatedMedia
        self.site = site
        _settingsStore = ObservedObject(wrappedValue: settingsStore)
        _interactionState = State(
            initialValue: BooruPostInteractionState(
                upvotes: image.upvotes,
                downvotes: image.downvotes,
                commentCount: image.commentCount,
                userVote: image.userVote ?? .none
            )
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            preview
                .contentShape(Rectangle())
                .onTapGesture {
                    openURL(image.pageURL)
                }

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

                if isLoadingPostState {
                    ProgressView()
                        .scaleEffect(0.65)
                }
            }

            tags
            interactionBar
        }
        .padding(10)
        .background(Color(uiColor: .secondarySystemBackground))
        .clipShape(
            RoundedRectangle(
                cornerRadius: 12,
                style: .continuous
            )
        )
        .task(id: interactionTaskID) {
            await loadPostStateIfUseful()
        }
        .sheet(isPresented: $showingComments) {
            if let site {
                MobileCommentsView(
                    image: image,
                    site: site,
                    settingsStore: settingsStore,
                    onCommentCountChanged: { count in
                        interactionState.commentCount = count
                    }
                )
            }
        }
        .alert("Booru", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var interactionBar: some View {
        HStack(spacing: 6) {
            reactionButton(
                vote: .up,
                title: "Upvote",
                systemImage: "hand.thumbsup",
                selectedSystemImage: "hand.thumbsup.fill",
                count: interactionState.upvotes,
                activeColor: .accentColor
            )

            reactionButton(
                vote: .down,
                title: "Downvote",
                systemImage: "hand.thumbsdown",
                selectedSystemImage: "hand.thumbsdown.fill",
                count: interactionState.downvotes,
                activeColor: .red
            )

            Button {
                showingComments = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                    Text(countText(interactionState.commentCount))
                }
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundColor(capabilities.canReadComments ? .primary : .secondary)
            .disabled(!capabilities.canReadComments)
            .accessibilityLabel("Comments, \(countText(interactionState.commentCount))")
        }
        .padding(.top, 2)
    }

    private func reactionButton(
        vote: BooruVoteState,
        title: String,
        systemImage: String,
        selectedSystemImage: String,
        count: Int?,
        activeColor: Color
    ) -> some View {
        let selected = interactionState.userVote == vote
        let isLoading = loadingVote == vote

        return Button {
            Task { await togglePostVote(vote) }
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    Image(systemName: selected ? selectedSystemImage : systemImage)
                        .opacity(isLoading ? 0.22 : 1)

                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.55)
                    }
                }

                Text(countText(count))
            }
            .font(.subheadline)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 7)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundColor(
            selected
                ? activeColor
                : (capabilities.canVotePosts ? .primary : .secondary)
        )
        .disabled(!capabilities.canVotePosts || loadingVote != nil)
        .accessibilityLabel("\(title), \(countText(count))")
    }

    private var capabilities: BooruInteractionCapabilities {
        guard let site else {
            return BooruInteractionCapabilities(
                canReadComments: false,
                canCreateComments: false,
                canVotePosts: false,
                canVoteComments: false
            )
        }
        return BooruInteractionAPI(site: site, settingsStore: settingsStore).capabilities
    }

    private var interactionTaskID: String {
        let siteID = site?.id.uuidString ?? "none"
        return "\(siteID):\(image.id):\(settingsStore.authenticationMode(for: site ?? settingsStore.selectedSite).rawValue)"
    }

    @MainActor
    private func loadPostStateIfUseful() async {
        guard let site else { return }

        // Feed responses already carry counts on Philomena/e621. Fetching the
        // detail is still useful when authenticated because it resolves the
        // user's current vote and refreshes stale counts.
        let shouldFetch = image.upvotes == nil
            || image.downvotes == nil
            || image.commentCount == nil
            || settingsStore.hasUsableAuthentication(for: site)

        guard shouldFetch, site.apiType != .gelbooru else { return }

        isLoadingPostState = true
        defer { isLoadingPostState = false }

        do {
            let state = try await BooruInteractionAPI(site: site, settingsStore: settingsStore)
                .fetchPostState(imageID: image.id)
            interactionState = merged(state, preservingCommentCount: false)
        } catch {
            // Counts from the feed remain usable even if the optional detail
            // refresh fails. Avoid turning a gallery card into an error state.
        }
    }

    @MainActor
    private func togglePostVote(_ vote: BooruVoteState) async {
        guard let site else { return }

        let target: BooruVoteState = interactionState.userVote == vote ? .none : vote
        loadingVote = vote
        defer { loadingVote = nil }

        do {
            let state = try await BooruInteractionAPI(site: site, settingsStore: settingsStore)
                .setPostVote(imageID: image.id, vote: target)
            interactionState = merged(state, preservingCommentCount: true)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func merged(
        _ incoming: BooruPostInteractionState,
        preservingCommentCount: Bool
    ) -> BooruPostInteractionState {
        BooruPostInteractionState(
            upvotes: incoming.upvotes ?? interactionState.upvotes,
            downvotes: incoming.downvotes ?? interactionState.downvotes,
            commentCount: preservingCommentCount
                ? interactionState.commentCount
                : (incoming.commentCount ?? interactionState.commentCount),
            userVote: incoming.userVote
        )
    }

    private func countText(_ count: Int?) -> String {
        guard let count else { return "—" }
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        }
        if count >= 10_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        }
        return String(count)
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
