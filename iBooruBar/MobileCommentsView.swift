import SwiftUI
import UIKit

struct MobileCommentsSheetHost: View {
    let image: BooruImage
    let site: BooruSite
    @ObservedObject var settingsStore: SettingsStore
    var onCommentCountChanged: ((Int) -> Void)?
    var onDismiss: () -> Void

    var body: some View {
        MobileCommentsView(
            image: image,
            site: site,
            settingsStore: settingsStore,
            onCommentCountChanged: onCommentCountChanged,
            onDismiss: onDismiss
        )
        .background(
            MobileCommentsSheetConfigurator()
                .frame(width: 0, height: 0)
        )
    }
}

private struct MobileCommentsSheetConfigurator: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> ConfiguratorViewController {
        ConfiguratorViewController()
    }

    func updateUIViewController(_ uiViewController: ConfiguratorViewController, context: Context) {
        uiViewController.configureIfNeeded()
    }

    final class ConfiguratorViewController: UIViewController {
        private var didConfigure = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .clear
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            configureIfNeeded()
        }

        func configureIfNeeded() {
            guard !didConfigure else { return }

            var candidate: UIViewController? = self
            while let current = candidate {
                if let sheet = current.sheetPresentationController {
                    sheet.detents = [.medium(), .large()]
                    sheet.selectedDetentIdentifier = .medium
                    sheet.prefersGrabberVisible = true
                    sheet.prefersScrollingExpandsWhenScrolledToEdge = true
                    sheet.preferredCornerRadius = 22
                    didConfigure = true
                    return
                }
                candidate = current.parent
            }

            DispatchQueue.main.async { [weak self] in
                self?.configureIfNeeded()
            }
        }
    }
}

struct MobileCommentsView: View {
    let image: BooruImage
    let site: BooruSite
    @ObservedObject var settingsStore: SettingsStore
    var onCommentCountChanged: ((Int) -> Void)?
    var onDismiss: () -> Void

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

            Button { onDismiss() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var commentList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedComments) { comment in
                    commentRow(comment)
                    Divider().padding(.leading, 60)
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

                commentBody(comment.body)

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

    @ViewBuilder
    private func commentBody(_ body: String) -> some View {
        let segments = CommentBodyParser.parse(body)

        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    Text(text)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)

                case .quote(let author, let text):
                    VStack(alignment: .leading, spacing: 7) {
                        if let author, !author.isEmpty {
                            Text(author)
                                .font(.subheadline.weight(.bold))
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Divider()
                        }

                        Text(text)
                            .font(.body.italic())
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 9)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 9, style: .continuous)
                            .stroke(Color.secondary.opacity(0.32), lineWidth: 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func avatar(for comment: BooruComment) -> some View {
        Group {
            if let url = comment.avatarURL {
                RemoteAvatarImage(url: url, author: comment.author)
            } else if site.apiType == .e621 {
                E621AvatarImage(author: comment.author, baseURL: site.baseURL)
            } else {
                AvatarFallbackView(author: comment.author)
            }
        }
        .frame(width: 38, height: 38)
        .clipShape(Circle())
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
                        ProgressView().scaleEffect(0.55)
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
                            ProgressView().scaleEffect(0.65)
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
            if site.apiType == .gelbooru {
                comments = try await GelbooruCommentsClient(site: site, settingsStore: settingsStore)
                    .fetchComments(postID: image.id)
            } else {
                comments = try await api.fetchComments(imageID: image.id)
            }
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

private struct RemoteAvatarImage: View {
    let url: URL
    let author: String

    var body: some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                AvatarFallbackView(author: author)
            }
        }
    }
}

private struct AvatarFallbackView: View {
    let author: String

    var body: some View {
        ZStack {
            Color(uiColor: .secondarySystemBackground)
            Text(String(author.prefix(1)).uppercased())
                .font(.headline)
                .foregroundColor(.secondary)
        }
    }
}

private struct E621AvatarImage: View {
    let author: String
    let baseURL: URL

    @State private var avatarURL: URL?
    @State private var didResolve = false

    var body: some View {
        Group {
            if let avatarURL {
                RemoteAvatarImage(url: avatarURL, author: author)
            } else {
                AvatarFallbackView(author: author)
            }
        }
        .task(id: "\(baseURL.absoluteString)|\(author)") {
            guard !didResolve else { return }
            avatarURL = await E621AvatarResolver.shared.avatarURL(for: author, baseURL: baseURL)
            didResolve = true
        }
    }
}

