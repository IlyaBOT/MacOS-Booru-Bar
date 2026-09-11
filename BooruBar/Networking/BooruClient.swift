import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif

protocol BooruClient {
    func fetchTrending(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage]
    func fetchNewest(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage]
    func search(tags: String, page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage]
}

enum BooruNetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The booru URL could not be created."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpStatus(let statusCode):
            return "The server returned HTTP \(statusCode)."
        case .decoding(let error):
            return "The server response could not be decoded: \(error.localizedDescription)"
        }
    }
}

// MARK: - Moebooru

/// Moebooru API used by yande.re, Konachan, Sakugabooru and compatible sites.
/// The read API is the old Danbooru-compatible `/post.json` interface.
struct MoebooruClient: BooruClient {
    private let site: BooruSite
    private let filterID: Int?
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(site: BooruSite, filterID: Int? = nil, session: URLSession = .shared) {
        self.site = site
        self.filterID = filterID
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
            tags: "",
            page: page,
            perPage: perPage,
            nsfwEnabled: nsfwEnabled
        )
    }

    func search(tags: String, page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        let normalized = normalizeUserTags(tags)
        let query = [normalized, "order:score"]
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
        let queryItems = [
            URLQueryItem(name: "limit", value: String(min(max(perPage, 1), 100))),
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "tags", value: queryWithSafety(tags, nsfwEnabled: nsfwEnabled))
        ]

        let url = try URLQueryBuilder.url(
            baseURL: site.baseURL,
            endpoint: "/post.json",
            queryItems: queryItems
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("iBooruBar/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BooruNetworkError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BooruNetworkError.httpStatus(httpResponse.statusCode)
        }

        do {
            return try decoder.decode([MoebooruPostDTO].self, from: data).compactMap(mapPost)
        } catch {
            throw BooruNetworkError.decoding(error)
        }
    }

    private func queryWithSafety(_ query: String, nsfwEnabled: Bool) -> String {
        var terms = splitTerms(query)
        let selectedRating = BooruFilterOption.ratingQuery(for: site, filterID: filterID)

        if !nsfwEnabled {
            terms.removeAll { $0.lowercased().hasPrefix("rating:") }
            terms.append("rating:s")
        } else if let selectedRating {
            terms.removeAll { $0.lowercased().hasPrefix("rating:") }
            terms.append(selectedRating)
        }

        return terms.joined(separator: " ")
    }

    private func normalizeUserTags(_ tags: String) -> String {
        splitTerms(tags).joined(separator: " ")
    }

    private func splitTerms(_ value: String) -> [String] {
        value
            .split { $0 == "," || $0.isWhitespace }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private func mapPost(_ post: MoebooruPostDTO) -> BooruImage? {
        guard let id = post.id else { return nil }

        let imageURL = absoluteURL(from: post.fileURL)
            ?? absoluteURL(from: post.jpegURL)
            ?? absoluteURL(from: post.sampleURL)
            ?? absoluteURL(from: post.previewURL)
        let previewURL = absoluteURL(from: post.previewURL)
            ?? absoluteURL(from: post.sampleURL)
            ?? imageURL
        let mediaKind = BooruMediaKind(fileExtension: post.fileExt, fallbackURL: imageURL)

        return BooruImage(
            id: id,
            authorName: post.author?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            pageURL: site.baseURL.appendingPathComponent("post/show").appendingPathComponent(String(id)),
            previewURL: previewURL,
            imageURL: imageURL,
            mediaKind: mediaKind,
            width: post.width,
            height: post.height,
            score: post.score,
            tags: splitTerms(post.tags ?? ""),
            rating: post.rating
        )
    }

    private func absoluteURL(from rawValue: String?) -> URL? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        if rawValue.hasPrefix("//") {
            return URL(string: "https:" + rawValue)
        }
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }
        return URL(string: rawValue, relativeTo: site.baseURL)?.absoluteURL
    }
}

