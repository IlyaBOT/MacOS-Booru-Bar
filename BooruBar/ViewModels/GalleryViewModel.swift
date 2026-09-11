import Foundation

enum GalleryTab: String, CaseIterable, Identifiable {
    case trending
    case newest
    case search

    var id: String { rawValue }

    var title: String {
        switch self {
        case .trending:
            return "Trending"
        case .newest:
            return "Newest"
        case .search:
            return "Search"
        }
    }
}

@MainActor
final class GalleryViewModel: ObservableObject {
    @Published var currentTab: GalleryTab = .trending
    @Published var selectedSiteID: UUID
    @Published var images: [BooruImage] = []
    @Published var currentPage = 0
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var searchQuery = ""
    @Published var hasMorePages = true
    @Published var hasSearched = false

    private let settingsStore: SettingsStore
    private let perPage = 24
    private var resultCache: [GalleryCacheKey: [BooruImage]] = [:]
    private var activeRequestID: UUID?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        selectedSiteID = settingsStore.selectedSiteID
    }

    func loadInitialIfNeeded() async {
        guard images.isEmpty, !isLoading, currentTab != .search else {
            return
        }

        await loadPage(reset: true)
    }

    func selectSite(_ siteID: UUID) async {
        guard selectedSiteID != siteID else {
            return
        }

        invalidateInFlightLoad()
        selectedSiteID = siteID
        settingsStore.selectedSiteID = siteID
        await loadPage(reset: true)
    }

    func connect() async {
        invalidateInFlightLoad()
        await loadPage(reset: true)
    }

    func selectTab(_ tab: GalleryTab) async {
        guard currentTab != tab else {
            return
        }

        invalidateInFlightLoad()
        currentTab = tab
        errorMessage = nil

        if tab == .search {
            if hasSearched && !trimmedSearchQuery.isEmpty {
                await loadPage(reset: true)
            } else {
                resetForEmptySearch()
            }
        } else {
            await loadPage(reset: true)
        }
    }

    func performSearch() async {
        guard !trimmedSearchQuery.isEmpty else {
            resetForEmptySearch()
            return
        }

        hasSearched = true
        invalidateInFlightLoad()
        await loadPage(reset: true)
    }

    func loadNextPageIfNeeded(currentItem: BooruImage?) async {
        guard let currentItem,
              !isLoading,
              hasMorePages,
              shouldLoadMore(after: currentItem) else {
            return
        }

        await loadPage(reset: false)
    }

    func handleSitesChanged() async {
        resultCache.removeAll()

        if settingsStore.sites.contains(where: { $0.id == settingsStore.selectedSiteID }) {
            selectedSiteID = settingsStore.selectedSiteID
        } else if !settingsStore.sites.contains(where: { $0.id == selectedSiteID }) {
            selectedSiteID = settingsStore.selectedSiteID
        }

        await reloadForSettingsChange()
    }

    func reloadForSettingsChange() async {
        guard currentTab != .search || (hasSearched && !trimmedSearchQuery.isEmpty) else {
            return
        }

        invalidateInFlightLoad()
        await loadPage(reset: true)
    }

    private func loadPage(reset: Bool) async {
        guard !isLoading else {
            return
        }

        if currentTab == .search && trimmedSearchQuery.isEmpty {
            resetForEmptySearch()
            return
        }

        if reset {
            currentPage = 0
            hasMorePages = true
            images = []
            errorMessage = nil
        }

        guard hasMorePages else {
            return
        }

        guard let site = settingsStore.sites.first(where: { $0.id == selectedSiteID }) else {
            errorMessage = "Select a booru source to continue."
            return
        }

        let nextPage = currentPage + 1
        let cacheKey = GalleryCacheKey(
            siteID: site.id,
            tab: currentTab,
            query: currentTab == .search ? trimmedSearchQuery : "",
            page: nextPage,
            perPage: perPage,
            nsfwEnabled: settingsStore.nsfwEnabled,
            filterID: settingsStore.selectedFilterID(for: site)
        )

        if let cachedImages = resultCache[cacheKey] {
            apply(cachedImages, page: nextPage, reset: reset)
            return
        }

        let requestID = UUID()
        activeRequestID = requestID
        isLoading = true

        defer {
            if activeRequestID == requestID {
                activeRequestID = nil
                isLoading = false
            }
        }

        do {
            // Existing e621/Gelbooru clients expect composed credentials
            // (username:key / userID:key), not the raw API key alone.
            let apiCredential = settingsStore.apiCredential(for: site)
            let client = makeClient(for: site, apiKey: apiCredential)
            let fetchedImages: [BooruImage]

            switch currentTab {
            case .trending:
                fetchedImages = try await client.fetchTrending(
                    page: nextPage,
                    perPage: perPage,
                    nsfwEnabled: settingsStore.nsfwEnabled
                )
            case .newest:
                fetchedImages = try await client.fetchNewest(
                    page: nextPage,
                    perPage: perPage,
                    nsfwEnabled: settingsStore.nsfwEnabled
                )
            case .search:
                fetchedImages = try await client.search(
                    tags: trimmedSearchQuery,
                    page: nextPage,
                    perPage: perPage,
                    nsfwEnabled: settingsStore.nsfwEnabled
                )
            }

            guard activeRequestID == requestID else {
                return
            }

            resultCache[cacheKey] = fetchedImages
            apply(fetchedImages, page: nextPage, reset: reset)
        } catch {
            guard activeRequestID == requestID else {
                return
            }

            if reset {
                images = []
            }
            errorMessage = Self.userFacingMessage(for: error)
        }
    }

    private func makeClient(for site: BooruSite, apiKey: String?) -> BooruClient {
        let filterID = settingsStore.selectedFilterID(for: site)

        switch site.resolvedProtocol {
        case .philomena:
            return PhilomenaClient(
                site: site,
                apiKey: apiKey,
                filterID: filterID
            )

        case .e621:
            return E621Client(
                site: site,
                apiKey: apiKey,
                filterID: filterID
            )

        case .gelbooru:
            if LegacyGelbooruClient.supports(site: site) {
                return LegacyGelbooruClient(
                    site: site,
                    filterID: filterID
                )
            }

            return GelbooruDapiClient(
                site: site,
                apiKey: apiKey,
                filterID: filterID
            )

        case .moebooru:
            return MoebooruClient(
                site: site,
                filterID: filterID
            )

        case .danbooru:
            return DanbooruClient(
                site: site,
                apiKey: apiKey,
                filterID: filterID
            )

        case .shimmie:
            return ShimmieClient(site: site)
        }
    }

    private func apply(_ fetchedImages: [BooruImage], page: Int, reset: Bool) {
        if reset {
            images = fetchedImages
        } else {
            let existingIDs = Set(images.map(\.id))
            let uniqueImages = fetchedImages.filter { !existingIDs.contains($0.id) }
            images.append(contentsOf: uniqueImages)
        }

        currentPage = page
        hasMorePages = fetchedImages.count >= perPage
    }

    private func shouldLoadMore(after item: BooruImage) -> Bool {
        guard let index = images.firstIndex(where: { $0.id == item.id }) else {
            return false
        }

        let thresholdIndex = images.index(
            images.endIndex,
            offsetBy: -5,
            limitedBy: images.startIndex
        ) ?? images.startIndex
        return index >= thresholdIndex
    }

    private func resetForEmptySearch() {
        currentPage = 0
        hasMorePages = false
        images = []
        errorMessage = nil
    }

    private func invalidateInFlightLoad() {
        activeRequestID = nil
        isLoading = false
    }

    private var trimmedSearchQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func userFacingMessage(for error: Error) -> String {
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }

        return error.localizedDescription
    }
}

private struct GalleryCacheKey: Hashable {
    let siteID: UUID
    let tab: GalleryTab
    let query: String
    let page: Int
    let perPage: Int
    let nsfwEnabled: Bool
    let filterID: Int?
}
