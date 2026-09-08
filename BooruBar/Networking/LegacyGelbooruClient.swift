import Foundation

struct LegacyGelbooruClient: BooruClient {
    private let site: BooruSite
    private let session: URLSession
    private let sitePageSize = 20

    init(site: BooruSite, session: URLSession = .shared) {
        self.site = site
        self.session = session
    }

    static func supports(site: BooruSite) -> Bool {
        guard let host = site.baseURL.host?.lowercased() else {
            return false
        }

        return host.hasSuffix(".booru.org")
    }

    func fetchTrending(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        // Gelbooru Beta 0.1.x does not support score sorting through the list page.
        try await fetchList(tags: "", page: page, perPage: perPage, nsfwEnabled: nsfwEnabled)
    }

    func fetchNewest(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        try await fetchList(tags: "", page: page, perPage: perPage, nsfwEnabled: nsfwEnabled)
    }

    func search(tags: String, page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage] {
        try await fetchList(
            tags: normalizeUserTags(tags),
            page: page,
            perPage: perPage,
            nsfwEnabled: nsfwEnabled
        )
    }

    private func fetchList(
        tags: String,
        page: Int,
        perPage: Int,
        nsfwEnabled: Bool
    ) async throws -> [BooruImage] {
        let desiredCount = max(perPage, 1)
        let logicalOffset = max(page - 1, 0) * desiredCount
        var siteOffset = (logicalOffset / sitePageSize) * sitePageSize
        var itemsToDrop = logicalOffset - siteOffset
        var images: [BooruImage] = []
        var requestCount = 0

        while images.count < desiredCount, requestCount < 8 {
            requestCount += 1
            let html = try await fetchHTML(tags: tags, offset: siteOffset)
            var pageImages = parseListPage(html)

            if itemsToDrop > 0 {
                pageImages = Array(pageImages.dropFirst(itemsToDrop))
                itemsToDrop = 0
            }

            if !nsfwEnabled {
                pageImages = pageImages.filter { image in
                    image.rating?.caseInsensitiveCompare("safe") == .orderedSame
                }
            }

            images.append(contentsOf: pageImages)

            if parseListPage(html).count < sitePageSize {
                break
            }

            siteOffset += sitePageSize
        }

        return Array(images.prefix(desiredCount))
    }

    private func fetchHTML(tags: String, offset: Int) async throws -> String {
        let queryItems = [
            URLQueryItem(name: "page", value: "post"),
            URLQueryItem(name: "s", value: "list"),
            URLQueryItem(name: "tags", value: tags),
            URLQueryItem(name: "pid", value: String(offset))
        ]

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

        guard let html = String(data: data, encoding: .utf8) else {
            throw BooruNetworkError.invalidResponse
        }

        return html
    }

    private func parseListPage(_ html: String) -> [BooruImage] {
        let pattern = #"<a[^>]*id="p(\d+)"[^>]*href="([^"]+)"[^>]*>\s*<img[^>]*src="([^"]+)"[^>]*title="([^"]*)""#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        return regex.matches(in: html, range: range).compactMap { match -> BooruImage? in
            guard match.numberOfRanges >= 5,
                  let idRange = Range(match.range(at: 1), in: html),
                  let hrefRange = Range(match.range(at: 2), in: html),
                  let previewRange = Range(match.range(at: 3), in: html),
                  let titleRange = Range(match.range(at: 4), in: html),
                  let id = Int(html[idRange]) else {
                return nil
            }

            let href = decodeHTMLEntities(String(html[hrefRange]))
            let previewValue = decodeHTMLEntities(String(html[previewRange]))
            let title = decodeHTMLEntities(String(html[titleRange]))
            let previewURL = absoluteURL(from: previewValue)
            let metadata = metadata(fromTitle: title)

            return BooruImage(
                id: id,
                authorName: nil,
                pageURL: absoluteURL(from: href) ?? fallbackPageURL(for: id),
                previewURL: previewURL,
                imageURL: previewURL,
                mediaKind: BooruMediaKind(url: previewURL),
                width: nil,
                height: nil,
                score: metadata.score,
                tags: metadata.tags,
                rating: metadata.rating
            )
        }
    }

    private func metadata(fromTitle title: String) -> (tags: [String], score: Int?, rating: String?) {
        let score = firstMatch(in: title, pattern: #"score:([+-]?\d+)"#).flatMap(Int.init)
        let rating = firstMatch(in: title, pattern: #"rating:([A-Za-z]+)"#)
        let tagPrefix = title.components(separatedBy: "score:").first ?? title
        let tags = tagPrefix
            .split(separator: " ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return (tags, score, rating)
    }

    private func firstMatch(in value: String, pattern: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return nil
        }

        let range = NSRange(value.startIndex..<value.endIndex, in: value)
        guard let match = regex.firstMatch(in: value, range: range),
              match.numberOfRanges > 1,
              let resultRange = Range(match.range(at: 1), in: value) else {
            return nil
        }

        return String(value[resultRange])
    }

    private func normalizeUserTags(_ tags: String) -> String {
        tags
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func absoluteURL(from rawValue: String) -> URL? {
        guard !rawValue.isEmpty else {
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

    private func fallbackPageURL(for id: Int) -> URL {
        var components = URLComponents(url: site.baseURL.appendingPathComponent("index.php"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "page", value: "post"),
            URLQueryItem(name: "s", value: "view"),
            URLQueryItem(name: "id", value: String(id))
        ]

        return components?.url ?? site.baseURL
    }

    private func decodeHTMLEntities(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}
