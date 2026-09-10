import SwiftUI

struct MobileGalleryView: View {
    @ObservedObject var viewModel: GalleryViewModel
    let playAnimatedMedia: Bool
    let site: BooruSite?
    @ObservedObject var settingsStore: SettingsStore

    var body: some View {
        Group {
            if let error = viewModel.errorMessage,
               viewModel.images.isEmpty {
                message(
                    icon: "exclamationmark.triangle",
                    text: error
                )
            } else if viewModel.images.isEmpty &&
                        !viewModel.isLoading {
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
                if let error = viewModel.errorMessage {
                    message(
                        icon: "exclamationmark.triangle",
                        text: error
                    )
                    .frame(minHeight: 100)
                }

                ForEach(viewModel.images) { image in
                    MobileGalleryCardView(
                        image: image,
                        playAnimatedMedia: playAnimatedMedia,
                        site: site,
                        settingsStore: settingsStore
                    )
                    .onAppear {
                        Task {
                            await viewModel.loadNextPageIfNeeded(
                                currentItem: image
                            )
                        }
                    }
                }

                if viewModel.isLoading {
                    ProgressView()
                        .padding(.vertical, 24)
                }
            }
            .padding(.vertical, 8)
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if viewModel.currentTab == .search &&
           viewModel.hasSearched {
            message(
                icon: "magnifyingglass",
                text: "Sorry buddy, nothing matched your search."
            )
        } else if viewModel.currentTab == .search {
            message(
                icon: "magnifyingglass",
                text: "Enter tags to search."
            )
        } else {
            message(
                icon: "photo.stack",
                text: "No images to show."
            )
        }
    }

    private func message(
        icon: String,
        text: String
    ) -> some View {
        VStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 30))
                .foregroundColor(.secondary)

            Text(text)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}
