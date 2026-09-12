import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

struct MacBooruInteractionCapabilities {
    let canReadComments: Bool
    let canCreateComments: Bool
    let canVotePosts: Bool
    let canVoteComments: Bool
}

struct MacBooruPostInteractionState: Equatable {
    var upvotes: Int?
    var downvotes: Int?
    var commentCount: Int?
    var userVote: BooruVoteState
}

struct MacBooruComment: Identifiable, Equatable {
    let id: Int
    let author: String
    let avatarURL: URL?
    let body: String
    let createdAt: Date?
    var score: Int?
    var userVote: BooruVoteState
}

enum MacBooruInteractionError: LocalizedError {
    case unsupported(String)
    case authenticationRequired(String)
    case invalidResponse
    case httpStatus(Int)
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .unsupported(let message), .authenticationRequired(let message), .serverMessage(let message):
            return message
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpStatus(let code):
            return "The server returned HTTP \(code)."
        }
    }
}

@MainActor
struct MacBooruInteractionAPI {
    let site: BooruSite

    private let mode: BooruAuthenticationMode
    private let username: String?
    private let userID: String?
    private let apiKey: String?
    private let session: URLSession

    init(site: BooruSite, settingsStore: SettingsStore, session: URLSession = .shared) {
        self.site = site
        mode = settingsStore.authenticationMode(for: site)
        username = settingsStore.username(for: site)
        userID = settingsStore.userID(for: site)
        apiKey = settingsStore.apiKey(for: site)
        self.session = session
    }

    var capabilities: MacBooruInteractionCapabilities {
        switch site.resolvedProtocol {
        case .e621:
            return .init(
                canReadComments: true,
                canCreateComments: hasE621APIAuthentication,
                canVotePosts: hasE621APIAuthentication,
                canVoteComments: hasE621APIAuthentication
            )

        case .philomena:
            return .init(
                canReadComments: true,
                canCreateComments: false,
                canVotePosts: false,
                canVoteComments: false
            )

        case .gelbooru:
            return .init(
                canReadComments: true,
                canCreateComments: false,
                canVotePosts: false,
                canVoteComments: false
            )

        case .moebooru, .danbooru, .shimmie:
            return .init(
                canReadComments: false,
                canCreateComments: false,
                canVotePosts: false,
                canVoteComments: false
            )
        }
    }

    func fetchPostState(imageID: Int) async throws -> MacBooruPostInteractionState {
        switch site.resolvedProtocol {
        case .philomena:
            return try await fetchPhilomenaPostState(imageID: imageID)
        case .e621:
            return try await fetchE621PostState(imageID: imageID)
        case .gelbooru, .moebooru, .danbooru, .shimmie:
            return .init(upvotes: nil, downvotes: nil, commentCount: nil, userVote: .none)
        }
    }

