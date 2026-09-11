import Foundation

struct GelbooruDapiClient: BooruClient {
    private let site: BooruSite
    private let apiCredential: String?
    private let filterID: Int?
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(site: BooruSite, apiKey: String? = nil, filterID: Int? = nil, session: URLSession = .shared) {
        self.site = site
        self.apiCredential = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.filterID = filterID
        self.session = session
    }

    func fetchTrending(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        try await fetchPosts(
            tags: "sort:score:desc",
            page: page,
            perPage: perPage,
            nsfwEnabled: nsfwEnabled
        )
    }

    func fetchNewest(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        try await fetchPosts(
            tags: "sort:id:desc",
            page: page,
            perPage: perPage,
            nsfwEnabled: nsfwEnabled
        )
    }

    func search(tags: String, page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        let normalizedTags = normalizeUserTags(tags)
        let query = [normalizedTags, "sort:score:desc"]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        return try await fetchPosts(
            tags: query,
            page: page,
            perPage: perPage,
            nsfwEnabled: nsfwEnabled
        )
    }

    private func fetchPosts(
        tags: String,
        page: Int,
        perPage: Int,
        nsfwEnabled: Bool
    ) async throws -> [BooruImage] {
        let safeLimit = min(max(perPage, 1), 100)
        let apiPage = max(page - 1, 0)

        var queryItems = [
            URLQueryItem(name: "page", value: "dapi"),
            URLQueryItem(name: "s", value: "post"),
            URLQueryItem(name: "q", value: "index"),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "limit", value: String(safeLimit)),
            URLQueryItem(name: "pid", value: String(apiPage)),
            URLQueryItem(name: "tags", value: queryWithSafety(tags, nsfwEnabled: nsfwEnabled))
        ]
        queryItems.append(contentsOf: authenticationQueryItems)

        let url = try URLQueryBuilder.url(
            baseURL: site.baseURL,
            endpoint: "/index.php",
            queryItems: queryItems
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("BooruBar/1.0 (macOS menu bar app)", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BooruNetworkError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BooruNetworkError.httpStatus(httpResponse.statusCode)
        }

        if data.isEmpty {
            return []
        }

        if let serverMessage = try? decoder.decode(String.self, from: data) {
            throw GelbooruDapiError.serverMessage(serverMessage)
        }

        do {
            let decoded = try decoder.decode(GelbooruDapiPostListResponse.self, from: data)
            return decoded.posts.compactMap(mapPost)
        } catch {
            throw BooruNetworkError.decoding(error)
        }
    }

    private func queryWithSafety(_ query: String, nsfwEnabled: Bool) -> String {
        var terms = query
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        let selectedRating = BooruFilterOption.ratingQuery(
            for: site,
            filterID: filterID
        )

        if !nsfwEnabled {
            terms.removeAll { $0.lowercased().hasPrefix("rating:") }
            terms.append(BooruFilterOption.safeRatingQuery(for: site))
        } else if let selectedRating {
            terms.removeAll { $0.lowercased().hasPrefix("rating:") }
            terms.append(selectedRating)
        }

        return terms.joined(separator: " ")
    }

    private func normalizeUserTags(_ tags: String) -> String {
        tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private var authenticationQueryItems: [URLQueryItem] {
        guard let apiCredential else {
            return []
        }

        let parts = apiCredential
            .split(separator: ":", maxSplits: 1)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        if parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            return [
                URLQueryItem(name: "user_id", value: parts[0]),
                URLQueryItem(name: "api_key", value: parts[1])
            ]
        }

        return [URLQueryItem(name: "api_key", value: apiCredential)]
    }

    private func mapPost(_ post: GelbooruDapiPostDTO) -> BooruImage? {
        guard let id = post.id else {
            return nil
        }

        let imageURL = absoluteURL(from: post.fileURL)
            ?? absoluteURL(from: post.sampleURL)
            ?? absoluteURL(from: post.previewURL)
        let mediaKind = BooruMediaKind(url: imageURL)
        let previewURL = absoluteURL(from: post.previewURL)
            ?? absoluteURL(from: post.sampleURL)
            ?? absoluteURL(from: post.fileURL)

        return BooruImage(
            id: id,
            authorName: post.owner?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            pageURL: pageURL(for: id),
            previewURL: previewURL,
            imageURL: imageURL,
            mediaKind: mediaKind,
            width: post.width,
            height: post.height,
            score: post.score,
            tags: post.tags,
            rating: post.rating
        )
    }

    private func pageURL(for id: Int) -> URL {
        var components = URLComponents(url: site.baseURL.appendingPathComponent("index.php"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "page", value: "post"),
            URLQueryItem(name: "s", value: "view"),
            URLQueryItem(name: "id", value: String(id))
        ]

        return components?.url ?? site.baseURL
    }

    private func absoluteURL(from rawValue: String?) -> URL? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }

        if rawValue.hasPrefix("//") {
            return URL(string: "https:" + rawValue)
        }

        return URL(string: rawValue, relativeTo: site.baseURL)?.absoluteURL
    }
}

private enum GelbooruDapiError: LocalizedError {
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .serverMessage(let message):
            return message
        }
    }
}

private struct GelbooruDapiPostListResponse: Decodable {
    let posts: [GelbooruDapiPostDTO]

    private enum CodingKeys: String, CodingKey {
        case post
    }

    init(from decoder: Decoder) throws {
        if let posts = try? [GelbooruDapiPostDTO](from: decoder) {
            self.posts = posts
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let posts = try? container.decode([GelbooruDapiPostDTO].self, forKey: .post) {
            self.posts = posts
        } else if let post = try? container.decode(GelbooruDapiPostDTO.self, forKey: .post) {
            self.posts = [post]
        } else {
            self.posts = []
        }
    }
}

private struct GelbooruDapiPostDTO: Decodable {
    let id: Int?
    let tags: [String]
    let fileURL: String?
    let previewURL: String?
    let sampleURL: String?
    let width: Int?
    let height: Int?
    let score: Int?
    let rating: String?
    let owner: String?

    private enum CodingKeys: String, CodingKey {
        case id
        case tags
        case fileURL = "file_url"
        case previewURL = "preview_url"
        case sampleURL = "sample_url"
        case width
        case height
        case score
        case rating
        case owner
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyInt(forKey: .id)
        tags = container.decodeTags(forKey: .tags)
        fileURL = try? container.decodeIfPresent(String.self, forKey: .fileURL)
        previewURL = try? container.decodeIfPresent(String.self, forKey: .previewURL)
        sampleURL = try? container.decodeIfPresent(String.self, forKey: .sampleURL)
        width = container.decodeLossyInt(forKey: .width)
        height = container.decodeLossyInt(forKey: .height)
        score = container.decodeLossyInt(forKey: .score)
        rating = try? container.decodeIfPresent(String.self, forKey: .rating)
        owner = try? container.decodeIfPresent(String.self, forKey: .owner)
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyInt(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }

        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }

        return nil
    }

    func decodeTags(forKey key: Key) -> [String] {
        if let values = try? decodeIfPresent([String].self, forKey: key) {
            return values
        }

        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
                .split(separator: " ")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return []
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
