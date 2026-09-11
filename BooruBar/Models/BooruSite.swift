import Foundation

struct BooruSite: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var baseURL: URL
    var apiType: BooruAPIType
    var protocolType: BooruProtocol?
    var hasAPIKey: Bool

    init(
        id: UUID = UUID(),
        name: String,
        baseURL: URL,
        apiType: BooruAPIType = .philomena,
        protocolType: BooruProtocol? = nil,
        hasAPIKey: Bool = false
    ) {
        self.id = id
        self.name = name
        self.baseURL = baseURL
        self.apiType = apiType
        self.protocolType = protocolType
        self.hasAPIKey = hasAPIKey
    }

    /// Protocol used for network requests. `apiType` is kept in the model for
    /// backward compatibility with settings saved by older app versions.
    var resolvedProtocol: BooruProtocol {
        protocolType ?? BooruProtocol(legacyAPIType: apiType)
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

enum BooruProtocol: String, Codable, CaseIterable, Identifiable {
    case philomena
    case e621
    case gelbooru
    case moebooru
    case danbooru
    case shimmie

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .philomena:
            return "Philomena"
        case .e621:
            return "e621"
        case .gelbooru:
            return "Gelbooru"
        case .moebooru:
            return "Moebooru"
        case .danbooru:
            return "Danbooru"
        case .shimmie:
            return "Shimmie"
        }
    }

    /// Maps the extended protocol list to the three values stored by older
    /// versions of BooruBar. New code should use `BooruSite.resolvedProtocol`.
    var legacyAPIType: BooruAPIType {
        switch self {
        case .philomena:
            return .philomena
        case .e621:
            return .e621
        case .gelbooru, .moebooru, .danbooru, .shimmie:
            return .gelbooru
        }
    }

    init(legacyAPIType: BooruAPIType) {
        switch legacyAPIType {
        case .philomena:
            self = .philomena
        case .e621:
            self = .e621
        case .gelbooru:
            self = .gelbooru
        }
    }

    static func detected(from url: URL) -> BooruProtocol? {
        guard let host = url.host?.lowercased() else {
            return nil
        }

        // Order matters: safebooru.donmai.us is Danbooru, while
        // safebooru.org is Gelbooru-compatible.
        if host == "danbooru.donmai.us"
            || host == "safebooru.donmai.us"
            || host.hasSuffix(".donmai.us")
            || host == "aibooru.online" {
            return .danbooru
        }

        if host == "e621.net" || host == "e926.net"
            || host.hasSuffix(".e621.net") || host.hasSuffix(".e926.net") {
            return .e621
        }

        if host == "yande.re"
            || host.hasSuffix(".yande.re")
            || host == "konachan.com"
            || host == "konachan.net"
            || host.hasSuffix(".konachan.com")
            || host.hasSuffix(".konachan.net")
            || host == "sakugabooru.com"
            || host.hasSuffix(".sakugabooru.com")
            || host == "lolibooru.moe"
            || host == "behoimi.org" {
            return .moebooru
        }

        if host == "rule34.paheal.net" || host.hasSuffix(".paheal.net") {
            return .shimmie
        }

        if host.contains("derpibooru")
            || host.contains("furbooru")
            || host.contains("ponybooru") {
            return .philomena
        }

        if host.contains("gelbooru")
            || host == "safebooru.org"
            || host.hasSuffix(".safebooru.org")
            || host.hasSuffix(".booru.org")
            || host == "rule34.xxx"
            || host == "xbooru.com"
            || host == "realbooru.com"
            || host == "tbib.org" {
            return .gelbooru
        }

        return nil
    }
}
