import Combine
import Foundation

enum BooruAuthenticationMode: String, Codable, CaseIterable, Identifiable {
    case none
    case apiKey
    case credentials

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: return "None"
        case .apiKey: return "API key"
        case .credentials: return "Credentials"
        }
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    @Published var sites: [BooruSite] = [] {
        didSet { saveSites() }
    }

    @Published var selectedSiteID: UUID = SettingsStore.defaultSites[0].id {
        didSet { userDefaults.set(selectedSiteID.uuidString, forKey: Keys.selectedSiteID) }
    }

    @Published var nsfwEnabled: Bool = false {
        didSet { userDefaults.set(nsfwEnabled, forKey: Keys.nsfwEnabled) }
    }

    @Published var selectedFilterIDsBySiteID: [String: Int] = [:] {
        didSet { userDefaults.set(selectedFilterIDsBySiteID, forKey: Keys.selectedFilterIDsBySiteID) }
    }

    @Published var playAnimatedMedia: Bool = false {
        didSet { userDefaults.set(playAnimatedMedia, forKey: Keys.playAnimatedMedia) }
    }

    @Published var authenticationModesBySiteID: [String: String] = [:] {
        didSet { userDefaults.set(authenticationModesBySiteID, forKey: Keys.authenticationModesBySiteID) }
    }

    private let userDefaults: UserDefaults
    private let keychainStore: KeychainStore

    init(userDefaults: UserDefaults = .standard, keychainStore: KeychainStore = KeychainStore()) {
        self.userDefaults = userDefaults
        self.keychainStore = keychainStore
        load()
    }

    var selectedSite: BooruSite {
        sites.first { $0.id == selectedSiteID } ?? sites.first ?? Self.defaultSites[0]
    }

    func apiKey(for site: BooruSite) -> String? {
        keychainStore.apiKey(for: site.id)
    }

    /// Credential string expected by the existing backend clients. Older
    /// builds stored e621/Gelbooru credentials as `name:key` / `id:key`; keep
    /// accepting that layout while composing it from the new secure fields.
    func apiCredential(for site: BooruSite) -> String? {
        guard authenticationMode(for: site) == .apiKey else { return nil }
        let rawKey = apiKey(for: site)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let rawKey, !rawKey.isEmpty else { return nil }

        if rawKey.contains(":") { return rawKey }

        switch site.apiType {
        case .philomena:
            return rawKey
        case .e621:
            guard let username = username(for: site)?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty else {
                return rawKey
            }
            return "\(username):\(rawKey)"
        case .gelbooru:
            guard let userID = userID(for: site)?.trimmingCharacters(in: .whitespacesAndNewlines), !userID.isEmpty else {
                return rawKey
            }
            return "\(userID):\(rawKey)"
        }
    }

    func username(for site: BooruSite) -> String? {
        keychainStore.username(for: site.id)
    }

    func password(for site: BooruSite) -> String? {
        keychainStore.password(for: site.id)
    }

    func userID(for site: BooruSite) -> String? {
        keychainStore.userID(for: site.id)
    }

    func authenticationMode(for site: BooruSite) -> BooruAuthenticationMode {
        guard let rawValue = authenticationModesBySiteID[site.id.uuidString],
              let mode = BooruAuthenticationMode(rawValue: rawValue) else {
            return site.hasAPIKey ? .apiKey : .none
        }
        return mode
    }

    func hasUsableAuthentication(for site: BooruSite) -> Bool {
        switch authenticationMode(for: site) {
        case .none:
            return false
        case .apiKey:
            switch site.apiType {
            case .e621:
                return !(username(for: site) ?? "").isEmpty && !(apiKey(for: site) ?? "").isEmpty
            case .gelbooru:
                return !(userID(for: site) ?? "").isEmpty && !(apiKey(for: site) ?? "").isEmpty
            case .philomena:
                return !(apiKey(for: site) ?? "").isEmpty
            }
        case .credentials:
            return !(username(for: site) ?? "").isEmpty && !(password(for: site) ?? "").isEmpty
        }
    }

    func saveAuthentication(
        for site: BooruSite,
        mode: BooruAuthenticationMode,
        username: String,
        password: String,
        userID: String,
        apiKey: String
    ) throws {
        authenticationModesBySiteID[site.id.uuidString] = mode.rawValue

        let cleanUsername = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanPassword = password
        let cleanUserID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if cleanUsername.isEmpty { keychainStore.deleteUsername(for: site.id) }
        else { try keychainStore.saveUsername(cleanUsername, for: site.id) }

        if cleanPassword.isEmpty { keychainStore.deletePassword(for: site.id) }
        else { try keychainStore.savePassword(cleanPassword, for: site.id) }

        if cleanUserID.isEmpty { keychainStore.deleteUserID(for: site.id) }
        else { try keychainStore.saveUserID(cleanUserID, for: site.id) }

        if cleanAPIKey.isEmpty { keychainStore.deleteAPIKey(for: site.id) }
        else { try keychainStore.saveAPIKey(cleanAPIKey, for: site.id) }

        if let index = sites.firstIndex(where: { $0.id == site.id }) {
            sites[index].hasAPIKey = !cleanAPIKey.isEmpty
        }
    }

    func selectedFilterID(for site: BooruSite) -> Int? {
        selectedFilterIDsBySiteID[site.id.uuidString] ?? BooruFilterOption.defaultFilterID(for: site)
    }

    func selectedFilterName(for site: BooruSite) -> String {
        let options = BooruFilterOption.options(for: site)
        guard !options.isEmpty else { return "Site default" }
        let selectedID = selectedFilterID(for: site)
        return options.first { $0.id == selectedID }?.name ?? options[0].name
    }

    func setSelectedFilterID(_ filterID: Int, for site: BooruSite) {
        selectedFilterIDsBySiteID[site.id.uuidString] = filterID
    }

    func upsertSite(_ site: BooruSite, apiKey: String) throws {
        var savedSite = site
        let trimmedAPIKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedAPIKey.isEmpty {
            keychainStore.deleteAPIKey(for: site.id)
            savedSite.hasAPIKey = false
        } else {
            try keychainStore.saveAPIKey(trimmedAPIKey, for: site.id)
            savedSite.hasAPIKey = true
            if authenticationModesBySiteID[site.id.uuidString] == nil {
                authenticationModesBySiteID[site.id.uuidString] = BooruAuthenticationMode.apiKey.rawValue
            }
        }

        if let index = sites.firstIndex(where: { $0.id == savedSite.id }) {
            sites[index] = savedSite
        } else {
            sites.append(savedSite)
        }

        selectedSiteID = savedSite.id
    }

    func deleteSite(_ site: BooruSite) {
        guard !isDefaultSite(site) else { return }
        keychainStore.deleteAuthentication(for: site.id)
        authenticationModesBySiteID.removeValue(forKey: site.id.uuidString)
        sites.removeAll { $0.id == site.id }
        if !sites.contains(where: { $0.id == selectedSiteID }) {
            selectedSiteID = sites.first?.id ?? Self.defaultSites[0].id
        }
    }

    func isDefaultSite(_ site: BooruSite) -> Bool {
        Self.defaultSiteIDs.contains(site.id)
    }

    private func load() {
        if let data = userDefaults.data(forKey: Keys.sites),
           let decodedSites = try? JSONDecoder().decode([BooruSite].self, from: data),
           !decodedSites.isEmpty {
            sites = Self.normalizedSites(Self.mergingDefaultSites(into: decodedSites))
        } else {
            sites = Self.defaultSites
        }

        if let selectedIDString = userDefaults.string(forKey: Keys.selectedSiteID),
           let selectedID = UUID(uuidString: selectedIDString),
           sites.contains(where: { $0.id == selectedID }) {
            selectedSiteID = selectedID
        } else {
            selectedSiteID = sites.first?.id ?? Self.defaultSites[0].id
        }

        if userDefaults.object(forKey: Keys.nsfwEnabled) != nil {
            nsfwEnabled = userDefaults.bool(forKey: Keys.nsfwEnabled)
        }
        if let storedFilters = userDefaults.dictionary(forKey: Keys.selectedFilterIDsBySiteID) as? [String: Int] {
            selectedFilterIDsBySiteID = storedFilters
        }
        if userDefaults.object(forKey: Keys.playAnimatedMedia) != nil {
            playAnimatedMedia = userDefaults.bool(forKey: Keys.playAnimatedMedia)
        }
        if let storedModes = userDefaults.dictionary(forKey: Keys.authenticationModesBySiteID) as? [String: String] {
            authenticationModesBySiteID = storedModes
        }
    }

    private func saveSites() {
        guard let data = try? JSONEncoder().encode(sites) else { return }
        userDefaults.set(data, forKey: Keys.sites)
    }

    private static func mergingDefaultSites(into sites: [BooruSite]) -> [BooruSite] {
        var mergedSites = sites
        for defaultSite in defaultSites where !mergedSites.contains(where: { $0.id == defaultSite.id }) {
            mergedSites.append(defaultSite)
        }
        return mergedSites
    }

    private static func normalizedSites(_ sites: [BooruSite]) -> [BooruSite] {
        sites.map { site in
            var normalizedSite = site
            let host = normalizedSite.baseURL.host?.lowercased() ?? ""
            if normalizedSite.id == e621SiteID
                || normalizedSite.id == e926SiteID
                || host.contains("e621.net")
                || host.contains("e926.net") {
                normalizedSite.apiType = .e621
            } else if normalizedSite.baseURL.host.map(Self.isGelbooruHost) == true {
                normalizedSite.apiType = .gelbooru
            }
            return normalizedSite
        }
    }

    private static func isGelbooruHost(_ host: String) -> Bool {
        let normalizedHost = host.lowercased()
        return normalizedHost.contains("gelbooru")
            || normalizedHost.contains("safebooru")
            || normalizedHost.hasSuffix(".booru.org")
            || normalizedHost == "tbib.org"
            || normalizedHost == "mspabooru.com"
            || normalizedHost == "xbooru.com"
    }

    private enum Keys {
        static let sites = "booruSites"
        static let selectedSiteID = "selectedSiteID"
        static let nsfwEnabled = "nsfwEnabled"
        static let selectedFilterIDsBySiteID = "selectedFilterIDsBySiteID"
        static let playAnimatedMedia = "playAnimatedMedia"
        static let authenticationModesBySiteID = "authenticationModesBySiteID"
    }

    static let defaultSites: [BooruSite] = [
        BooruSite(
            id: e926SiteID,
            name: "e926",
            baseURL: URL(string: "https://e926.net")!,
            apiType: .e621
        ),
        BooruSite(
            id: e621SiteID,
            name: "e621",
            baseURL: URL(string: "https://e621.net")!,
            apiType: .e621
        ),
        BooruSite(
            id: UUID(uuidString: "F673845A-DA5A-4AF4-BF3E-A535073F07A0")!,
            name: "Furbooru",
            baseURL: URL(string: "https://furbooru.org")!
        ),
        BooruSite(
            id: UUID(uuidString: "C3DE6F79-33CA-4DAB-81B1-F35A255B346A")!,
            name: "Derpibooru",
            baseURL: URL(string: "https://derpibooru.org")!
        ),
        BooruSite(
            id: UUID(uuidString: "B1B74833-E45C-5BDD-BB11-96676791D4D3")!,
            name: "Safebooru",
            baseURL: URL(string: "https://safebooru.org")!,
            apiType: .gelbooru
        ),
        BooruSite(
            id: UUID(uuidString: "52F288AA-E497-585A-A6EA-55C0DC4F83C8")!,
            name: "The Azure Blade",
            baseURL: URL(string: "https://tab.booru.org")!,
            apiType: .gelbooru
        ),
        BooruSite(
            id: UUID(uuidString: "8E7CED24-97C1-58EC-9988-00AF21825C85")!,
            name: "All Girl",
            baseURL: URL(string: "https://allgirl.booru.org")!,
            apiType: .gelbooru
        ),
        BooruSite(
            id: UUID(uuidString: "FCAFA0FD-9A84-59E4-98F2-AACF817CA253")!,
            name: "The /co/llection",
            baseURL: URL(string: "https://the-collection.booru.org")!,
            apiType: .gelbooru
        ),
        BooruSite(
            id: UUID(uuidString: "ADC55C90-6572-5C95-B32C-213244B87A8B")!,
            name: "Illusion Game Cards",
            baseURL: URL(string: "https://illusioncards.booru.org")!,
            apiType: .gelbooru
        ),
        BooruSite(
            id: UUID(uuidString: "EC69A933-EE51-5D65-9CED-6BFA44955950")!,
            name: "Draw Friends",
            baseURL: URL(string: "https://drawfriends.booru.org")!,
            apiType: .gelbooru
        ),
        BooruSite(
            id: UUID(uuidString: "F16ABB39-EE8A-51C6-BF18-C70F69952EDA")!,
            name: "/v/idyart2",
            baseURL: URL(string: "https://vidyart2.booru.org")!,
            apiType: .gelbooru
        ),
        BooruSite(
            id: UUID(uuidString: "9979DCA8-07EF-540D-9486-5149BF1F9C8A")!,
            name: "BlueGunnerBooru",
            baseURL: URL(string: "https://bgb.booru.org")!,
            apiType: .gelbooru
        ),
        BooruSite(
            id: UUID(uuidString: "5149987E-5840-5DA3-83E2-7A5307D42052")!,
            name: "The Big ImageBoard",
            baseURL: URL(string: "https://tbib.org")!,
            apiType: .gelbooru
        ),
        BooruSite(
            id: UUID(uuidString: "48957D78-C321-503E-A985-0F6D71A8EC3D")!,
            name: "MSPA Booru",
            baseURL: URL(string: "https://mspabooru.com")!,
            apiType: .gelbooru
        ),
        BooruSite(
            id: UUID(uuidString: "6BE1D6C6-0056-53C1-8B84-A3254FE7486C")!,
            name: "Xbooru",
            baseURL: URL(string: "https://xbooru.com")!,
            apiType: .gelbooru
        )
    ]

    private static let e926SiteID = UUID(uuidString: "BCC9B0BF-AF92-56D3-9A9D-87C5C4527CB0")!
    private static let e621SiteID = UUID(uuidString: "496BD647-93B0-4D2B-B4A1-3EFDBD1816B3")!
    private static let defaultSiteIDs = Set(defaultSites.map(\.id))
}
