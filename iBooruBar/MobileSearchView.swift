import SwiftUI

struct MobileSearchView: View {
    @ObservedObject var viewModel: GalleryViewModel

    var body: some View {
        HStack(spacing: 8) {
            TextField(
                "Tags, comma separated",
                text: $viewModel.searchQuery
            )
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            .onSubmit {
                search()
            }

            Button {
                search()
            } label: {
                Image(systemName: "magnifyingglass")
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                viewModel.searchQuery
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ||
                viewModel.isLoading
            )
        }
    }

    private func search() {
        Task {
            await viewModel.performSearch()
        }
    }
}
