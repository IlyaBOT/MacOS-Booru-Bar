import SwiftUI
import UIKit

struct MobileCommentsView: View {
    let image: BooruImage
    let site: BooruSite
    @ObservedObject var settingsStore: SettingsStore
    var onCommentCountChanged: ((Int) -> Void)?

    @Environment(\.presentationMode) private var presentationMode

    @State private var comments: [BooruComment] = []
    @State private var isLoading = true
    @State private var isNewestFirst = false
    @State private var draft = ""
    @State private var isSending = false
    @State private var loadingVoteCommentID: Int?
    @State private var errorMessage: String?

    private var api: BooruInteractionAPI {
        BooruInteractionAPI(site: site, settingsStore: settingsStore)
    }

    private var capabilities: BooruInteractionCapabilities {
        api.capabilities
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetDetentConfigurator()
                .frame(width: 0, height: 0)

            header
            Divider()

            Group {
                if isLoading {
                    VStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if let errorMessage, comments.isEmpty {
                    messageView(icon: "exclamationmark.triangle", text: errorMessage)
                } else if comments.isEmpty {
                    messageView(icon: "bubble.left", text: "There are no comments on this post yet.")
                } else {
                    commentList
                }
            }

            Divider()
            composer
        }
        .background(Color(uiColor: .systemBackground))
        .task {
            await loadComments()
        }
        .alert("Comments", isPresented: Binding(
            get: { errorMessage != nil && !comments.isEmpty },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Comments")
                .font(.headline)

            Spacer()

            Button {
                isNewestFirst.toggle()
            } label: {
                Label(
                    isNewestFirst ? "Newest" : "Oldest",
                    systemImage: isNewestFirst ? "arrow.down" : "arrow.up"
                )
                .font(.subheadline)
            }

            Button {
                presentationMode.wrappedValue.dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var commentList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedComments) { comment in
                    commentRow(comment)
                    Divider()
                        .padding(.leading, 60)
                }
            }
        }
    }

    private func commentRow(_ comment: BooruComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            avatar(for: comment)

            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline) {
                    Text(comment.author)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer()

                    if let createdAt = comment.createdAt {
                        Text(createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }

                Text(comment.body)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)

                if comment.score != nil {
                    HStack {
                        Spacer()
                        commentVoteButton(comment)
                    }
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func avatar(for comment: BooruComment) -> some View {
        Group {
            if let url = comment.avatarURL {
                AsyncImage(url: url) { phase in
                    if case .success(let image) = phase {
                        image.resizable().scaledToFill()
                    } else {
                        avatarFallback(comment.author)
                    }
                }
            } else {
                avatarFallback(comment.author)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
    }

    private func avatarFallback(_ author: String) -> some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            Text(String(author.prefix(1)).uppercased())
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }

    private func commentVoteButton(_ comment: BooruComment) -> some View {
        Button {
            guard capabilities.canVoteComments else { return }
            Task { await toggleCommentVote(comment) }
        } label: {
            HStack(spacing: 4) {
                ZStack {
                    Image(systemName: comment.userVote == .up ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .foregroundColor(comment.userVote == .up ? .accentColor : .secondary)
                        .opacity(loadingVoteCommentID == comment.id ? 0.25 : 1)

                    if loadingVoteCommentID == comment.id {
                        ProgressView()
                            .scaleEffect(0.55)
                    }
                }
                Text("\(comment.score ?? 0)")
                    .foregroundColor(.secondary)
            }
            .font(.caption)
        }
        .buttonStyle(.plain)
        .disabled(!capabilities.canVoteComments || loadingVoteCommentID != nil)
    }

    @ViewBuilder
    private var composer: some View {
        if capabilities.canCreateComments {
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Write a comment…", text: $draft)
                    .textFieldStyle(.roundedBorder)

                Button {
                    Task { await sendComment() }
                } label: {
                    ZStack {
                        Image(systemName: "paperplane.fill")
                            .opacity(isSending ? 0.2 : 1)
                        if isSending {
                            ProgressView()
                                .scaleEffect(0.65)
                        }
                    }
                    .frame(width: 30, height: 30)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
        } else {
            Text(readOnlyMessage)
                .font(.footnote)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }

    private var readOnlyMessage: String {
        switch site.apiType {
        case .e621:
            return "Sign in with your e621 username and API key to post comments."
        case .philomena:
            return "Comments are read-only here because Philomena does not expose comment posting through its public token API."
        case .gelbooru:
            return "Comments are read-only because this API does not document a stable comment-posting endpoint."
        }
    }

    private var sortedComments: [BooruComment] {
        comments.sorted { lhs, rhs in
            let leftDate = lhs.createdAt ?? .distantPast
            let rightDate = rhs.createdAt ?? .distantPast
            if leftDate == rightDate {
                return isNewestFirst ? lhs.id > rhs.id : lhs.id < rhs.id
            }
            return isNewestFirst ? leftDate > rightDate : leftDate < rightDate
        }
    }

    private func messageView(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(.secondary)
            Text(text)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .padding(.horizontal, 24)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @MainActor
    private func loadComments() async {
        isLoading = true
        defer { isLoading = false }

        do {
            comments = try await api.fetchComments(imageID: image.id)
            onCommentCountChanged?(comments.count)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func sendComment() async {
        let body = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        isSending = true
        defer { isSending = false }

        do {
            let comment = try await api.createComment(imageID: image.id, body: body)
            comments.append(comment)
            draft = ""
            onCommentCountChanged?(comments.count)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func toggleCommentVote(_ comment: BooruComment) async {
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else { return }
        loadingVoteCommentID = comment.id
        defer { loadingVoteCommentID = nil }

        let target: BooruVoteState = comment.userVote == .up ? .none : .up
        do {
            let result = try await api.setCommentVote(commentID: comment.id, vote: target)
            comments[index].score = result.score
            comments[index].userVote = result.userVote
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct SheetDetentConfigurator: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.backgroundColor = .clear
        DispatchQueue.main.async {
            configure(from: controller)
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            configure(from: uiViewController)
        }
    }

    private func configure(from controller: UIViewController) {
        guard let sheet = controller.parent?.presentationController as? UISheetPresentationController else { return }
        sheet.detents = [.medium(), .large()]
        sheet.selectedDetentIdentifier = .medium
        sheet.prefersGrabberVisible = true
        sheet.prefersScrollingExpandsWhenScrolledToEdge = true
        sheet.preferredCornerRadius = 22
        sheet.largestUndimmedDetentIdentifier = nil
    }
}
