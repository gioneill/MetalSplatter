import Foundation

enum ModelIdentifier: Equatable, Hashable, Codable, CustomStringConvertible {
    case gaussianSplat(URL)
    case sampleBox

    var description: String {
        switch self {
        case .gaussianSplat(let url):
            "Gaussian Splat: \(url.path)"
        case .sampleBox:
            "Sample Box"
        }
    }
    
    var displayName: String {
        switch self {
        case .gaussianSplat(let url):
            url.lastPathComponent
        case .sampleBox:
            "Sample Box"
        }
    }
    
    var url: URL? {
        switch self {
        case .gaussianSplat(let url):
            url
        case .sampleBox:
            nil
        }
    }
}
