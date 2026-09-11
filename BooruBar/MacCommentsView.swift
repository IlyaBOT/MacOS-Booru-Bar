import SwiftUI

@available(macOS 12.0, *)
struct MacCommentsView: View {
    let image: BooruImage
    let site: BooruSite
    @ObservedObject var settingsStore: SettingsStore
    var onCommentCountChanged: ((Int) -> Void)? = nil
    let onDismiss: () -> Void

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
                } else if let errorMessage = errorMessage, comments.isEmpty {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                onDismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
            .help("Back to gallery")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

                commentBody(comment.body)

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

    @ViewBuilder
    private func commentBody(_ body: String) -> some View {
        if site.resolvedProtocol == .philomena {
            philomenaSegmentsView(
                MacPhilomenaCommentBodyParser.parse(body),
                visitedCommentIDs: [],
                depth: 0
            )
        } else {
            let segments = MacCommentBodyParser.parse(body)

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
                            if let author = author, !author.isEmpty {
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
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.secondary.opacity(0.32), lineWidth: 1)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func philomenaSegmentsView(
        _ segments: [MacPhilomenaCommentBodySegment],
        visitedCommentIDs: Set<Int>,
        depth: Int
    ) -> AnyView {
        AnyView(
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    philomenaSegmentView(
                        segment,
                        visitedCommentIDs: visitedCommentIDs,
                        depth: depth
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        )
    }

    private func philomenaSegmentView(
        _ segment: MacPhilomenaCommentBodySegment,
        visitedCommentIDs: Set<Int>,
        depth: Int
    ) -> AnyView {
        switch segment {
        case .text(let text):
            return AnyView(
                Text(text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            )

        case .reply(let author, let commentID):
            return philomenaReplyView(
                author: author,
                commentID: commentID,
                visitedCommentIDs: visitedCommentIDs,
                depth: depth
            )

        case .quote(let author, let commentID, let segments):
            return philomenaQuoteView(
                author: author,
                commentID: commentID,
                segments: segments,
                visitedCommentIDs: visitedCommentIDs,
                depth: depth
            )
        }
    }

    private func philomenaReplyView(
        author: String,
        commentID: Int,
        visitedCommentIDs: Set<Int>,
        depth: Int
    ) -> AnyView {
        guard !visitedCommentIDs.contains(commentID),
              visitedCommentIDs.count < 6,
              let referencedComment = comments.first(where: { $0.id == commentID }) else {
            return philomenaQuoteView(
                author: author,
                commentID: commentID,
                segments: [],
                visitedCommentIDs: visitedCommentIDs,
                depth: depth
            )
        }

        var nextVisited = visitedCommentIDs
        nextVisited.insert(commentID)

        return philomenaQuoteView(
            author: referencedComment.author,
            commentID: commentID,
            segments: MacPhilomenaCommentBodyParser.parse(referencedComment.body),
            visitedCommentIDs: nextVisited,
            depth: depth
        )
    }

    private func philomenaQuoteView(
        author: String?,
        commentID: Int?,
        segments: [MacPhilomenaCommentBodySegment],
        visitedCommentIDs: Set<Int>,
        depth: Int
    ) -> AnyView {
        var renderedSegments = segments
        var renderedAuthor = author
        var nextVisited = visitedCommentIDs

        if renderedSegments.isEmpty,
           let commentID = commentID,
           !visitedCommentIDs.contains(commentID),
           visitedCommentIDs.count < 6,
           let referencedComment = comments.first(where: { $0.id == commentID }) {
            renderedAuthor = referencedComment.author
            renderedSegments = MacPhilomenaCommentBodyParser.parse(referencedComment.body)
            nextVisited.insert(commentID)
        }

        let hasBody = !renderedSegments.isEmpty

        return AnyView(
            VStack(alignment: .leading, spacing: 7) {
                if let renderedAuthor = renderedAuthor, !renderedAuthor.isEmpty {
                    Text(renderedAuthor)
                        .font(.subheadline.weight(.bold))
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if hasBody {
                        Divider()
                    }
                }

                if hasBody {
                    philomenaSegmentsView(
                        renderedSegments,
                        visitedCommentIDs: nextVisited,
                        depth: depth + 1
                    )
                } else if let commentID = commentID {
                    Text("Comment #\(commentID)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 9)
            .background(Color(nsColor: .controlBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.32), lineWidth: 1)
            }
            .padding(.leading, depth > 0 ? 8 : 0)
        )
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
            if let avatarURL = avatarURL {
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

        if let result = result {
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
        guard let rawValue = rawValue, !rawValue.isEmpty else { return nil }
        if rawValue.hasPrefix("//") {
            return URL(string: "https:" + rawValue)
        }
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }
        return URL(string: rawValue, relativeTo: baseURL)?.absoluteURL
    }
}

private enum MacCommentBodySegment: Equatable {
    case text(String)
    case quote(author: String?, text: String)
}

private enum MacCommentBodyParser {
    private static let quoteExpression = try? NSRegularExpression(
        pattern: #"\[quote\](.*?)\[/quote\]"#,
        options: [.caseInsensitive, .dotMatchesLineSeparators]
    )

    private static let quoteAuthorExpression = try? NSRegularExpression(
        pattern: #"^\s*\"([^\"]+)\":/(?:users|user/show)/\d+\s+said:\s*"#,
        options: [.caseInsensitive]
    )

    static func parse(_ body: String) -> [MacCommentBodySegment] {
        guard let quoteExpression = quoteExpression else {
            return [.text(body)]
        }

        let nsBody = body as NSString
        let fullRange = NSRange(location: 0, length: nsBody.length)
        let matches = quoteExpression.matches(in: body, options: [], range: fullRange)

        guard !matches.isEmpty else {
            return [.text(body)]
        }

        var segments: [MacCommentBodySegment] = []
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

        if let quoteAuthorExpression = quoteAuthorExpression {
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

    private static func appendPlainText(_ rawText: String, to segments: inout [MacCommentBodySegment]) {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        segments.append(.text(text))
    }
}

private indirect enum MacPhilomenaCommentBodySegment: Equatable {
    case text(String)
    case quote(author: String?, commentID: Int?, segments: [MacPhilomenaCommentBodySegment])
    case reply(author: String, commentID: Int)
}

private enum MacPhilomenaCommentBodyParser {
    private struct Line {
        let depth: Int
        let text: String
    }

    private static let replyExpression = try? NSRegularExpression(
        pattern: #"^\s*\[@([^\]]+)\]\([^)]*#comment_(\d+)\)\s*$"#,
        options: [.caseInsensitive]
    )

    private static let imageExpression = try? NSRegularExpression(
        pattern: #"!\[([^\]]*)\]\([^)]*\)"#,
        options: []
    )

    private static let linkExpression = try? NSRegularExpression(
        pattern: #"\[([^\]]+)\]\([^)]*\)"#,
        options: []
    )

    static func parse(_ body: String) -> [MacPhilomenaCommentBodySegment] {
        let normalized = body
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        let lines = normalized
            .components(separatedBy: "\n")
            .map(tokenize)

        var index = 0
        let segments = parseLevel(lines, index: &index, level: 0)

        if !segments.isEmpty {
            return segments
        }

        let fallback = cleanInline(normalized)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return fallback.isEmpty ? [] : [.text(fallback)]
    }

    private static func tokenize(_ rawLine: String) -> Line {
        var remainder = rawLine[...]
        var depth = 0

        while true {
            while let first = remainder.first, first == " " || first == "\t" {
                remainder.removeFirst()
            }

            guard remainder.first == ">" else { break }
            remainder.removeFirst()
            depth += 1

            if remainder.first == " " {
                remainder.removeFirst()
            }
        }

        return Line(depth: depth, text: String(remainder))
    }

    private static func parseLevel(
        _ lines: [Line],
        index: inout Int,
        level: Int
    ) -> [MacPhilomenaCommentBodySegment] {
        var segments: [MacPhilomenaCommentBodySegment] = []
        var paragraphLines: [String] = []

        func flushParagraph() {
            let text = paragraphLines
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            paragraphLines.removeAll(keepingCapacity: true)

            guard !text.isEmpty else { return }
            segments.append(.text(cleanInline(text)))
        }

        while index < lines.count {
            let line = lines[index]

            if line.depth < level {
                break
            }

            if line.depth > level {
                flushParagraph()
                let children = parseLevel(lines, index: &index, level: level + 1)
                if !children.isEmpty {
                    segments.append(.quote(author: nil, commentID: nil, segments: children))
                }
                continue
            }

            index += 1
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.isEmpty {
                flushParagraph()
                continue
            }

            if let reply = replyReference(trimmed) {
                flushParagraph()
                segments.append(.reply(author: reply.author, commentID: reply.commentID))
                continue
            }

            paragraphLines.append(line.text)
        }

        flushParagraph()
        return mergeReplyWithQuotedSnapshot(segments)
    }

    private static func mergeReplyWithQuotedSnapshot(
        _ segments: [MacPhilomenaCommentBodySegment]
    ) -> [MacPhilomenaCommentBodySegment] {
        var result: [MacPhilomenaCommentBodySegment] = []
        var index = 0

        while index < segments.count {
            if case .reply(let author, let commentID) = segments[index],
               index + 1 < segments.count,
               case .quote(let quoteAuthor, let quoteCommentID, let children) = segments[index + 1] {
                if quoteAuthor == nil && quoteCommentID == nil {
                    result.append(
                        .quote(
                            author: author,
                            commentID: commentID,
                            segments: children
                        )
                    )
                } else {
                    result.append(
                        .quote(
                            author: author,
                            commentID: commentID,
                            segments: [segments[index + 1]]
                        )
                    )
                }
                index += 2
                continue
            }

            result.append(segments[index])
            index += 1
        }

        return result
    }

    private static func replyReference(_ text: String) -> (author: String, commentID: Int)? {
        guard let replyExpression = replyExpression else { return nil }

        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        guard let match = replyExpression.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 3,
              match.range(at: 1).location != NSNotFound,
              match.range(at: 2).location != NSNotFound,
              let commentID = Int(nsText.substring(with: match.range(at: 2))) else {
            return nil
        }

        var author = nsText.substring(with: match.range(at: 1))
        if author.hasPrefix("@") {
            author.removeFirst()
        }

        return (author, commentID)
    }

    private static func cleanInline(_ text: String) -> String {
        var value = text

        if let imageExpression = imageExpression {
            value = replacingMatches(imageExpression, in: value) { altText in
                altText.isEmpty ? "Image" : altText
            }
        }

        if let linkExpression = linkExpression {
            value = replacingMatches(linkExpression, in: value) { label in
                label
            }
        }

        return value
    }

    private static func replacingMatches(
        _ expression: NSRegularExpression,
        in text: String,
        replacement: (String) -> String
    ) -> String {
        let nsText = text as NSString
        let matches = expression.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        )

        var result = text
        for match in matches.reversed() {
            guard match.numberOfRanges > 1,
                  match.range(at: 1).location != NSNotFound,
                  let swiftRange = Range(match.range, in: result) else {
                continue
            }

            let label = nsText.substring(with: match.range(at: 1))
            result.replaceSubrange(swiftRange, with: replacement(label))
        }

        return result
    }
}
