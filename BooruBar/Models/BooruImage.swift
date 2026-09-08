import Foundation

struct BooruImage: Identifiable, Codable, Equatable {
    let id: Int
    let authorName: String?
    let pageURL: URL
    let previewURL: URL?
    let imageURL: URL?
    let mediaKind: BooruMediaKind
    let width: Int?
    let height: Int?
    let score: Int?
    let tags: [String]
    let rating: String?
}

enum BooruMediaKind: String, Codable, Equatable {
    case staticImage
    case animatedImage
    case video
    case unknown

    init(url: URL?) {
        guard let fileExtension = url?.pathExtension.lowercased(), !fileExtension.isEmpty else {
            self = .unknown
            return
        }

        self.init(fileExtension: fileExtension)
    }

    init(fileExtension: String?, fallbackURL: URL? = nil) {
        let normalizedExtension = fileExtension?.lowercased()
            ?? fallbackURL?.pathExtension.lowercased()
            ?? ""

        guard !normalizedExtension.isEmpty else {
            self = .unknown
            return
        }

        self.init(fileExtension: normalizedExtension)
    }

    private init(fileExtension: String) {
        switch fileExtension {
        case "gif", "webp":
            self = .animatedImage
        case "mp4", "m4v", "mov", "webm":
            self = .video
        case "jpg", "jpeg", "png", "heic", "heif", "avif":
            self = .staticImage
        default:
            self = .unknown
        }
    }

    var shouldUsePlaybackView: Bool {
        self == .animatedImage || self == .video
    }
}