    func setPostVote(imageID: Int, vote: BooruVoteState) async throws -> MacBooruPostInteractionState {
        guard site.resolvedProtocol == .e621 else {
            throw MacBooruInteractionError.unsupported("Voting is not available through this site's public API.")
        }
        guard let authorizationHeader = e621AuthorizationHeader else {
            throw MacBooruInteractionError.authenticationRequired("e621 voting requires your username and API key.")
        }

        var components = URLComponents(
            url: site.baseURL
                .appendingPathComponent("posts")
                .appendingPathComponent(String(imageID))
                .appendingPathComponent("votes.json"),
            resolvingAgainstBaseURL: false
        )

        if vote != .none {
            components?.queryItems = [
                URLQueryItem(name: "score", value: String(vote.rawValue)),
                URLQueryItem(name: "no_unvote", value: "true")
            ]
        }

        guard let url = components?.url else {
            throw MacBooruInteractionError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = vote == .none ? "DELETE" : "POST"
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let object = try await jsonObject(for: request)
        guard let dictionary = object as? [String: Any] else {
            throw MacBooruInteractionError.invalidResponse
        }

        return .init(
            upvotes: int(dictionary["up"]),
            downvotes: int(dictionary["down"]),
            commentCount: nil,
            userVote: BooruVoteState(rawValue: int(dictionary["our_score"]) ?? vote.rawValue) ?? vote
        )
    }

    func fetchComments(imageID: Int) async throws -> [MacBooruComment] {
        switch site.resolvedProtocol {
        case .philomena:
            return try await fetchPhilomenaComments(imageID: imageID)
        case .e621:
            return try await fetchE621Comments(imageID: imageID)
        case .gelbooru:
            return try await fetchGelbooruComments(imageID: imageID)
        case .moebooru, .danbooru, .shimmie:
            throw MacBooruInteractionError.unsupported("Comments are not implemented for this booru protocol yet.")
        }
    }

    func createComment(imageID: Int, body: String) async throws -> MacBooruComment {
        guard site.resolvedProtocol == .e621 else {
            throw MacBooruInteractionError.unsupported("Posting comments is not available through this site's public API.")
        }
        guard let authorizationHeader = e621AuthorizationHeader else {
            throw MacBooruInteractionError.authenticationRequired("e621 comments require your username and API key.")
        }

        let url = site.baseURL.appendingPathComponent("comments.json")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formBody([
            "comment[body]": body,
            "comment[post_id]": String(imageID)
        ])

        let object = try await jsonObject(for: request)
        guard let dictionary = object as? [String: Any] else {
            throw MacBooruInteractionError.invalidResponse
        }
        return parseE621Comment(dictionary)
    }

    func setCommentVote(commentID: Int, vote: BooruVoteState) async throws -> (score: Int?, userVote: BooruVoteState) {
        guard site.resolvedProtocol == .e621 else {
            throw MacBooruInteractionError.unsupported("Comment voting is not available through this site's public API.")
        }
        guard let authorizationHeader = e621AuthorizationHeader else {
            throw MacBooruInteractionError.authenticationRequired("e621 comment voting requires your username and API key.")
        }

        var components = URLComponents(
            url: site.baseURL
                .appendingPathComponent("comments")
                .appendingPathComponent(String(commentID))
                .appendingPathComponent("votes.json"),
            resolvingAgainstBaseURL: false
        )

        if vote != .none {
            components?.queryItems = [
                URLQueryItem(name: "score", value: String(vote.rawValue)),
                URLQueryItem(name: "no_unvote", value: "true")
            ]
        }

        guard let url = components?.url else {
            throw MacBooruInteractionError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = vote == .none ? "DELETE" : "POST"
        request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let object = try await jsonObject(for: request)
        guard let dictionary = object as? [String: Any] else {
            throw MacBooruInteractionError.invalidResponse
        }

        let resultingVote = BooruVoteState(
            rawValue: int(dictionary["our_score"]) ?? vote.rawValue
        ) ?? vote

        return (int(dictionary["score"]), resultingVote)
    }

    // MARK: - Philomena

    private func fetchPhilomenaPostState(imageID: Int) async throws -> MacBooruPostInteractionState {
        var components = URLComponents(
            url: site.baseURL
                .appendingPathComponent("api/v1/json/images")
                .appendingPathComponent(String(imageID)),
            resolvingAgainstBaseURL: false
        )

        if mode == .apiKey, let apiKey = apiKey?.nonEmpty {
            components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        }

        guard let url = components?.url else {
            throw MacBooruInteractionError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let object = try await jsonObject(for: request)
        guard let root = object as? [String: Any],
              let image = root["image"] as? [String: Any] else {
            throw MacBooruInteractionError.invalidResponse
        }

        var userVote: BooruVoteState = .none
        if let interactions = root["interactions"] as? [[String: Any]],
           let vote = interactions.first(where: { ($0["interaction_type"] as? String) == "voted" }),
           let value = vote["value"] as? String {
            userVote = value == "up" ? .up : value == "down" ? .down : .none
        }

        return .init(
            upvotes: int(image["upvotes"]),
            downvotes: int(image["downvotes"]),
            commentCount: int(image["comment_count"]),
            userVote: userVote
        )
    }

    private func fetchPhilomenaComments(imageID: Int) async throws -> [MacBooruComment] {
        var components = URLComponents(
            url: site.baseURL.appendingPathComponent("api/v1/json/search/comments"),
            resolvingAgainstBaseURL: false
        )

        var items = [
            URLQueryItem(name: "q", value: "image_id:\(imageID)"),
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "per_page", value: "100")
        ]
        if mode == .apiKey, let apiKey = apiKey?.nonEmpty {
            items.append(URLQueryItem(name: "key", value: apiKey))
        }
        components?.queryItems = items

        guard let url = components?.url else {
            throw MacBooruInteractionError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let object = try await jsonObject(for: request)
        guard let root = object as? [String: Any],
              let comments = root["comments"] as? [[String: Any]] else {
            throw MacBooruInteractionError.invalidResponse
        }

        return comments.compactMap { dictionary in
            guard let id = int(dictionary["id"]) else { return nil }
            return MacBooruComment(
                id: id,
                author: (dictionary["author"] as? String)?.nonEmpty ?? "Anonymous",
                avatarURL: absoluteURL(dictionary["avatar"] as? String),
                body: (dictionary["body"] as? String) ?? "",
                createdAt: parseDate(dictionary["created_at"] as? String),
                score: nil,
                userVote: .none
            )
        }
    }

    // MARK: - e621

    private var hasE621APIAuthentication: Bool {
        mode == .apiKey && e621AuthorizationHeader != nil
    }

    private var e621AuthorizationHeader: String? {
        guard mode == .apiKey,
              let username = username?.nonEmpty,
              let apiKey = apiKey?.nonEmpty,
              let data = "\(username):\(apiKey)".data(using: .utf8) else {
            return nil
        }
        return "Basic \(data.base64EncodedString())"
    }

    private func fetchE621PostState(imageID: Int) async throws -> MacBooruPostInteractionState {
        let url = site.baseURL
            .appendingPathComponent("posts")
            .appendingPathComponent("\(imageID).json")

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let authorizationHeader = e621AuthorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }

        let object = try await jsonObject(for: request)
        let root = object as? [String: Any]
        let post = (root?["post"] as? [String: Any]) ?? root ?? [:]
        let score = post["score"] as? [String: Any]
        let stats = post["stats"] as? [String: Any]
        let modernScore = stats?["score"] as? [String: Any]

        return .init(
            upvotes: int(score?["up"]) ?? int(modernScore?["up"]),
            downvotes: int(score?["down"]) ?? int(modernScore?["down"]),
            commentCount: int(post["comment_count"]) ?? int(stats?["comment_count"]),
            userVote: BooruVoteState(rawValue: int(stats?["vote"]) ?? 0) ?? .none
        )
    }

    private func fetchE621Comments(imageID: Int) async throws -> [MacBooruComment] {
        var components = URLComponents(
            url: site.baseURL.appendingPathComponent("comments.json"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "group_by", value: "comment"),
            URLQueryItem(name: "search[post_id]", value: String(imageID)),
            URLQueryItem(name: "search[order]", value: "id_asc"),
            URLQueryItem(name: "limit", value: "100")
        ]

        guard let url = components?.url else {
            throw MacBooruInteractionError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if let authorizationHeader = e621AuthorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }

        let object = try await jsonObject(for: request)
        guard let comments = object as? [[String: Any]] else {
            throw MacBooruInteractionError.invalidResponse
        }
        return comments.map(parseE621Comment)
    }

    private func parseE621Comment(_ dictionary: [String: Any]) -> MacBooruComment {
        MacBooruComment(
            id: int(dictionary["id"]) ?? 0,
            author: (dictionary["creator_name"] as? String)?.nonEmpty ?? "Anonymous",
            avatarURL: nil,
            body: (dictionary["body"] as? String) ?? "",
            createdAt: parseDate(dictionary["created_at"] as? String),
            score: int(dictionary["score"]),
            userVote: BooruVoteState(rawValue: int(dictionary["vote"]) ?? 0) ?? .none
        )
    }

    // MARK: - Gelbooru DAPI

    private func fetchGelbooruComments(imageID: Int) async throws -> [MacBooruComment] {
        var components = URLComponents(
            url: site.baseURL.appendingPathComponent("index.php"),
            resolvingAgainstBaseURL: false
        )

        var items = [
            URLQueryItem(name: "page", value: "dapi"),
            URLQueryItem(name: "s", value: "comment"),
            URLQueryItem(name: "q", value: "index"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "post_id", value: String(imageID))
        ]

        if mode == .apiKey, let apiKey = apiKey?.nonEmpty {
            items.append(URLQueryItem(name: "api_key", value: apiKey))
            if let userID = userID?.nonEmpty {
                items.append(URLQueryItem(name: "user_id", value: userID))
            }
        }
        components?.queryItems = items

        guard let url = components?.url else {
            throw MacBooruInteractionError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MacBooruInteractionError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MacBooruInteractionError.httpStatus(http.statusCode)
        }

        if let object = try? JSONSerialization.jsonObject(with: data) {
            return parseGelbooruJSON(object)
        }

        let delegate = MacGelbooruCommentXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else {
            throw MacBooruInteractionError.invalidResponse
        }
        return delegate.comments.map { comment in
            MacBooruComment(
                id: comment.id,
                author: comment.author,
                avatarURL: nil,
                body: comment.body,
                createdAt: parseFlexibleDate(comment.createdAt),
                score: comment.score,
                userVote: .none
            )
        }
    }

    private func parseGelbooruJSON(_ object: Any) -> [MacBooruComment] {
        let dictionaries: [[String: Any]]
        if let array = object as? [[String: Any]] {
            dictionaries = array
        } else if let root = object as? [String: Any],
                  let comments = root["comment"] as? [[String: Any]] {
            dictionaries = comments
        } else if let root = object as? [String: Any],
                  let comment = root["comment"] as? [String: Any] {
            dictionaries = [comment]
        } else {
            dictionaries = []
        }

        return dictionaries.compactMap { dictionary in
            guard let id = int(dictionary["id"]) else { return nil }
            let author = (dictionary["creator"] as? String)
                ?? (dictionary["creator_name"] as? String)
                ?? (dictionary["author"] as? String)
                ?? "Anonymous"

            return MacBooruComment(
                id: id,
                author: author,
                avatarURL: nil,
                body: (dictionary["body"] as? String) ?? "",
                createdAt: parseFlexibleDate(dictionary["created_at"]),
                score: int(dictionary["score"]),
                userVote: .none
            )
        }
    }

    // MARK: - Helpers

    private var userAgent: String {
        "BooruBar/1.0 (macOS; contact: github.com/IlyaBOT/iBooru-Bar)"
    }

    private func jsonObject(for request: URLRequest) async throws -> Any {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MacBooruInteractionError.invalidResponse
        }

        guard (200..<300).contains(http.statusCode) else {
            if let rawObject = try? JSONSerialization.jsonObject(with: data),
               let dictionary = rawObject as? [String: Any],
               let message = (dictionary["message"] as? String) ?? (dictionary["error"] as? String) {
                throw MacBooruInteractionError.serverMessage(message)
            }
            throw MacBooruInteractionError.httpStatus(http.statusCode)
        }

        guard !data.isEmpty else { return [:] }
        return try JSONSerialization.jsonObject(with: data)
    }

    private func formBody(_ fields: [String: String]) -> Data? {
        var components = URLComponents()
        components.queryItems = fields.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.percentEncodedQuery?.data(using: .utf8)
    }

    private func absoluteURL(_ rawValue: String?) -> URL? {
        guard let rawValue = rawValue?.nonEmpty else { return nil }
        if rawValue.hasPrefix("//") {
            return URL(string: "https:" + rawValue)
        }
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }
        return URL(string: rawValue, relativeTo: site.baseURL)?.absoluteURL
    }

