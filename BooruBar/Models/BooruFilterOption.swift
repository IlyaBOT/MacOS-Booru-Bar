import Foundation

struct BooruFilterOption: Identifiable, Hashable {
    let id: Int
    let name: String

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

    private static let derpibooruSystemFilters = [
        BooruFilterOption(id: 56027, name: "Everything"),
        BooruFilterOption(id: 37431, name: "Legacy Default"),
        BooruFilterOption(id: 37432, name: "18+ R34"),
        BooruFilterOption(id: 100073, name: "Default"),
        BooruFilterOption(id: 37429, name: "18+ Dark"),
        BooruFilterOption(id: 37430, name: "Maximum Spoilers")
    ]
}
