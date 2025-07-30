import Foundation
import GroupActivities
import UIKit
import simd
import CoreTransferable

struct SplatViewingActivity: GroupActivity, Transferable {
    static let activityIdentifier = "com.metalsplatter.viewing"
    
    var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.title = "View 3D Splat Together"
        if let modelIdentifier = modelIdentifier {
            metadata.subtitle = modelIdentifier.displayName
        }
        metadata.previewImage = UIImage(named: "splat-preview")?.cgImage
        metadata.supportsContinuationOnTV = false
        metadata.sceneAssociationBehavior = .content(modelIdentifier?.contentID ?? "content:none")
        return metadata
    }
    
    let modelIdentifier: ModelIdentifier?
    
    init(modelIdentifier: ModelIdentifier? = nil) {
        self.modelIdentifier = modelIdentifier
    }
    
    // MARK: - Transferable conformance
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .data)
    }
}

enum SyncMessage: Codable {
    case modelSelection(ModelIdentifier)
    case cameraUpdate(position: SIMD3<Float>, rotation: simd_quatf, timestamp: TimeInterval)
    case viewingStateUpdate(ViewingState)
    case participantPointer(position: SIMD3<Float>, participantID: String)
    case annotation(AnnotationMessage)
    
    struct ViewingState: Codable {
        let isPlaying: Bool
        let currentTime: TimeInterval
        let renderingMode: String
    }
    
    struct AnnotationMessage: Codable {
        let id: String
        let position: SIMD3<Float>
        let text: String
        let participantID: String
        let timestamp: TimeInterval
    }
}

// SIMD3 already conforms to Codable in modern Swift - extension removed to avoid conflict

extension simd_quatf: @retroactive Codable {
    public init(from decoder: Decoder) throws {
        var container = try decoder.unkeyedContainer()
        let x = try container.decode(Float.self)
        let y = try container.decode(Float.self)
        let z = try container.decode(Float.self)
        let w = try container.decode(Float.self)
        self.init(ix: x, iy: y, iz: z, r: w)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(imag.x)
        try container.encode(imag.y)
        try container.encode(imag.z)
        try container.encode(real)
    }
}