private struct MoebooruPostDTO: Decodable {
    let id: Int?
    let tags: String?
    let author: String?
    let score: Int?
    let fileURL: String?
    let previewURL: String?
    let sampleURL: String?
    let jpegURL: String?
    let fileExt: String?
    let width: Int?
    let height: Int?
    let rating: String?

    enum CodingKeys: String, CodingKey {
        case id, tags, author, score, width, height, rating
        case fileURL = "file_url"
        case previewURL = "preview_url"
        case sampleURL = "sample_url"
        case jpegURL = "jpeg_url"
        case fileExt = "file_ext"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyInt(forKey: .id)
        tags = try? container.decodeIfPresent(String.self, forKey: .tags)
        author = try? container.decodeIfPresent(String.self, forKey: .author)
        score = container.decodeLossyInt(forKey: .score)
        fileURL = try? container.decodeIfPresent(String.self, forKey: .fileURL)
        previewURL = try? container.decodeIfPresent(String.self, forKey: .previewURL)
        sampleURL = try? container.decodeIfPresent(String.self, forKey: .sampleURL)
        jpegURL = try? container.decodeIfPresent(String.self, forKey: .jpegURL)
        fileExt = try? container.decodeIfPresent(String.self, forKey: .fileExt)
        width = container.decodeLossyInt(forKey: .width)
        height = container.decodeLossyInt(forKey: .height)
        rating = try? container.decodeIfPresent(String.self, forKey: .rating)
    }
}

// MARK: - Danbooru

/// Current Danbooru 2 API (`/posts.json`). Authentication, when supplied,
/// follows Danbooru's HTTP Basic `login:api_key` convention.
struct DanbooruClient: BooruClient {
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
            tags: "order:score",
            page: page,
            perPage: perPage,
            nsfwEnabled: nsfwEnabled
        )
    }

    func fetchNewest(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        try await fetchPosts(
            tags: "",
            page: page,
            perPage: perPage,
            nsfwEnabled: nsfwEnabled
        )
    }

    func search(tags: String, page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        let normalized = normalizeUserTags(tags)
        let query = [normalized, "order:score"]
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
        let queryItems = [
            URLQueryItem(name: "limit", value: String(min(max(perPage, 1), 100))),
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "tags", value: queryWithSafety(tags, nsfwEnabled: nsfwEnabled))
        ]

        let url = try URLQueryBuilder.url(
            baseURL: site.baseURL,
            endpoint: "/posts.json",
            queryItems: queryItems
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("iBooruBar/1.0", forHTTPHeaderField: "User-Agent")
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
            return try decoder.decode([DanbooruPostDTO].self, from: data).compactMap(mapPost)
        } catch {
            throw BooruNetworkError.decoding(error)
        }
    }

    private func queryWithSafety(_ query: String, nsfwEnabled: Bool) -> String {
        var terms = splitTerms(query)
        let selectedRating = BooruFilterOption.ratingQuery(for: site, filterID: filterID)

        if !nsfwEnabled {
            terms.removeAll { $0.lowercased().hasPrefix("rating:") }
            terms.append("rating:g")
        } else if let selectedRating {
            terms.removeAll { $0.lowercased().hasPrefix("rating:") }
            terms.append(selectedRating)
        }

        return terms.joined(separator: " ")
    }

    private func normalizeUserTags(_ tags: String) -> String {
        splitTerms(tags).joined(separator: " ")
    }

    private func splitTerms(_ value: String) -> [String] {
        value
            .split { $0 == "," || $0.isWhitespace }
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    private var authorizationHeader: String? {
        guard let apiCredential,
              apiCredential.contains(":"),
              let data = apiCredential.data(using: .utf8) else {
            return nil
        }
        return "Basic \(data.base64EncodedString())"
    }

    private func mapPost(_ post: DanbooruPostDTO) -> BooruImage? {
        guard let id = post.id else { return nil }

        let imageURL = absoluteURL(from: post.fileURL)
            ?? absoluteURL(from: post.largeFileURL)
            ?? absoluteURL(from: post.previewFileURL)
        let previewURL = absoluteURL(from: post.previewFileURL)
            ?? absoluteURL(from: post.largeFileURL)
            ?? imageURL
        let mediaKind = BooruMediaKind(fileExtension: post.fileExt, fallbackURL: imageURL)

        return BooruImage(
            id: id,
            authorName: authorName(from: post),
            pageURL: site.baseURL.appendingPathComponent("posts").appendingPathComponent(String(id)),
            previewURL: previewURL,
            imageURL: imageURL,
            mediaKind: mediaKind,
            width: post.imageWidth,
            height: post.imageHeight,
            score: post.score,
            tags: splitTerms(post.tagString ?? ""),
            rating: post.rating,
            upvotes: post.upScore,
            downvotes: post.downScore,
            commentCount: nil,
            userVote: nil
        )
    }

    private func authorName(from post: DanbooruPostDTO) -> String? {
        let artists = splitTerms(post.tagStringArtist ?? "")
            .map { $0.replacingOccurrences(of: "_", with: " ") }
            .filter { !$0.isEmpty }

        if !artists.isEmpty {
            let prefix = artists.prefix(2).joined(separator: ", ")
            return artists.count > 2 ? "\(prefix) +\(artists.count - 2)" : prefix
        }

        return post.uploaderName?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    }

    private func absoluteURL(from rawValue: String?) -> URL? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        if rawValue.hasPrefix("//") {
            return URL(string: "https:" + rawValue)
        }
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }
        return URL(string: rawValue, relativeTo: site.baseURL)?.absoluteURL
    }
}

