import SwiftUI

@available(macOS 12.0, *)
struct GalleryView: View {
    @ObservedObject var viewModel: GalleryViewModel
    let playAnimatedMedia: Bool
    @State private var lastScrollOffset: CGFloat?
    @State private var scrollDirection: GalleryScrollDirection = .idle

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
                scrollOffsetProbe

                if let errorMessage = viewModel.errorMessage {
                    GalleryMessageView(systemImage: "exclamationmark.triangle", message: errorMessage)
                }

                ForEach(viewModel.images) { image in
                    GalleryCardView(image: image, playAnimatedMedia: playAnimatedMedia)
                        .onAppear {
                            handleAppearance(of: image)
                        }
                }

                if viewModel.isLoading {
                    ProgressView()
                        .padding(.vertical, 18)
                }
            }
            .padding(.vertical, 2)
        }
        .coordinateSpace(name: "galleryScroll")
        .onPreferenceChange(GalleryScrollOffsetPreferenceKey.self) { offset in
            updateScrollDirection(offset)
        }
    }

    private var scrollOffsetProbe: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: GalleryScrollOffsetPreferenceKey.self,
                value: proxy.frame(in: .named("galleryScroll")).minY
            )
        }
        .frame(height: 0)
    }

    private func handleAppearance(of image: BooruImage) {
        if image.id == viewModel.images.first?.id, scrollDirection == .up {
            viewModel.revealPreviousImageIfNeeded(currentItem: image)
            return
        }

        guard scrollDirection != .up else {
            return
        }

        Task {
            await viewModel.loadNextPageIfNeeded(currentItem: image)
        }
    }

    private func updateScrollDirection(_ offset: CGFloat) {
        defer {
            lastScrollOffset = offset
        }

        guard let lastScrollOffset else {
            return
        }

        let delta = offset - lastScrollOffset
        guard abs(delta) > 1 else {
            return
        }

        scrollDirection = delta > 0 ? .up : .down
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

private enum GalleryScrollDirection {
    case idle
    case up
    case down
}

private struct GalleryScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
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