private actor E621AvatarResolver {
    static let shared = E621AvatarResolver()

    private var cache: [String: URL] = [:]
    private var missing: Set<String> = []
    private var inFlight: [String: Task<URL?, Never>] = [:]

    func avatarURL(for author: String, baseURL: URL) async -> URL? {
        let key = "\(baseURL.host?.lowercased() ?? baseURL.absoluteString)|\(author.lowercased())"

        if let cached = cache[key] {
            return cached
        }
        if missing.contains(key) {
            return nil
        }
        if let task = inFlight[key] {
            return await task.value
        }

        let task = Task<URL?, Never> {
            await Self.fetchAvatarURL(author: author, baseURL: baseURL)
        }
        inFlight[key] = task

        let result = await task.value
        inFlight[key] = nil

        if let result {
            cache[key] = result
        } else {
            missing.insert(key)
        }

        return result
    }

    private static func fetchAvatarURL(author: String, baseURL: URL) async -> URL? {
        do {
            let userURL = baseURL
                .appendingPathComponent("users")
                .appendingPathComponent("\(author).json")

            var userRequest = URLRequest(url: userURL)
            userRequest.setValue(
                "iBooruBar/1.0 (iOS; contact: github.com/IlyaBOT/iBooru-Bar)",
                forHTTPHeaderField: "User-Agent"
            )

            let (userData, userResponse) = try await URLSession.shared.data(for: userRequest)
            guard let userHTTP = userResponse as? HTTPURLResponse,
                  (200..<300).contains(userHTTP.statusCode),
                  let userObject = try JSONSerialization.jsonObject(with: userData) as? [String: Any] else {
                return nil
            }

            let user = (userObject["user"] as? [String: Any]) ?? userObject

            if let direct = string(user["avatar_url"]),
               let directURL = absoluteURL(direct, relativeTo: baseURL) {
                return directURL
            }

            guard let avatarID = int(user["avatar_id"]) else {
                return nil
            }

            let postURL = baseURL
                .appendingPathComponent("posts")
                .appendingPathComponent("\(avatarID).json")

            var postRequest = URLRequest(url: postURL)
            postRequest.setValue(
                "iBooruBar/1.0 (iOS; contact: github.com/IlyaBOT/iBooru-Bar)",
                forHTTPHeaderField: "User-Agent"
            )

            let (postData, postResponse) = try await URLSession.shared.data(for: postRequest)
            guard let postHTTP = postResponse as? HTTPURLResponse,
                  (200..<300).contains(postHTTP.statusCode),
                  let postObject = try JSONSerialization.jsonObject(with: postData) as? [String: Any] else {
                return nil
            }

            let post = (postObject["post"] as? [String: Any]) ?? postObject
            let preview = post["preview"] as? [String: Any]
            let sample = post["sample"] as? [String: Any]
            let file = post["file"] as? [String: Any]

            let rawURL = string(preview?["url"])
                ?? string(sample?["url"])
                ?? string(file?["url"])

            return absoluteURL(rawURL, relativeTo: baseURL)
        } catch {
            return nil
        }
    }

    private static func string(_ value: Any?) -> String? {
        if let value = value as? String, !value.isEmpty { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private static func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private static func absoluteURL(_ rawValue: String?, relativeTo baseURL: URL) -> URL? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        if let url = URL(string: rawValue), url.scheme != nil { return url }
        if rawValue.hasPrefix("//") { return URL(string: "https:" + rawValue) }
        return URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
    }
}

private enum CommentBodySegment: Equatable {
    case text(String)
    case quote(author: String?, text: String)
}

private enum CommentBodyParser {
    private static let quoteExpression = try? NSRegularExpression(
        pattern: #"\[quote\](.*?)\[/quote\]"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    private static let quoteAuthorExpression = try? NSRegularExpression(
        pattern: #"^\s*\"([^\"]+)\":/(?:users|user/show)/\d+\s+said:\s*"#,
        options: [.caseInsensitive]
    )

    static func parse(_ body: String) -> [CommentBodySegment] {
        guard let quoteExpression else {
            return [.text(body)]
        }

        let nsBody = body as NSString
        let fullRange = NSRange(location: 0, length: nsBody.length)
        let matches = quoteExpression.matches(in: body, options: [], range: fullRange)

        guard !matches.isEmpty else {
            return [.text(body)]
        }

        var segments: [CommentBodySegment] = []
        var cursor = 0

        for match in matches {
            if match.range.location > cursor {
                let plainRange = NSRange(location: cursor, length: match.range.location - cursor)
                appendPlainText(nsBody.substring(with: plainRange), to: &segments)
            }

            if match.numberOfRanges > 1,
               match.range(at: 1).location != NSNotFound {
                let rawQuote = nsBody.substring(with: match.range(at: 1))
                let parsed = parseQuote(rawQuote)
                if !parsed.text.isEmpty {
                    segments.append(.quote(author: parsed.author, text: parsed.text))
                }
            }

            cursor = NSMaxRange(match.range)
        }

        if cursor < nsBody.length {
            appendPlainText(
                nsBody.substring(with: NSRange(location: cursor, length: nsBody.length - cursor)),
                to: &segments
            )
        }

        return segments.isEmpty ? [.text(body)] : segments
    }

    private static func parseQuote(_ rawQuote: String) -> (author: String?, text: String) {
        var text = rawQuote.trimmingCharacters(in: .whitespacesAndNewlines)
        var author: String?

        if let quoteAuthorExpression {
            let nsText = text as NSString
            let range = NSRange(location: 0, length: nsText.length)
            if let match = quoteAuthorExpression.firstMatch(in: text, options: [], range: range) {
                if match.numberOfRanges > 1,
                   match.range(at: 1).location != NSNotFound {
                    author = nsText.substring(with: match.range(at: 1))
                }

                text = nsText.substring(from: NSMaxRange(match.range))
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return (author, text)
    }

    private static func appendPlainText(_ rawText: String, to segments: inout [CommentBodySegment]) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        segments.append(.text(text))
    }
}
