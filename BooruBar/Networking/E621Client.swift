import Foundation

struct E621Client: BooruClient {
    private let site: BooruSite
    private let apiCredential: String?
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(site: BooruSite, apiKey: String? = nil, session: URLSession = .shared) {
        self.site = site
        self.apiCredential = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.session = session
    }

    func fetchTrending(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        try await fetchPosts(
            tags: "order:score",
            page: page,
            perPage: perPage,
            nsfwEnabled: nsfwEnabled
        )
    }

    func fetchNewest(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        try await fetchPosts(
            tags: "order:id_desc",
            page: page,
            perPage: perPage,
            nsfwEnabled: nsfwEnabled
        )
    }

    func search(tags: String, page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        let normalizedTags = normalizeUserTags(tags)
        let query = [normalizedTags, "order:score"]
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
        let safeLimit = min(max(perPage, 1), 320)
        let queryItems = [
            URLQueryItem(name: "tags", value: queryWithSafety(tags, nsfwEnabled: nsfwEnabled)),
            URLQueryItem(name: "limit", value: String(safeLimit)),
            URLQueryItem(name: "page", value: String(page))
        ]

        let url = try URLQueryBuilder.url(
            baseURL: site.baseURL,
            endpoint: "/posts.json",
            queryItems: queryItems
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("BooruBar/1.0 (macOS menu bar app)", forHTTPHeaderField: "User-Agent")

        if let authorizationHeader {
            request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BooruNetworkError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BooruNetworkError.httpStatus(httpResponse.statusCode)
        }

        do {
            let decoded = try decoder.decode(E621SearchResponse.self, from: data)
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

        terms.append("-type:swf")

        if !nsfwEnabled {
            terms.removeAll { $0.lowercased().hasPrefix("rating:") }
            terms.append("rating:s")
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

    private var authorizationHeader: String? {
        guard let apiCredential,
              apiCredential.contains(":"),
              let data = apiCredential.data(using: .utf8) else {
            return nil
        }

        return "Basic \(data.base64EncodedString())"
    }

    private func mapPost(_ post: E621PostDTO) -> BooruImage? {
        guard let id = post.id else {
            return nil
        }

        let pageURL = site.baseURL.appendingPathComponent("posts").appendingPathComponent(String(id))
        let mediaKind = BooruMediaKind(fileExtension: post.file?.ext, fallbackURL: absoluteURL(from: post.file?.url))
        let previewURL = absoluteURL(from: post.preview?.url)
            ?? absoluteURL(from: post.sample?.url)
            ?? absoluteURL(from: post.file?.url)
        let imageURL = playbackURL(for: post, mediaKind: mediaKind)
            ?? absoluteURL(from: post.preview?.url)
            ?? absoluteURL(from: post.sample?.url)
            ?? absoluteURL(from: post.file?.url)

        return BooruImage(
            id: id,
            authorName: authorName(from: post.tags?.artist),
            pageURL: pageURL,
            previewURL: previewURL,
            imageURL: imageURL,
            mediaKind: mediaKind,
            width: post.file?.width ?? post.sample?.width ?? post.preview?.width,
            height: post.file?.height ?? post.sample?.height ?? post.preview?.height,
            score: post.score?.total,
            tags: post.tags?.flattened ?? [],
            rating: post.rating
        )
    }

    private func authorName(from artists: [String]?) -> String? {
        guard let artists else {
            return nil
        }

        let visibleArtists = artists
            .map { $0.replacingOccurrences(of: "_", with: " ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.caseInsensitiveCompare("unknown_artist") != .orderedSame }

        guard !visibleArtists.isEmpty else {
            return nil
        }

        let prefix = visibleArtists.prefix(2).joined(separator: ", ")
        if visibleArtists.count > 2 {
            return "\(prefix) +\(visibleArtists.count - 2)"
        }

        return prefix
    }

    private func absoluteURL(from rawValue: String?) -> URL? {
        guard let rawValue, !rawValue.isEmpty else {
            return nil
        }

        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }

        return URL(string: rawValue, relativeTo: site.baseURL)?.absoluteURL
    }

    private func playbackURL(for post: E621PostDTO, mediaKind: BooruMediaKind) -> URL? {
        if mediaKind == .video {
            return absoluteURL(from: post.sample?.alternates?.preferredPlaybackURL)
                ?? absoluteURL(from: post.file?.url)
        }

        return absoluteURL(from: post.file?.url)
            ?? absoluteURL(from: post.sample?.url)
    }
}

private struct E621SearchResponse: Decodable {
    let posts: [E621PostDTO]
}

private struct E621PostDTO: Decodable {
    let id: Int?
    let file: E621FileDTO?
    let preview: E621PreviewDTO?
    let sample: E621SampleDTO?
    let score: E621ScoreDTO?
    let tags: E621TagsDTO?
    let rating: String?
}

private struct E621FileDTO: Decodable {
    let width: Int?
    let height: Int?
    let ext: String?
    let url: String?
}

private struct E621PreviewDTO: Decodable {
    let width: Int?
    let height: Int?
    let url: String?
}

private struct E621SampleDTO: Decodable {
    let width: Int?
    let height: Int?
    let url: String?
    let alternates: E621AlternatesDTO?
}

private struct E621AlternatesDTO: Decodable {
    let original: E621VideoVariantDTO?
    let variants: [String: E621VideoVariantDTO]?
    let samples: [String: E621VideoVariantDTO]?

    var preferredPlaybackURL: String? {
        samples?["480p"]?.url
            ?? samples?["720p"]?.url
            ?? variants?["mp4"]?.url
            ?? original?.url
    }
}

private struct E621VideoVariantDTO: Decodable {
    let url: String?
}

private struct E621ScoreDTO: Decodable {
    let total: Int?
}

private struct E621TagsDTO: Decodable {
    let general: [String]?
    let artist: [String]?
    let contributor: [String]?
    let copyright: [String]?
    let character: [String]?
    let species: [String]?
    let invalid: [String]?
    let meta: [String]?
    let lore: [String]?

    enum CodingKeys: String, CodingKey {
        case general
        case artist
        case contributor
        case copyright
        case character
        case species
        case invalid
        case meta
        case lore
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        general = container.decodeStringArray(forKey: .general)
        artist = container.decodeStringArray(forKey: .artist)
        contributor = container.decodeStringArray(forKey: .contributor)
        copyright = container.decodeStringArray(forKey: .copyright)
        character = container.decodeStringArray(forKey: .character)
        species = container.decodeStringArray(forKey: .species)
        invalid = container.decodeStringArray(forKey: .invalid)
        meta = container.decodeStringArray(forKey: .meta)
        lore = container.decodeStringArray(forKey: .lore)
    }

    var flattened: [String] {
        [
            artist,
            character,
            species,
            copyright,
            general,
            meta,
            lore,
            contributor,
            invalid
        ]
        .compactMap { $0 }
        .flatMap { $0 }
    }
}

private extension KeyedDecodingContainer {
    func decodeStringArray(forKey key: Key) -> [String] {
        (try? decodeIfPresent([String].self, forKey: key)) ?? []
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
