import SwiftUI

@available(macOS 12.0, *)
struct MacCommentsView: View {
    let image: BooruImage
    let site: BooruSite
    @ObservedObject var settingsStore: SettingsStore
    var onCommentCountChanged: ((Int) -> Void)?

    @Environment(\.dismiss) private var dismiss

    @State private var comments: [MacBooruComment] = []
    @State private var isLoading = true
    @State private var newestFirst = false
    @State private var draft = ""
    @State private var isSending = false
    @State private var loadingVoteCommentID: Int?
    @State private var errorMessage: String?

    private var api: MacBooruInteractionAPI {
        MacBooruInteractionAPI(site: site, settingsStore: settingsStore)
    }

    private var capabilities: MacBooruInteractionCapabilities {
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
        .frame(width: 430, height: 560)
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            await loadComments()
        }
        .alert("Comments", isPresented: Binding(
            get: { errorMessage != nil && !comments.isEmpty },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Comments")
                    .font(.headline)
                Text("#\(image.id) · \(site.name)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                newestFirst.toggle()
            } label: {
                Label(
                    newestFirst ? "Newest" : "Oldest",
                    systemImage: newestFirst ? "arrow.down" : "arrow.up"
                )
            }
            .buttonStyle(.borderless)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private var commentList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(sortedComments) { comment in
                    commentRow(comment)
                    Divider()
                        .padding(.leading, 58)
                }
            }
        }
    }

    private func commentRow(_ comment: MacBooruComment) -> some View {
        HStack(alignment: .top, spacing: 10) {
            avatar(for: comment)

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(comment.author)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)

                    Spacer()

                    if let createdAt = comment.createdAt {
                        Text(createdAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                Text(comment.body)
                    .font(.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if comment.score != nil {
                    HStack {
                        Spacer()
                        commentVoteButton(comment)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func avatar(for comment: MacBooruComment) -> some View {
        Group {
            if let avatarURL = comment.avatarURL {
                MacRemoteAvatarImage(url: avatarURL, author: comment.author)
            } else if site.resolvedProtocol == .e621 {
                MacE621AvatarImage(author: comment.author, baseURL: site.baseURL)
            } else {
                MacAvatarFallbackView(author: comment.author)
            }
        }
        .frame(width: 36, height: 36)
        .clipShape(Circle())
    }

    private func commentVoteButton(_ comment: MacBooruComment) -> some View {
        Button {
            guard capabilities.canVoteComments else { return }
            Task {
                await toggleCommentVote(comment)
            }
        } label: {
            HStack(spacing: 4) {
                ZStack {
                    Image(systemName: comment.userVote == .up ? "hand.thumbsup.fill" : "hand.thumbsup")
                        .foregroundStyle(comment.userVote == .up ? Color.accentColor : Color.secondary)
                        .opacity(loadingVoteCommentID == comment.id ? 0.2 : 1)

                    if loadingVoteCommentID == comment.id {
                        ProgressView()
                            .controlSize(.mini)
                    }
                }

                Text("\(comment.score ?? 0)")
                    .foregroundStyle(.secondary)
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
                TextEditor(text: $draft)
                    .font(.body)
                    .frame(minHeight: 50, maxHeight: 88)
                    .padding(4)
                    .background(Color(nsColor: .textBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    }

                Button {
                    Task {
                        await sendComment()
                    }
                } label: {
                    ZStack {
                        Image(systemName: "paperplane.fill")
                            .opacity(isSending ? 0.2 : 1)
                        if isSending {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }
                    .frame(width: 26, height: 26)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSending || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(12)
        } else {
            Text(readOnlyMessage)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
    }

    private var readOnlyMessage: String {
        switch site.resolvedProtocol {
        case .e621:
            return "Add your e621 username and API key in Settings to post comments."
        case .philomena:
            return "Philomena comments are read-only because comment posting is not exposed through its public token API."
        case .gelbooru:
            return "Gelbooru comments are read-only because a stable public comment-posting endpoint is not documented."
        case .moebooru, .danbooru, .shimmie:
            return "Comments are not implemented for this API protocol yet."
        }
    }

    private var sortedComments: [MacBooruComment] {
        comments.sorted { lhs, rhs in
            let leftDate = lhs.createdAt ?? .distantPast
            let rightDate = rhs.createdAt ?? .distantPast

            if leftDate == rightDate {
                return newestFirst ? lhs.id > rhs.id : lhs.id < rhs.id
            }
            return newestFirst ? leftDate > rightDate : leftDate < rightDate
        }
    }

    private func messageView(icon: String, text: String) -> some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 30)
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
    private func toggleCommentVote(_ comment: MacBooruComment) async {
        guard let index = comments.firstIndex(where: { $0.id == comment.id }) else {
            return
        }

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

@available(macOS 12.0, *)
private struct MacRemoteAvatarImage: View {
    let url: URL
    let author: String

    var body: some View {
        AsyncImage(url: url) { phase in
            if case .success(let image) = phase {
                image
                    .resizable()
                    .scaledToFill()
            } else {
                MacAvatarFallbackView(author: author)
            }
        }
    }
}

@available(macOS 12.0, *)
private struct MacAvatarFallbackView: View {
    let author: String

    var body: some View {
        ZStack {
            Color(nsColor: .controlBackgroundColor)
            Text(String(author.prefix(1)).uppercased())
                .font(.headline)
                .foregroundStyle(.secondary)
        }
    }
}

@available(macOS 12.0, *)
private struct MacE621AvatarImage: View {
    let author: String
    let baseURL: URL

    @State private var avatarURL: URL?
    @State private var didResolve = false

    var body: some View {
        Group {
            if let avatarURL {
                MacRemoteAvatarImage(url: avatarURL, author: author)
            } else {
                MacAvatarFallbackView(author: author)
            }
        }
        .task(id: "\(baseURL.absoluteString)|\(author)") {
            guard !didResolve else { return }
            avatarURL = await MacE621AvatarResolver.shared.avatarURL(for: author, baseURL: baseURL)
            didResolve = true
        }
    }
}

private actor MacE621AvatarResolver {
    static let shared = MacE621AvatarResolver()

    private var cache: [String: URL] = [:]
    private var missing: Set<String> = []

    func avatarURL(for author: String, baseURL: URL) async -> URL? {
        let key = "\(baseURL.host?.lowercased() ?? baseURL.absoluteString)|\(author.lowercased())"

        if let cached = cache[key] {
            return cached
        }
        if missing.contains(key) {
            return nil
        }

        let result = await Self.fetchAvatarURL(author: author, baseURL: baseURL)
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

            var request = URLRequest(url: userURL)
            request.setValue(
                "BooruBar/1.0 (macOS; contact: github.com/IlyaBOT/iBooru-Bar)",
                forHTTPHeaderField: "User-Agent"
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  let rawObject = try? JSONSerialization.jsonObject(with: data),
                  let object = rawObject as? [String: Any] else {
                return nil
            }

            let user = (object["user"] as? [String: Any]) ?? object

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
                "BooruBar/1.0 (macOS; contact: github.com/IlyaBOT/iBooru-Bar)",
                forHTTPHeaderField: "User-Agent"
            )

            let (postData, postResponse) = try await URLSession.shared.data(for: postRequest)
            guard let postHTTP = postResponse as? HTTPURLResponse,
                  (200..<300).contains(postHTTP.statusCode),
                  let rawPost = try? JSONSerialization.jsonObject(with: postData),
                  let postObject = rawPost as? [String: Any] else {
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
        if rawValue.hasPrefix("//") {
            return URL(string: "https:" + rawValue)
        }
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }
        return URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
    }
}
