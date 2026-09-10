import Foundation

@MainActor
struct GelbooruCommentsClient {
    let site: BooruSite
    let settingsStore: SettingsStore
    var session: URLSession = .shared

    func fetchComments(postID: Int) async throws -> [BooruComment] {
        var queryItems = [
            URLQueryItem(name: "page", value: "dapi"),
            URLQueryItem(name: "s", value: "comment"),
            URLQueryItem(name: "q", value: "index"),
            URLQueryItem(name: "post_id", value: String(postID))
        ]

        if settingsStore.authenticationMode(for: site) == .apiKey,
           let apiKey = settingsStore.apiKey(for: site)?.trimmedNonEmpty {
            queryItems.append(URLQueryItem(name: "api_key", value: apiKey))
            if let userID = settingsStore.userID(for: site)?.trimmedNonEmpty {
                queryItems.append(URLQueryItem(name: "user_id", value: userID))
            }
        }

        var components = URLComponents(
            url: site.baseURL.appendingPathComponent("index.php"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = queryItems
        guard let url = components?.url else { throw BooruInteractionError.invalidResponse }

        var request = URLRequest(url: url)
        request.setValue("iBooruBar/1.0 (iOS; contact: github.com/IlyaBOT/iBooru-Bar)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw BooruInteractionError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw BooruInteractionError.httpStatus(http.statusCode) }
        guard !data.isEmpty else { return [] }

        if let comments = parseJSON(data) {
            return comments
        }

        let parserDelegate = GelbooruCommentXMLDelegate()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        guard parser.parse() else {
            throw parser.parserError ?? BooruInteractionError.invalidResponse
        }
        return parserDelegate.comments
    }

    private func parseJSON(_ data: Data) -> [BooruComment]? {
        guard let raw = try? JSONSerialization.jsonObject(with: data) else { return nil }

        let dictionaries: [[String: Any]]
        if let array = raw as? [[String: Any]] {
            dictionaries = array
        } else if let root = raw as? [String: Any], let comments = root["comment"] as? [[String: Any]] {
            dictionaries = comments
        } else if let root = raw as? [String: Any], let comment = root["comment"] as? [String: Any] {
            dictionaries = [comment]
        } else {
            dictionaries = []
        }

        return dictionaries.compactMap { dictionary in
            guard let id = lossyInt(dictionary["id"]) else { return nil }
            return BooruComment(
                id: id,
                author: string(dictionary["creator"])
                    ?? string(dictionary["creator_name"])
                    ?? string(dictionary["author"])
                    ?? "Anonymous",
                avatarURL: nil,
                body: string(dictionary["body"]) ?? "",
                createdAt: flexibleDate(dictionary["created_at"]),
                score: lossyInt(dictionary["score"]),
                userVote: .none
            )
        }
    }

    private func string(_ value: Any?) -> String? {
        if let value = value as? String { return value }
        if let value = value as? NSNumber { return value.stringValue }
        return nil
    }

    private func lossyInt(_ value: Any?) -> Int? {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) }
        return nil
    }

    private func flexibleDate(_ value: Any?) -> Date? {
        guard let value else { return nil }
        if let number = value as? NSNumber { return Date(timeIntervalSince1970: number.doubleValue) }
        guard let string = string(value) else { return nil }
        if let timestamp = TimeInterval(string) { return Date(timeIntervalSince1970: timestamp) }
        return Self.isoDate(string)
    }

    fileprivate static func isoDate(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private final class GelbooruCommentXMLDelegate: NSObject, XMLParserDelegate {
    private(set) var comments: [BooruComment] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.caseInsensitiveCompare("comment") == .orderedSame,
              let idString = attributeDict["id"],
              let id = Int(idString) else {
            return
        }

        let author = attributeDict["creator"]
            ?? attributeDict["creator_name"]
            ?? attributeDict["author"]
            ?? "Anonymous"

        let date: Date?
        if let rawDate = attributeDict["created_at"] {
            if let timestamp = TimeInterval(rawDate) {
                date = Date(timeIntervalSince1970: timestamp)
            } else {
                date = GelbooruCommentsClient.isoDate(rawDate)
            }
        } else {
            date = nil
        }

        comments.append(
            BooruComment(
                id: id,
                author: author,
                avatarURL: nil,
                body: attributeDict["body"] ?? "",
                createdAt: date,
                score: attributeDict["score"].flatMap(Int.init),
                userVote: .none
            )
        )
    }
}

private extension String {
    var trimmedNonEmpty: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