private struct DanbooruPostDTO: Decodable {
    let id: Int?
    let rating: String?
    let fileExt: String?
    let imageWidth: Int?
    let imageHeight: Int?
    let score: Int?
    let upScore: Int?
    let downScore: Int?
    let tagString: String?
    let tagStringArtist: String?
    let uploaderName: String?
    let fileURL: String?
    let largeFileURL: String?
    let previewFileURL: String?

    enum CodingKeys: String, CodingKey {
        case id, rating, score
        case fileExt = "file_ext"
        case imageWidth = "image_width"
        case imageHeight = "image_height"
        case upScore = "up_score"
        case downScore = "down_score"
        case tagString = "tag_string"
        case tagStringArtist = "tag_string_artist"
        case uploaderName = "uploader_name"
        case fileURL = "file_url"
        case largeFileURL = "large_file_url"
        case previewFileURL = "preview_file_url"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyInt(forKey: .id)
        rating = try? container.decodeIfPresent(String.self, forKey: .rating)
        fileExt = try? container.decodeIfPresent(String.self, forKey: .fileExt)
        imageWidth = container.decodeLossyInt(forKey: .imageWidth)
        imageHeight = container.decodeLossyInt(forKey: .imageHeight)
        score = container.decodeLossyInt(forKey: .score)
        upScore = container.decodeLossyInt(forKey: .upScore)
        downScore = container.decodeLossyInt(forKey: .downScore)
        tagString = try? container.decodeIfPresent(String.self, forKey: .tagString)
        tagStringArtist = try? container.decodeIfPresent(String.self, forKey: .tagStringArtist)
        uploaderName = try? container.decodeIfPresent(String.self, forKey: .uploaderName)
        fileURL = try? container.decodeIfPresent(String.self, forKey: .fileURL)
        largeFileURL = try? container.decodeIfPresent(String.self, forKey: .largeFileURL)
        previewFileURL = try? container.decodeIfPresent(String.self, forKey: .previewFileURL)
    }
}

// MARK: - Shimmie

/// Shimmie2's optional Danbooru Client API extension. It exposes XML through
/// `/api/danbooru/find_posts` and is intentionally treated as read-only here.
struct ShimmieClient: BooruClient {
    private let site: BooruSite
    private let session: URLSession

    init(site: BooruSite, session: URLSession = .shared) {
        self.site = site
        self.session = session
    }

