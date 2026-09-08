import Combine
import Foundation

@MainActor
final class SettingsStore: ObservableObject {
    @Published var sites: [BooruSite] = [] {
        didSet {
            saveSites()
        }
    }

    @Published var selectedSiteID: UUID = SettingsStore.defaultSites[0].id {
        didSet {
            userDefaults.set(selectedSiteID.uuidString, forKey: Keys.selectedSiteID)
        }
    }

    @Published var nsfwEnabled: Bool = false {
        didSet {
            userDefaults.set(nsfwEnabled, forKey: Keys.nsfwEnabled)
        }
    }

    @Published var selectedFilterIDsBySiteID: [String: Int] = [:] {
        didSet {
            userDefaults.set(selectedFilterIDsBySiteID, forKey: Keys.selectedFilterIDsBySiteID)
        }
    }

    @Published var playAnimatedMedia: Bool = false {
        didSet {
            userDefaults.set(playAnimatedMedia, forKey: Keys.playAnimatedMedia)
        }
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

    func selectedFilterID(for site: BooruSite) -> Int? {
        selectedFilterIDsBySiteID[site.id.uuidString] ?? BooruFilterOption.defaultFilterID(for: site)
    }

    func selectedFilterName(for site: BooruSite) -> String {
        let options = BooruFilterOption.options(for: site)
        guard !options.isEmpty else {
            return "Site default"
        }

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
        }

        if let index = sites.firstIndex(where: { $0.id == savedSite.id }) {
            sites[index] = savedSite
        } else {
            sites.append(savedSite)
        }

        selectedSiteID = savedSite.id
    }

    func deleteSite(_ site: BooruSite) {
        guard !isDefaultSite(site) else {
            return
        }

        keychainStore.deleteAPIKey(for: site.id)
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
    }

    private func saveSites() {
        guard let data = try? JSONEncoder().encode(sites) else {
            return
        }

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

            if normalizedSite.id == e621SiteID || normalizedSite.baseURL.host?.lowercased().contains("e621.net") == true {
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
    }

    private enum Keys {
        static let sites = "booruSites"
        static let selectedSiteID = "selectedSiteID"
        static let nsfwEnabled = "nsfwEnabled"
        static let selectedFilterIDsBySiteID = "selectedFilterIDsBySiteID"
        static let playAnimatedMedia = "playAnimatedMedia"
    }

    static let defaultSites: [BooruSite] = [
        BooruSite(
            id: UUID(uuidString: "C3DE6F79-33CA-4DAB-81B1-F35A255B346A")!,
            name: "Derpibooru",
            baseURL: URL(string: "https://derpibooru.org")!
        ),
        BooruSite(
            id: UUID(uuidString: "F673845A-DA5A-4AF4-BF3E-A535073F07A0")!,
            name: "Furbooru",
            baseURL: URL(string: "https://furbooru.org")!
        ),
        BooruSite(
            id: e621SiteID,
            name: "e621",
            baseURL: URL(string: "https://e621.net")!,
            apiType: .e621
        )
    ]

    private static let e621SiteID = UUID(uuidString: "496BD647-93B0-4D2B-B4A1-3EFDBD1816B3")!
    private static let defaultSiteIDs = Set(defaultSites.map(\.id))
}
