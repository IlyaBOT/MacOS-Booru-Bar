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

    // Reserved client-side sentinel used by the mobile filter picker.
    static let allRatingsID = -1

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

    static func mobileFallbackOptions(for site: BooruSite) -> [BooruFilterOption] {
        switch site.apiType {
        case .philomena:
            let native = options(for: site)
            return native.isEmpty ? [BooruFilterOption(id: allRatingsID, name: "Site default")] : native
        case .e621, .gelbooru:
            // Rating presets for these APIs require query-level handling in the
            // corresponding clients. Keep this picker honest until that path is
            // wired instead of presenting filters that do nothing.
            return []
        }
    }

    static func fetchMobileOptions(for site: BooruSite, apiKey: String?) async throws -> [BooruFilterOption] {
        guard site.apiType == .philomena else {
            return mobileFallbackOptions(for: site)
        }

        var result: [BooruFilterOption] = []
        result.append(contentsOf: try await fetchPhilomenaFilters(endpoint: "/api/v1/json/filters/system", site: site, apiKey: apiKey))

        if let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty {
            if let userFilters = try? await fetchPhilomenaFilters(
                endpoint: "/api/v1/json/filters/user",
                site: site,
                apiKey: apiKey
            ) {
                result.append(contentsOf: userFilters)
            }
        }

        var seen = Set<Int>()
        let unique = result.filter { seen.insert($0.id).inserted }
        return unique.isEmpty ? mobileFallbackOptions(for: site) : unique
    }

    private static func fetchPhilomenaFilters(
        endpoint: String,
        site: BooruSite,
        apiKey: String?
    ) async throws -> [BooruFilterOption] {
        var components = URLComponents(
            url: site.baseURL.appendingPathComponent(endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))),
            resolvingAgainstBaseURL: false
        )

        if let apiKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines), !apiKey.isEmpty {
            components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]
        }

        guard let url = components?.url else { throw URLError(.badURL) }
        var request = URLRequest(url: url)
        request.setValue("iBooruBar/1.0", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        let object = try JSONSerialization.jsonObject(with: data)
        let dictionaries: [[String: Any]]
        if let root = object as? [String: Any], let filters = root["filters"] as? [[String: Any]] {
            dictionaries = filters
        } else if let filters = object as? [[String: Any]] {
            dictionaries = filters
        } else {
            return []
        }

        return dictionaries.compactMap { filter in
            let id: Int?
            if let value = filter["id"] as? Int { id = value }
            else if let value = filter["id"] as? NSNumber { id = value.intValue }
            else if let value = filter["id"] as? String { id = Int(value) }
            else { id = nil }

            guard let id, let name = filter["name"] as? String else { return nil }
            return BooruFilterOption(id: id, name: name)
        }
    }

    private static let derpibooruSystemFilters = [
        BooruFilterOption(id: 56027, name: "Everything", requiresNSFW: true),
        BooruFilterOption(id: 37431, name: "Legacy Default"),
        BooruFilterOption(id: 37432, name: "18+ R34", requiresNSFW: true),
        BooruFilterOption(id: 100073, name: "Default"),
        BooruFilterOption(id: 37429, name: "18+ Dark", requiresNSFW: true),
        BooruFilterOption(id: 37430, name: "Maximum Spoilers")
    ]
}