    func fetchTrending(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        // `order:score` only exists when a Shimmie installation enables the
        // optional Numeric Score extension. The Danbooru Client API itself does
        // not guarantee that extension, so keep this feed compatible with stock
        // Shimmie and use the API's native newest-first ordering.
        try await fetchPosts(tags: "", page: page, perPage: perPage)
    }

    func fetchNewest(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        try await fetchPosts(tags: "", page: page, perPage: perPage)
    }

    func search(tags: String, page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        try await fetchPosts(
            tags: normalizeUserTags(tags),
            page: page,
            perPage: perPage
        )
    }

    private func fetchPosts(tags: String, page: Int, perPage: Int) async throws -> [BooruImage] {
        let queryItems = [
            URLQueryItem(name: "limit", value: String(min(max(perPage, 1), 100))),
            URLQueryItem(name: "page", value: String(max(page, 1))),
            URLQueryItem(name: "tags", value: tags)
        ]

        let url = try URLQueryBuilder.url(
            baseURL: site.baseURL,
            endpoint: "/api/danbooru/find_posts",
            queryItems: queryItems
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("iBooruBar/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw BooruNetworkError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BooruNetworkError.httpStatus(httpResponse.statusCode)
        }

        let parserDelegate = ShimmiePostXMLParser()
        let parser = XMLParser(data: data)
        parser.delegate = parserDelegate
        guard parser.parse() else {
            throw BooruNetworkError.decoding(parser.parserError ?? BooruNetworkError.invalidResponse)
        }

        return parserDelegate.posts.compactMap(mapPost)
    }

    private func normalizeUserTags(_ tags: String) -> String {
        tags
            .split { $0 == "," || $0.isWhitespace }
            .map(String.init)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func mapPost(_ post: ShimmiePostDTO) -> BooruImage? {
        guard let id = post.id else { return nil }

        let imageURL = absoluteURL(from: post.fileURL) ?? absoluteURL(from: post.previewURL)
        let previewURL = absoluteURL(from: post.previewURL) ?? imageURL

        return BooruImage(
            id: id,
            authorName: post.author?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty,
            pageURL: site.baseURL.appendingPathComponent("post/view").appendingPathComponent(String(id)),
            previewURL: previewURL,
            imageURL: imageURL,
            mediaKind: BooruMediaKind(url: imageURL),
            width: post.width,
            height: post.height,
            score: post.score,
            tags: normalizeUserTags(post.tags ?? "").split(separator: " ").map(String.init),
            rating: post.rating == "?" ? nil : post.rating
        )
    }

    private func absoluteURL(from rawValue: String?) -> URL? {
        guard let rawValue, !rawValue.isEmpty else { return nil }
        if rawValue.hasPrefix("//") {
            return URL(string: "https:" + rawValue)
        }
        if let url = URL(string: rawValue), url.scheme != nil {
            return url
        }
        return URL(string: rawValue, relativeTo: site.baseURL)?.absoluteURL
    }
}

private struct ShimmiePostDTO {
    let id: Int?
    let fileURL: String?
    let previewURL: String?
    let width: Int?
    let height: Int?
    let score: Int?
    let rating: String?
    let tags: String?
    let author: String?
}

private final class ShimmiePostXMLParser: NSObject, XMLParserDelegate {
    private(set) var posts: [ShimmiePostDTO] = []

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        guard elementName.lowercased() == "post" else { return }

        posts.append(
            ShimmiePostDTO(
                id: attributeDict["id"].flatMap(Int.init),
                fileURL: attributeDict["file_url"],
                previewURL: attributeDict["preview_url"],
                width: attributeDict["width"].flatMap(Int.init),
                height: attributeDict["height"].flatMap(Int.init),
                score: attributeDict["score"].flatMap(Int.init),
                rating: attributeDict["rating"],
                tags: attributeDict["tags"],
                author: attributeDict["author"]
            )
        )
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
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
