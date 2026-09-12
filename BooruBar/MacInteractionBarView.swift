import SwiftUI

@available(macOS 12.0, *)
struct MacInteractionBarView: View {
    let image: BooruImage
    let site: BooruSite?
    @ObservedObject var settingsStore: SettingsStore
    let onOpenComments: () -> Void

    @State private var interactionState: MacBooruPostInteractionState
    @State private var isLoadingPostState = false
    @State private var loadingVote: BooruVoteState?
    @State private var errorMessage: String?

    init(
        image: BooruImage,
        site: BooruSite?,
        settingsStore: SettingsStore,
        onOpenComments: @escaping () -> Void
    ) {
        self.image = image
        self.site = site
        self.onOpenComments = onOpenComments
        _settingsStore = ObservedObject(wrappedValue: settingsStore)
        _interactionState = State(
            initialValue: MacBooruPostInteractionState(
                upvotes: image.upvotes,
                downvotes: image.downvotes,
                commentCount: image.commentCount,
                userVote: image.userVote ?? .none
            )
        )
    }

    var body: some View {
        HStack(spacing: 8) {
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
                onOpenComments()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "bubble.left")
                    Text(countText(interactionState.commentCount))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .foregroundStyle(capabilities.canReadComments ? Color.primary : Color.secondary)
            .disabled(!capabilities.canReadComments)
            .help(capabilities.canReadComments ? "Comments" : "Comments are not supported by this API")

            if isLoadingPostState {
                ProgressView()
                    .controlSize(.small)
                    .frame(width: 18)
            }
        }
        .task(id: interactionTaskID) {
            await loadPostStateIfUseful()
        }
        .alert("BooruBar", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
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
        let loading = loadingVote == vote

        return Button {
            Task {
                await togglePostVote(vote)
            }
        } label: {
            HStack(spacing: 5) {
                ZStack {
                    Image(systemName: selected ? selectedSystemImage : systemImage)
                        .opacity(loading ? 0.2 : 1)

                    if loading {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }
                Text(countText(count))
            }
            .foregroundStyle(selected ? activeColor : (capabilities.canVotePosts ? Color.primary : Color.secondary))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(Color(nsColor: .textBackgroundColor).opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .disabled(!capabilities.canVotePosts || loadingVote != nil)
        .help(capabilities.canVotePosts ? title : "Configure API authentication to enable voting")
    }

    private var capabilities: MacBooruInteractionCapabilities {
        guard let site else {
            return .init(
                canReadComments: false,
                canCreateComments: false,
                canVotePosts: false,
                canVoteComments: false
            )
        }
        return MacBooruInteractionAPI(site: site, settingsStore: settingsStore).capabilities
    }

    private var interactionTaskID: String {
        guard let site else { return "none:\(image.id)" }
        return [
            site.id.uuidString,
            String(image.id),
            site.resolvedProtocol.rawValue,
            settingsStore.authenticationMode(for: site).rawValue,
            settingsStore.hasUsableAuthentication(for: site) ? "auth" : "anon"
        ].joined(separator: ":")
    }

    @MainActor
    private func loadPostStateIfUseful() async {
        guard let site else { return }

        let shouldFetch = image.upvotes == nil
            || image.downvotes == nil
            || image.commentCount == nil
            || settingsStore.hasUsableAuthentication(for: site)

        guard shouldFetch else { return }

        switch site.resolvedProtocol {
        case .philomena, .e621:
            break
        case .gelbooru, .moebooru, .danbooru, .shimmie:
            return
        }

        isLoadingPostState = true
        defer { isLoadingPostState = false }

        do {
            let state = try await MacBooruInteractionAPI(site: site, settingsStore: settingsStore)
                .fetchPostState(imageID: image.id)
            interactionState = merged(state, preservingCommentCount: false)
        } catch {
            // Feed metadata remains usable if the optional detail refresh fails.
        }
    }

    @MainActor
    private func togglePostVote(_ vote: BooruVoteState) async {
        guard let site else { return }

        let target: BooruVoteState = interactionState.userVote == vote ? .none : vote
        loadingVote = vote
        defer { loadingVote = nil }

        do {
            let state = try await MacBooruInteractionAPI(site: site, settingsStore: settingsStore)
                .setPostVote(imageID: image.id, vote: target)
            interactionState = merged(state, preservingCommentCount: true)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func merged(
        _ newState: MacBooruPostInteractionState,
        preservingCommentCount: Bool
    ) -> MacBooruPostInteractionState {
        MacBooruPostInteractionState(
            upvotes: newState.upvotes ?? interactionState.upvotes,
            downvotes: newState.downvotes ?? interactionState.downvotes,
            commentCount: preservingCommentCount
                ? interactionState.commentCount
                : (newState.commentCount ?? interactionState.commentCount),
            userVote: newState.userVote
        )
    }

    private func countText(_ count: Int?) -> String {
        count.map(String.init) ?? "—"
    }
}
