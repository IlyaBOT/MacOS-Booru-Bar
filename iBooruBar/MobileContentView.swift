import SwiftUI

struct MobileContentView: View {
    @ObservedObject private var settingsStore: SettingsStore
    @StateObject private var viewModel: GalleryViewModel

    @State private var showingSettings = false
    @State private var filterOptions: [BooruFilterOption] = []
    @State private var isLoadingFilters = false

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        _viewModel = StateObject(
            wrappedValue: GalleryViewModel(settingsStore: settingsStore)
        )
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 10) {
                Picker("Feed", selection: tabBinding) {
                    ForEach(GalleryTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)

                if viewModel.currentTab == .search {
                    MobileSearchView(viewModel: viewModel)
                }

                MobileGalleryView(
                    viewModel: viewModel,
                    playAnimatedMedia: settingsStore.playAnimatedMedia
                )
            }
            .padding(.horizontal, 12)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    sourceMenu
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    filterMenu

                    Button {
                        showingSettings = true
                    } label: {
                        toolbarIconLabel(
                            systemImage: "gearshape",
                            title: "Settings"
                        )
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                MobileSettingsView(settingsStore: settingsStore)
            }
            .task {
                await viewModel.loadInitialIfNeeded()
                await reloadFilterOptions()
            }
            .onChange(of: settingsStore.sites) { _ in
                Task {
                    await viewModel.handleSitesChanged()
                    await reloadFilterOptions()
                }
            }
            .onChange(of: settingsStore.selectedSiteID) { siteID in
                Task {
                    await viewModel.selectSite(siteID)
                    await reloadFilterOptions()
                }
            }
            .onChange(of: settingsStore.nsfwEnabled) { _ in
                Task {
                    await viewModel.reloadForSettingsChange()
                }
            }
            .onChange(of: settingsStore.selectedFilterIDsBySiteID) { _ in
                Task {
                    await viewModel.reloadForSettingsChange()
                }
            }
        }
        .navigationViewStyle(.stack)
    }

    private var sourceMenu: some View {
        Menu {
            ForEach(settingsStore.sites) { site in
                Button {
                    Task {
                        await viewModel.selectSite(site.id)
                    }
                } label: {
                    if site.id == viewModel.selectedSiteID {
                        Label(site.name, systemImage: "checkmark")
                    } else {
                        Text(site.name)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(selectedSite?.name ?? "iBooruBar")
                    .font(.headline)
                    .lineLimit(1)

                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 0.5)
            )
        }
    }

    private var filterMenu: some View {
        Menu {
            if isLoadingFilters {
                Label("Loading filters…", systemImage: "clock")
                    .disabled(true)
            } else if filterOptions.isEmpty {
                Text("No filters available")
            } else {
                ForEach(filterOptions) { filter in
                    Button {
                        guard let selectedSite else { return }

                        settingsStore.setSelectedFilterID(
                            filter.id,
                            for: selectedSite
                        )
                    } label: {
                        if isSelected(filter) {
                            Label(filter.name, systemImage: "checkmark")
                        } else {
                            Text(filter.name)
                        }
                    }
                    .disabled(filter.requiresNSFW && !settingsStore.nsfwEnabled)
                }
            }
        } label: {
            toolbarIconLabel(
                systemImage: "line.3.horizontal.decrease",
                title: "Filter"
            )
        }
    }

    private func toolbarIconLabel(systemImage: String, title: String) -> some View {
        VStack(spacing: 1) {
            Image(systemName: systemImage)
                .font(.system(size: 16))

            Text(title)
                .font(.system(size: 8))
        }
        .frame(minWidth: 34)
    }

    private func isSelected(_ filter: BooruFilterOption) -> Bool {
        guard let selectedSite else {
            return false
        }

        let currentID = settingsStore.selectedFilterID(for: selectedSite)

        if filter.id == BooruFilterOption.allRatingsID {
            return currentID == nil || currentID == BooruFilterOption.allRatingsID
        }

        return currentID == filter.id
    }

    @MainActor
    private func reloadFilterOptions() async {
        guard let selectedSite else {
            filterOptions = []
            return
        }

        let fallback = BooruFilterOption.mobileFallbackOptions(for: selectedSite)

        guard selectedSite.apiType == .philomena else {
            filterOptions = fallback
            return
        }

        isLoadingFilters = true
        defer { isLoadingFilters = false }

        do {
            filterOptions = try await BooruFilterOption.fetchMobileOptions(
                for: selectedSite,
                apiKey: settingsStore.apiKey(for: selectedSite)
            )
        } catch {
            filterOptions = fallback
        }
    }

    private var selectedSite: BooruSite? {
        settingsStore.sites.first {
            $0.id == viewModel.selectedSiteID
        }
    }

    private var tabBinding: Binding<GalleryTab> {
        Binding(
            get: { viewModel.currentTab },
            set: { tab in
                Task {
                    await viewModel.selectTab(tab)
                }
            }
        )
    }
}
