import Foundation

enum URLQueryBuilderError: LocalizedError {
    case invalidBaseURL

    var errorDescription: String? {
        "The booru base URL is invalid."
    }
}

struct URLQueryBuilder {
    static func url(baseURL: URL, endpoint: String, queryItems: [URLQueryItem]) throws -> URL {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw URLQueryBuilderError.invalidBaseURL
        }

        let basePath = components.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let endpointPath = endpoint.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let pathParts = [basePath, endpointPath].filter { !$0.isEmpty }
        components.path = "/" + pathParts.joined(separator: "/")
        components.queryItems = queryItems

        guard let url = components.url else {
            throw BooruNetworkError.invalidURL
        }

        return url
    }
}
