import SwiftUI

struct MobileContentView: View {
    @ObservedObject private var settingsStore: SettingsStore
    @StateObject private var viewModel: GalleryViewModel

    @State private var showingSettings = false

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
                    Text(selectedSite?.name ?? "iBooruBar")
                        .font(.headline)
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    sourceMenu
                }

                ToolbarItemGroup(placement: .navigationBarTrailing) {
                    if !availableFilters.isEmpty {
                        filterMenu
                    }

                    Button {
                        showingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showingSettings) {
                MobileSettingsView(settingsStore: settingsStore)
            }
            .task {
                await viewModel.loadInitialIfNeeded()
            }
            .onChange(of: settingsStore.sites) { _ in
                Task {
                    await viewModel.handleSitesChanged()
                }
            }
            .onChange(of: settingsStore.selectedSiteID) { siteID in
                Task {
                    await viewModel.selectSite(siteID)
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
            Image(systemName: "globe")
        }
    }

    private var filterMenu: some View {
        Menu {
            ForEach(availableFilters) { filter in
                Button {
                    guard let selectedSite else { return }

                    settingsStore.setSelectedFilterID(
                        filter.id,
                        for: selectedSite
                    )
                } label: {
                    if let selectedSite,
                       settingsStore.selectedFilterID(for: selectedSite) == filter.id {
                        Label(filter.name, systemImage: "checkmark")
                    } else {
                        Text(filter.name)
                    }
                }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease.circle")
        }
    }

    private var selectedSite: BooruSite? {
        settingsStore.sites.first {
            $0.id == viewModel.selectedSiteID
        }
    }

    private var availableFilters: [BooruFilterOption] {
        BooruFilterOption.options(for: selectedSite)
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
