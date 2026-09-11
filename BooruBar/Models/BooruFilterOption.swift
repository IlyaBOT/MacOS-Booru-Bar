import Foundation

struct BooruFilterOption: Identifiable, Hashable {
    let id: Int
    let name: String
    let requiresNSFW: Bool

    init(id: Int, name: String, requiresNSFW: Bool = false) {
        self.id = id
        self.name = name
        self.requiresNSFW = requiresNSFW
    }

    // Keep the existing macOS Philomena filter list behavior unchanged.
    static func options(for site: BooruSite?) -> [BooruFilterOption] {
        guard let host = site?.baseURL.host?.lowercased() else {
            return []
        }

        if host == "derpibooru.org" || host.hasSuffix(".derpibooru.org") {
            return derpibooruSystemFilters
        }

        return []
    }

    static func defaultFilterID(for site: BooruSite?) -> Int? {
        options(for: site).first { $0.name == "Default" }?.id
    }

    // Mobile uses native Philomena filter profiles and rating presets for APIs
    // which do not expose Philomena-style saved filters.
    static func mobileFallbackOptions(for site: BooruSite?) -> [BooruFilterOption] {
        guard let site else {
            return []
        }

        switch site.resolvedProtocol {
        case .philomena:
            return options(for: site)

        case .e621, .moebooru:
            return [
                BooruFilterOption(id: allRatingsID, name: "All"),
                BooruFilterOption(id: safeRatingID, name: "Safe"),
                BooruFilterOption(id: questionableRatingID, name: "Questionable", requiresNSFW: true),
                BooruFilterOption(id: explicitRatingID, name: "Explicit", requiresNSFW: true)
            ]

        case .danbooru:
            return [
                BooruFilterOption(id: allRatingsID, name: "All"),
                BooruFilterOption(id: generalRatingID, name: "General"),
                BooruFilterOption(id: sensitiveRatingID, name: "Sensitive", requiresNSFW: true),
                BooruFilterOption(id: questionableRatingID, name: "Questionable", requiresNSFW: true),
                BooruFilterOption(id: explicitRatingID, name: "Explicit", requiresNSFW: true)
            ]

        case .gelbooru:
            if isModernGelbooru(site) {
                return [
                    BooruFilterOption(id: allRatingsID, name: "All"),
                    BooruFilterOption(id: generalRatingID, name: "General"),
                    BooruFilterOption(id: sensitiveRatingID, name: "Sensitive", requiresNSFW: true),
                    BooruFilterOption(id: questionableRatingID, name: "Questionable", requiresNSFW: true),
                    BooruFilterOption(id: explicitRatingID, name: "Explicit", requiresNSFW: true)
                ]
            }

            return [
                BooruFilterOption(id: allRatingsID, name: "All"),
                BooruFilterOption(id: safeRatingID, name: "Safe"),
                BooruFilterOption(id: questionableRatingID, name: "Questionable", requiresNSFW: true),
                BooruFilterOption(id: explicitRatingID, name: "Explicit", requiresNSFW: true)
            ]

        case .shimmie:
            // Shimmie core does not define a standardized rating field. Sites
            // can add their own rating extensions, so a universal preset would
            // silently hide valid posts on many installations.
            return [BooruFilterOption(id: allRatingsID, name: "All")]
        }
    }

    static func fetchMobileOptions(
        for site: BooruSite,
        apiKey: String?,
        session: URLSession = .shared
    ) async throws -> [BooruFilterOption] {
        guard site.resolvedProtocol == .philomena else {
            return mobileFallbackOptions(for: site)
        }

        var result = try await fetchPhilomenaFilters(
            site: site,
            endpoint: "/api/v1/json/filters/system",
            apiKey: nil,
            session: session
        )

        if let rawAPIKey = apiKey {
            let trimmedAPIKey = rawAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmedAPIKey.isEmpty,
               let userFilters = try? await fetchPhilomenaFilters(
                   site: site,
                   endpoint: "/api/v1/json/filters/user",
                   apiKey: trimmedAPIKey,
                   session: session
               ) {
                result.append(contentsOf: userFilters)
            }
        }

        var seen = Set<Int>()
        result = result.filter { seen.insert($0.id).inserted }

        return result.isEmpty ? mobileFallbackOptions(for: site) : result
    }

