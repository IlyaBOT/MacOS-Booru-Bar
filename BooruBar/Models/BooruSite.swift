import Foundation

struct BooruSite: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var baseURL: URL
    var apiType: BooruAPIType
    var hasAPIKey: Bool

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: URL,
        apiType: BooruAPIType = .philomena,
        hasAPIKey: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiType = apiType
        self.hasAPIKey = hasAPIKey
    }
}

enum BooruAPIType: String, Codable, CaseIterable, Identifiable {
    case philomena
    case e621
    case gelbooru

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .philomena:
            return "Philomena"
        case .e621:
            return "e621"
        case .gelbooru:
            return "Gelbooru"
        }
    }
}
