import Foundation

protocol BooruClient {
    func fetchTrending(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage]
    func fetchNewest(page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage]
    func search(tags: String, page: Int, perPage: Int, nsfwEnabled: Bool) async throws -> [BooruImage]
}

enum BooruNetworkError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "The booru URL could not be created."
        case .invalidResponse:
            return "The server returned an invalid response."
        case .httpStatus(let statusCode):
            return "The server returned HTTP \(statusCode)."
        case .decoding(let error):
            return "The server response could not be decoded: \(error.localizedDescription)"
        }
    }
}
