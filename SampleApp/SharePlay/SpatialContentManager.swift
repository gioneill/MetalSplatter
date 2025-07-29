import Foundation
import RealityKit
import ARKit
import GroupActivities
import Combine
import OSLog
import SwiftUI

@MainActor
class SpatialContentManager: ObservableObject {
    private let logger = Logger(subsystem: "com.metalsplatter", category: "SpatialContent")
    
    @Published var participantIndicators: [String: Entity] = [:]
    @Published var sharedAnnotations: [String: AnnotationEntity] = [:]
    @Published var participantPointers: [String: Entity] = [:]
    
    private var nearbyParticipantHandler: NearbyParticipantHandler?
    private var cancellables = Set<AnyCancellable>()
    
    // RealityKit scene for spatial content
    private var rootEntity: Entity?
    
    init() {
        setupNotifications()
    }
    
    func configure(with nearbyHandler: NearbyParticipantHandler, rootEntity: Entity) {
        self.nearbyParticipantHandler = nearbyHandler
        self.rootEntity = rootEntity
        
        // Observe participant state changes
        nearbyHandler.$participantStates
            .sink { [weak self] states in
                self?.updateParticipantIndicators(states)
            }
            .store(in: &cancellables)
        
        // Observe shared world anchors
        nearbyHandler.$sharedWorldAnchors
            .sink { [weak self] anchors in
                self?.updateWorldAnchoredContent(anchors)
            }
            .store(in: &cancellables)
    }
    
    private func setupNotifications() {
        // Listen for participant pointer updates
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ParticipantPointerUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userInfo = notification.userInfo,
               let position = userInfo["position"] as? SIMD3<Float>,
               let participantID = userInfo["participantID"] as? String,
               let isNearby = userInfo["isNearby"] as? Bool {
                Task { @MainActor in
                    self?.updateParticipantPointer(participantID: participantID, position: position, isNearby: isNearby)
                }
            }
        }
        
