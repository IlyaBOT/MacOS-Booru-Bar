import SwiftUI

struct SearchView: View {
    @ObservedObject var viewModel: GalleryViewModel

    var body: some View {
        HStack(spacing: 8) {
            TextField("Tags, comma separated", text: $viewModel.searchQuery)
                .textFieldStyle(.roundedBorder)
                .onSubmit {
                    Task {
                        await viewModel.performSearch()
                    }
                }

            Button {
                Task {
                    await viewModel.performSearch()
                }
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .disabled(viewModel.searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || viewModel.isLoading)
            .help("Search")
        }
    }
}
