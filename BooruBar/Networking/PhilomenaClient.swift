import Foundation

struct PhilomenaClient: BooruClient {
    private let site: BooruSite
    private let apiKey: String?
    private let filterID: Int?
    private let session: URLSession
    private let decoder = JSONDecoder()

    init(site: BooruSite, apiKey: String? = nil, filterID: Int? = nil, session: URLSession = .shared) {
        self.site = site
        self.apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
        self.filterID = filterID
        self.session = session
    }

    func fetchTrending(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        do {
            return try await fetchImages(
                query: "",
                page: page,
                perPage: perPage,
                nsfwEnabled: nsfwEnabled,
                sortField: "wilson_score",
                sortDirection: "desc"
            )
        } catch BooruNetworkError.httpStatus(let statusCode) where (400..<500).contains(statusCode) {
            return try await fetchImages(
                query: "",
                page: page,
                perPage: perPage,
                nsfwEnabled: nsfwEnabled,
                sortField: "score",
                sortDirection: "desc"
            )
        }
    }

    func fetchNewest(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        try await fetchImages(
            query: "",
            page: page,
            perPage: perPage,
            nsfwEnabled: nsfwEnabled,
            sortField: "created_at",
            sortDirection: "desc"
        )
    }

    func search(tags: String, page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        try await fetchImages(
            query: tags,
            page: page,
            perPage: perPage,
            nsfwEnabled: nsfwEnabled,
            sortField: "score",
            sortDirection: "desc"
        )
    }

    private func fetchImages(
        query: String,
        page: Int,
        perPage: Int,
        nsfwEnabled: Bool,
        sortField: String,
        sortDirection: String
    ) async throws -> [BooruImage] {
        var queryItems = [
            URLQueryItem(name: "q", value: queryWithSafety(query, nsfwEnabled: nsfwEnabled)),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "per_page", value: String(perPage)),
            URLQueryItem(name: "sf", value: sortField),
            URLQueryItem(name: "sd", value: sortDirection)
        ]

        if let apiKey {
            queryItems.append(URLQueryItem(name: "key", value: apiKey))
        }

        if let filterID {
            queryItems.append(URLQueryItem(name: "filter_id", value: String(filterID)))
        }

        let url = try URLQueryBuilder.url(
            baseURL: site.baseURL,
            endpoint: "/api/v1/json/search/images",
            queryItems: queryItems
        )

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("BooruBar/1.0 macOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BooruNetworkError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw BooruNetworkError.httpStatus(httpResponse.statusCode)
        }

        do {
            let decoded = try decoder.decode(PhilomenaSearchResponse.self, from: data)
            return decoded.images.compactMap(mapImage)
        } catch {
            throw BooruNetworkError.decoding(error)
        }
    }

    private func queryWithSafety(_ query: String, nsfwEnabled: Bool) -> String {
        var terms = query
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let shouldUseNativeFilter = filterID != nil

        if terms.isEmpty {
            return (nsfwEnabled || shouldUseNativeFilter) ? "*" : "safe"
        }

        if !nsfwEnabled,
           !shouldUseNativeFilter,
           !terms.contains(where: { $0.caseInsensitiveCompare("safe") == .orderedSame }) {
            terms.append("safe")
        }

        return terms.joined(separator: ", ")
    }

    private func mapImage(_ image: PhilomenaImageDTO) -> BooruImage? {
        guard let id = image.id else {
            return nil
        }

        let imageURL = absoluteURL(from: image.viewURL)
            ?? bestRepresentationURL(
                from: image.representations,
                preferredKeys: ["full", "large", "tall", "medium", "small", "thumb"]
            )
        let mediaKind = BooruMediaKind(url: imageURL)
        let previewKeys = mediaKind.shouldUsePlaybackView
            ? ["thumb", "thumb_small", "small", "medium", "large", "tall", "full"]
            : ["medium", "large", "small", "thumb", "thumb_small", "thumb_tiny", "tall", "full"]
        let previewURL = bestRepresentationURL(
            from: image.representations,
            preferredKeys: previewKeys
        )

        return BooruImage(
            id: id,
            authorName: authorName(from: image.tags, uploader: image.uploaderName ?? image.uploader),
            pageURL: site.baseURL.appendingPathComponent("images").appendingPathComponent(String(id)),
            previewURL: previewURL,
            imageURL: imageURL,
            mediaKind: mediaKind,
            width: image.width,
            height: image.height,
            score: image.score,
            tags: image.tags,
            rating: rating(from: image.tags)
        )
    }

    private func authorName(from tags: [String], uploader: String?) -> String? {
        let artistPrefix = "artist:"
        if let artistTag = tags.first(where: { $0.lowercased().hasPrefix(artistPrefix) }) {
            let artist = String(artistTag.dropFirst(artistPrefix.count))
                .replacingOccurrences(of: "_", with: " ")
                .trimmingCharacters(in: .whitespacesAndNewlines)

            if !artist.isEmpty {
                return artist
            }
        }

        return uploader?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .nilIfEmpty
    }

    private func bestRepresentationURL(from representations: [String: String], preferredKeys: [String]) -> URL? {
        for key in preferredKeys {
            if let value = representations[key], let url = absoluteURL(from: value) {
                return url
            }
        }

        return representations.values.compactMap(absoluteURL).first
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

    private func rating(from tags: [String]) -> String? {
        let knownRatings = ["safe", "suggestive", "questionable", "explicit", "grimdark", "grotesque"]
        return tags.first { tag in
            knownRatings.contains { rating in
                tag.caseInsensitiveCompare(rating) == .orderedSame
            }
        }
    }
}

private struct PhilomenaSearchResponse: Decodable {
    let images: [PhilomenaImageDTO]
}

private struct PhilomenaImageDTO: Decodable {
    let id: Int?
    let viewURL: String?
    let representations: [String: String]
    let tags: [String]
    let score: Int?
    let width: Int?
    let height: Int?
    let uploader: String?
    let uploaderName: String?

    enum CodingKeys: String, CodingKey {
        case id
        case viewURL = "view_url"
        case representations
        case tags
        case score
        case width
        case height
        case uploader
        case uploaderName = "uploader_name"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.decodeLossyInt(forKey: .id)
        viewURL = try? container.decodeIfPresent(String.self, forKey: .viewURL)
        representations = (try? container.decodeIfPresent([String: String].self, forKey: .representations)) ?? [:]
        tags = container.decodeTags(forKey: .tags)
        score = container.decodeLossyInt(forKey: .score)
        width = container.decodeLossyInt(forKey: .width)
        height = container.decodeLossyInt(forKey: .height)
        uploader = try? container.decodeIfPresent(String.self, forKey: .uploader)
        uploaderName = try? container.decodeIfPresent(String.self, forKey: .uploaderName)
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
                .split(separator: ",")
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