        // Listen for annotation updates
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AnnotationReceived"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userInfo = notification.userInfo,
               let annotation = userInfo["annotation"] as? SyncMessage.AnnotationMessage,
               let isNearby = userInfo["isNearby"] as? Bool {
                Task { @MainActor in
                    self?.addSharedAnnotation(annotation, isNearby: isNearby)
                }
            }
        }
        
        // Listen for shared world anchor updates
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SharedWorldAnchorUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userInfo = notification.userInfo,
               let anchorID = userInfo["anchorID"] as? String,
               let anchor = userInfo["anchor"] as? WorldAnchor {
                Task { @MainActor in
                    self?.handleWorldAnchorUpdate(anchorID: anchorID, anchor: anchor)
                }
            }
        }
    }
    
    private func updateParticipantIndicators(_ participantStates: [String: NearbyParticipantHandler.ParticipantSpatialState]) {
        guard let rootEntity = rootEntity else { return }
        
        // Remove indicators for participants who left
        let currentParticipantIDs = Set(participantStates.keys)
        for participantID in participantIndicators.keys {
            if !currentParticipantIDs.contains(participantID) {
                if let indicator = participantIndicators.removeValue(forKey: participantID) {
                    rootEntity.removeChild(indicator)
                }
            }
        }
        
        // Add or update indicators for current participants
        for (participantID, state) in participantStates {
            if let existingIndicator = participantIndicators[participantID] {
                // Update existing indicator
                updateParticipantIndicatorPosition(existingIndicator, state: state)
            } else {
                // Create new indicator
                let indicator = createParticipantIndicator(for: state)
                participantIndicators[participantID] = indicator
                rootEntity.addChild(indicator)
            }
        }
        
        logger.debug("Updated participant indicators for \(participantStates.count) participants")
    }
    
    private func createParticipantIndicator(for state: NearbyParticipantHandler.ParticipantSpatialState) -> Entity {
        let indicator = Entity()
        
        // Create visual representation based on participant type
        let mesh: MeshResource
        let material: RealityKit.Material
        
        if state.isNearby {
            // Blue indicator for nearby participants
            mesh = .generateSphere(radius: 0.05)
            var materialResource = UnlitMaterial(color: .blue)
            materialResource.blending = .transparent(opacity: 0.7)
            material = materialResource
        } else {
            // Green indicator for FaceTime participants
            mesh = .generateBox(size: 0.1)
            var materialResource = UnlitMaterial(color: .green)
            materialResource.blending = .transparent(opacity: 0.7)
            material = materialResource
        }
        
        let modelComponent = ModelComponent(mesh: mesh, materials: [material])
        indicator.components.set(modelComponent)
        
        // Position the indicator
        updateParticipantIndicatorPosition(indicator, state: state)
        
        // Add animation
        let rotationAnimation = FromToByAnimation<Transform>(
            from: Transform(rotation: simd_quatf(angle: 0, axis: [0, 1, 0])),
            to: Transform(rotation: simd_quatf(angle: .pi * 2, axis: [0, 1, 0])),
            duration: 4.0
        )
        let animationResource = try! AnimationResource.generate(with: rotationAnimation)
        indicator.playAnimation(animationResource.repeat())
        
        return indicator
    }
    
    private func updateParticipantIndicatorPosition(_ indicator: Entity, state: NearbyParticipantHandler.ParticipantSpatialState) {
        // Position indicator slightly above participant's head
        let offset = SIMD3<Float>(0, 0.3, 0)
        
        if let transform = nearbyParticipantHandler?.getPositionForContentRelativeToParticipant(state.participant.id.uuidString, offset: offset) {
            indicator.transform = Transform(matrix: transform)
        } else {
            // Fallback positioning
            indicator.position = state.position + offset
            indicator.orientation = state.rotation
        }
    }
    
    private func updateParticipantPointer(participantID: String, position: SIMD3<Float>, isNearby: Bool) {
        guard let rootEntity = rootEntity else { return }
        
        // Remove existing pointer
        if let existingPointer = participantPointers[participantID] {
            rootEntity.removeChild(existingPointer)
        }
        
        // Create new pointer
        let pointer = createParticipantPointer(at: position, isNearby: isNearby)
        participantPointers[participantID] = pointer
        rootEntity.addChild(pointer)
        
        // Auto-remove pointer after a few seconds
        Task {
            try await Task.sleep(for: .seconds(3))
            if let currentPointer = participantPointers[participantID],
               currentPointer == pointer {
                participantPointers.removeValue(forKey: participantID)
                rootEntity.removeChild(pointer)
            }
        }
        
        logger.debug("Updated pointer for participant \(participantID) at \(position)")
    }
    
    private func createParticipantPointer(at position: SIMD3<Float>, isNearby: Bool) -> Entity {
        let pointer = Entity()
        
        // Create a small sphere as pointer
        let mesh = MeshResource.generateSphere(radius: 0.02)
        let color: Color = isNearby ? .blue : .green
        let material = UnlitMaterial(color: UIColor(color))
        
        let modelComponent = ModelComponent(mesh: mesh, materials: [material])
        pointer.components.set(modelComponent)
        pointer.position = position
        
        // Add pulsing animation
        let scaleAnimation = FromToByAnimation<Transform>(
            from: Transform(scale: SIMD3<Float>(1, 1, 1)),
            to: Transform(scale: SIMD3<Float>(1.5, 1.5, 1.5)),
            duration: 0.5
        )
        let animationResource = try! AnimationResource.generate(with: scaleAnimation)
        pointer.playAnimation(animationResource.repeat())
        
        return pointer
    }
    
    private func addSharedAnnotation(_ annotation: SyncMessage.AnnotationMessage, isNearby: Bool) {
        guard let rootEntity = rootEntity else { return }
        
        // Remove existing annotation with same ID
        if let existingAnnotation = sharedAnnotations[annotation.id] {
            rootEntity.removeChild(existingAnnotation.entity)
        }
        
        // Create new annotation
        let annotationEntity = createAnnotationEntity(annotation, isNearby: isNearby)
        sharedAnnotations[annotation.id] = annotationEntity
        rootEntity.addChild(annotationEntity.entity)
        
        logger.info("Added shared annotation: \(annotation.text) at \(annotation.position)")
    }
    
    private func createAnnotationEntity(_ annotation: SyncMessage.AnnotationMessage, isNearby: Bool) -> AnnotationEntity {
        let entity = Entity()
        
        // Create text mesh (simplified - in reality you'd use TextKit or similar)
        let textMesh = MeshResource.generateBox(size: 0.1) // Placeholder
        let textColor: Color = isNearby ? .blue : .green
        let material = UnlitMaterial(color: UIColor(textColor))
        
        let modelComponent = ModelComponent(mesh: textMesh, materials: [material])
        entity.components.set(modelComponent)
        entity.position = annotation.position
        
        // Add billboard behavior to face the user
        let billboardComponent = BillboardComponent()
        entity.components.set(billboardComponent)
        
        return AnnotationEntity(entity: entity, annotation: annotation)
    }
    
    private func updateWorldAnchoredContent(_ anchors: [String: WorldAnchor]) {
        logger.debug("Updating world anchored content for \(anchors.count) anchors")
        
        // For each shared world anchor, we could position content relative to it
        // This enables shared experiences anchored to the real world
        for (anchorID, _) in anchors {
            // Example: Place a shared marker at each anchor
            // In a real app, this might be interactive content, annotations, etc.
            logger.debug("World anchor \(anchorID) updated")
        }
    }
    
    private func handleWorldAnchorUpdate(anchorID: String, anchor: WorldAnchor) {
        logger.debug("Handling world anchor update: \(anchorID)")
        // Handle specific anchor updates (added, moved, removed)
    }
    
    func placeSharedContent(at position: SIMD3<Float>, anchoredToWorld: Bool = false) async {
        guard let rootEntity = rootEntity else { return }
        
        if anchoredToWorld {
            // Create a world anchor for nearby participants
            #if os(visionOS)
            let transform = matrix4x4_translation(position.x, position.y, position.z)
            if let _ = await nearbyParticipantHandler?.createSharedWorldAnchor(at: transform) {
                logger.info("Created shared world anchor for content at \(position)")
            }
            #endif
        } else {
            // Place content without world anchoring (works for all participants)
            let contentEntity = createSharedContentEntity(at: position)
            rootEntity.addChild(contentEntity)
        }
    }
    
    private func createSharedContentEntity(at position: SIMD3<Float>) -> Entity {
        let entity = Entity()
        
        let mesh = MeshResource.generateSphere(radius: 0.1)
        let material = UnlitMaterial(color: .systemYellow)
        
        let modelComponent = ModelComponent(mesh: mesh, materials: [material])
        entity.components.set(modelComponent)
        entity.position = position
        
        return entity
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

struct AnnotationEntity {
    let entity: Entity
    let annotation: SyncMessage.AnnotationMessage
}