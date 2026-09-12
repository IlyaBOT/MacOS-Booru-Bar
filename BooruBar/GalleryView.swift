import SwiftUI

@available(macOS 12.0, *)
struct GalleryView: View {
    @ObservedObject var viewModel: GalleryViewModel
    let playAnimatedMedia: Bool
    let site: BooruSite?
    @ObservedObject var settingsStore: SettingsStore
    let onOpenComments: (BooruImage) -> Void

    var body: some View {
        Group {
            if let errorMessage = viewModel.errorMessage, viewModel.images.isEmpty {
                GalleryMessageView(systemImage: "exclamationmark.triangle", message: errorMessage)
            } else if viewModel.images.isEmpty && !viewModel.isLoading {
                emptyState
            } else {
                gallery
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var gallery: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                if let errorMessage = viewModel.errorMessage {
                    GalleryMessageView(systemImage: "exclamationmark.triangle", message: errorMessage)
                }

                ForEach(viewModel.images) { image in
                    GalleryCardView(
                        image: image,
                        playAnimatedMedia: playAnimatedMedia,
                        site: site,
                        settingsStore: settingsStore,
                        onOpenComments: onOpenComments
                    )
                    .onAppear {
                        Task {
                            await viewModel.loadNextPageIfNeeded(currentItem: image)
                        }
                    }
                }

                if viewModel.isLoading {
                    ProgressView()
                        .padding(.vertical, 18)
                }
            }
            .padding(.vertical, 2)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.currentTab == .search && viewModel.hasSearched {
            GalleryMessageView(systemImage: "magnifyingglass", message: "Sorry buddy, nothing matched your search.")
        } else if viewModel.currentTab == .search {
            GalleryMessageView(systemImage: "magnifyingglass", message: "Enter tags to search.")
        } else {
            GalleryMessageView(systemImage: "photo.stack", message: "No images to show.")
        }
    }
}

@available(macOS 12.0, *)
private struct GalleryMessageView: View {
    let systemImage: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(.secondary)

            Text(message)
                .font(.callout)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