    static func ratingQuery(for site: BooruSite, filterID: Int?) -> String? {
        guard let filterID else {
            return nil
        }

        switch site.resolvedProtocol {
        case .philomena, .shimmie:
            return nil

        case .e621, .moebooru:
            switch filterID {
            case safeRatingID:
                return "rating:s"
            case questionableRatingID:
                return "rating:q"
            case explicitRatingID:
                return "rating:e"
            default:
                return nil
            }

        case .danbooru:
            switch filterID {
            case generalRatingID:
                return "rating:g"
            case sensitiveRatingID:
                return "rating:s"
            case questionableRatingID:
                return "rating:q"
            case explicitRatingID:
                return "rating:e"
            default:
                return nil
            }

        case .gelbooru:
            switch filterID {
            case safeRatingID:
                return "rating:safe"
            case generalRatingID:
                return "rating:general"
            case sensitiveRatingID:
                return "rating:sensitive"
            case questionableRatingID:
                return "rating:questionable"
            case explicitRatingID:
                return "rating:explicit"
            default:
                return nil
            }
        }
    }

    static func safeRatingQuery(for site: BooruSite) -> String {
        switch site.resolvedProtocol {
        case .philomena:
            return "safe"
        case .e621, .moebooru:
            return "rating:s"
        case .danbooru:
            return "rating:g"
        case .gelbooru:
            return isModernGelbooru(site) ? "rating:general" : "rating:safe"
        case .shimmie:
            return ""
        }
    }

    static let allRatingsID = -10_000
    private static let safeRatingID = -10_001
    private static let questionableRatingID = -10_002
    private static let explicitRatingID = -10_003
    private static let generalRatingID = -10_004
    private static let sensitiveRatingID = -10_005

    private static func isModernGelbooru(_ site: BooruSite) -> Bool {
        site.baseURL.host?.lowercased().contains("gelbooru.com") == true
    }

    private static func fetchPhilomenaFilters(
        site: BooruSite,
        endpoint: String,
        apiKey: String?,
        session: URLSession
    ) async throws -> [BooruFilterOption] {
        var page = 1
        var collected: [BooruFilterOption] = []

        while page <= 20 {
            var queryItems = [
                URLQueryItem(name: "page", value: String(page))
            ]

            if let apiKey {
                queryItems.append(URLQueryItem(name: "key", value: apiKey))
            }

            let url = try URLQueryBuilder.url(
                baseURL: site.baseURL,
                endpoint: endpoint,
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

            let decoded: PhilomenaFilterListResponse
            do {
                decoded = try JSONDecoder().decode(PhilomenaFilterListResponse.self, from: data)
            } catch {
                throw BooruNetworkError.decoding(error)
            }

            let pageFilters = decoded.filters.map {
                BooruFilterOption(
                    id: $0.id,
                    name: $0.name,
                    requiresNSFW: looksAdult(filterName: $0.name)
                )
            }

            collected.append(contentsOf: pageFilters)

            if pageFilters.isEmpty || collected.count >= (decoded.total ?? collected.count) {
                break
            }

            page += 1
        }

        return collected
    }

    private static func looksAdult(filterName: String) -> Bool {
        let value = filterName.lowercased()
        return value.contains("18+")
            || value.contains("nsfw")
            || value.contains("r34")
            || value.contains("explicit")
            || value.contains("dark")
    }

    private static let derpibooruSystemFilters = [
        BooruFilterOption(id: 56027, name: "Everything"),
        BooruFilterOption(id: 37431, name: "Legacy Default"),
        BooruFilterOption(id: 37432, name: "18+ R34", requiresNSFW: true),
        BooruFilterOption(id: 100073, name: "Default"),
        BooruFilterOption(id: 37429, name: "18+ Dark", requiresNSFW: true),
        BooruFilterOption(id: 37430, name: "Maximum Spoilers")
    ]
}

private struct PhilomenaFilterListResponse: Decodable {
    let filters: [PhilomenaFilterDTO]
    let total: Int?
}

private struct PhilomenaFilterDTO: Decodable {
    let id: Int
    let name: String
}