    private func int(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func parseFlexibleDate(_ value: Any?) -> Date? {
        if let number = value as? NSNumber {
            return Date(timeIntervalSince1970: number.doubleValue)
        }
        if let string = value as? String {
            if let timestamp = TimeInterval(string) {
                return Date(timeIntervalSince1970: timestamp)
            }
            return parseDate(string)
        }
        return nil
    }

    private func parseDate(_ value: String?) -> Date? {
        guard let value else { return nil }

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: value) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: value) { return date }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyy-MM-dd'T'HH:mm:ssZ"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) { return date }
        }
        return nil
    }
}

private struct MacGelbooruParsedComment {
    let id: Int
    let author: String
    let body: String
    let createdAt: String?
    let score: Int?
}

private final class MacGelbooruCommentXMLParser: NSObject, XMLParserDelegate {
    private(set) var comments: [MacGelbooruParsedComment] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "comment",
              let rawID = attributeDict["id"],
              let id = Int(rawID) else {
            return
        }

        comments.append(
            MacGelbooruParsedComment(
                id: id,
                author: attributeDict["creator"]
                    ?? attributeDict["creator_name"]
                    ?? attributeDict["author"]
                    ?? "Anonymous",
                body: attributeDict["body"] ?? "",
                createdAt: attributeDict["created_at"],
                score: attributeDict["score"].flatMap(Int.init)
            )
        )
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
