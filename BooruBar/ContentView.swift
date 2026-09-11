//
//  ContentView.swift
//  BooruBar
//
//  Created by IlyaBOT on 21.06.2026.
//

import AppKit
import SwiftUI

@available(macOS 12.0, *)
struct ContentView: View {
    @ObservedObject private var settingsStore: SettingsStore
    @StateObject private var viewModel: GalleryViewModel
    @State private var isShowingSettings = false
    @State private var isShowingSources = false
    @State private var isShowingFilters = false
    @State private var filterOptions: [BooruFilterOption] = []
    @State private var isLoadingFilters = false
    @State private var commentsRoute: MacCommentsRoute?

    init(settingsStore: SettingsStore) {
        self.settingsStore = settingsStore
        _viewModel = StateObject(wrappedValue: GalleryViewModel(settingsStore: settingsStore))
    }

    var body: some View {
        ZStack {
            Group {
                if isShowingSettings {
                    SettingsView(settingsStore: settingsStore) {
                        isShowingSettings = false
                    }
                } else {
                    mainContent
                }
            }

            if let commentsRoute = commentsRoute {
                MacCommentsView(
                    image: commentsRoute.image,
                    site: commentsRoute.site,
                    settingsStore: settingsStore,
                    onDismiss: {
                        self.commentsRoute = nil
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(nsColor: .windowBackgroundColor))
                .transition(.opacity)
                .zIndex(10)
            }
        }
        .frame(width: 460, height: 720)
        .background(Color(nsColor: .windowBackgroundColor))
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

    private var mainContent: some View {
        VStack(spacing: 12) {
            header

            if isShowingSources {
                sourceList
            }

            if !filterOptions.isEmpty || isLoadingFilters {
                filterControl
            }

            if isShowingFilters {
                filterList
            }

            Picker("Feed", selection: tabBinding) {
                ForEach(GalleryTab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)

            if viewModel.currentTab == .search {
                SearchView(viewModel: viewModel)
            }

            GalleryView(
                viewModel: viewModel,
                playAnimatedMedia: settingsStore.playAnimatedMedia,
                site: selectedSite,
                settingsStore: settingsStore,
                onOpenComments: { image in
                    guard let selectedSite = selectedSite else {
                        return
                    }

                    isShowingSources = false
                    isShowingFilters = false
                    commentsRoute = MacCommentsRoute(
                        image: image,
                        site: selectedSite
                    )
                }
            )
        }
        .padding(14)
    }

    private var header: some View {
        HStack(spacing: 10) {
            quitButton

            Text("BooruBar")
                .font(.title2.bold())
                .lineLimit(1)

            Spacer(minLength: 8)

            Button {
                isShowingSources.toggle()
                isShowingFilters = false
            } label: {
                HStack(spacing: 6) {
                    Text(selectedSiteName)
                        .lineLimit(1)

                    Image(systemName: isShowingSources ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .frame(width: 155, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(settingsStore.sites.isEmpty)
            .help("Booru source")

            Button("Connect") {
                Task {
                    isShowingSources = false
                    isShowingFilters = false
                    await viewModel.connect()
                }
            }
            .disabled(settingsStore.sites.isEmpty || viewModel.isLoading)

            Button {
                isShowingSources = false
                isShowingFilters = false
                isShowingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .help("Settings")
        }
    }

    private var quitButton: some View {
        Button {
            NSApplication.shared.terminate(nil)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color(nsColor: .controlBackgroundColor))
                .frame(width: 18, height: 18)
                .background {
                    Circle()
                        .fill(Color(nsColor: .secondaryLabelColor).opacity(0.75))
                }
        }
        .buttonStyle(.plain)
        .contentShape(Circle())
        .help("Quit BooruBar")
    }

    private var sourceList: some View {
        VStack(spacing: 4) {
            ForEach(settingsStore.sites) { site in
                Button {
                    isShowingSources = false
                    Task {
                        await viewModel.selectSite(site.id)
                    }
                } label: {
                    HStack(spacing: 8) {
                        Text(site.name)
                            .lineLimit(1)

                        Spacer()

                        Text(site.resolvedProtocol.displayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if settingsStore.hasUsableAuthentication(for: site) {
                            Image(systemName: "key.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if viewModel.selectedSiteID == site.id {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private var filterControl: some View {
        HStack(spacing: 8) {
            Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)

            Button {
                guard !isLoadingFilters else { return }
                isShowingFilters.toggle()
                isShowingSources = false
            } label: {
                HStack(spacing: 6) {
                    if isLoadingFilters {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading filters…")
                    } else {
                        Text(currentFilterName)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: isShowingFilters ? "chevron.up" : "chevron.down")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.bordered)
            .disabled(isLoadingFilters)
        }
    }

    private var filterList: some View {
        VStack(spacing: 4) {
            ForEach(filterOptions) { filter in
                Button {
                    guard let selectedSite = selectedSite else {
                        return
                    }

                    settingsStore.setSelectedFilterID(filter.id, for: selectedSite)
                    isShowingFilters = false
                } label: {
                    HStack(spacing: 8) {
                        Text(filter.name)
                            .lineLimit(1)

                        Spacer()

                        if isSelected(filter) {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.tint)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(filter.requiresNSFW && !settingsStore.nsfwEnabled)
            }
        }
        .padding(6)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
    }

    private var selectedSiteName: String {
        selectedSite?.name ?? "No source"
    }

    private var selectedSite: BooruSite? {
        settingsStore.sites.first { $0.id == viewModel.selectedSiteID }
    }

    private var currentFilterName: String {
        guard let selectedSite = selectedSite else {
            return "Site default"
        }

        let selectedID = settingsStore.selectedFilterID(for: selectedSite)
        if selectedID == nil,
           let all = filterOptions.first(where: { $0.id == BooruFilterOption.allRatingsID }) {
            return all.name
        }

        return filterOptions.first(where: { $0.id == selectedID })?.name
            ?? settingsStore.selectedFilterName(for: selectedSite)
    }

    private func isSelected(_ filter: BooruFilterOption) -> Bool {
        guard let selectedSite = selectedSite else { return false }
        let selectedID = settingsStore.selectedFilterID(for: selectedSite)

        if filter.id == BooruFilterOption.allRatingsID {
            return selectedID == nil || selectedID == BooruFilterOption.allRatingsID
        }
        return selectedID == filter.id
    }

    @MainActor
    private func reloadFilterOptions() async {
        guard let selectedSite = selectedSite else {
            filterOptions = []
            return
        }

        let fallback = BooruFilterOption.mobileFallbackOptions(for: selectedSite)

        guard selectedSite.resolvedProtocol == .philomena else {
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

    private var tabBinding: Binding<GalleryTab> {
        Binding(
            get: { viewModel.currentTab },
            set: { newValue in
                Task {
                    isShowingSources = false
                    isShowingFilters = false
                    await viewModel.selectTab(newValue)
                }
            }
        )
    }
}

@available(macOS 12.0, *)
private struct MacCommentsRoute {
    let image: BooruImage
    let site: BooruSite
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView(settingsStore: SettingsStore())
    }
}
