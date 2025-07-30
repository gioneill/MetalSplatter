import Foundation
import simd

struct ModelConfiguration: Equatable, Hashable, Codable {
    let modelIdentifier: ModelIdentifier
    let usePreprocessComputeShader: Bool
}

struct SavedCameraPose: Codable {
    var position: SIMD3<Float>
    var rotation: simd_quatf
    var scale: Float
}

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
    
    static var rvSample: ModelIdentifier? {
        guard let url = Bundle.main.url(forResource: "RV-compressed", withExtension: "ply") else {
            return nil
        }
        return .gaussianSplat(url)
    }
}
