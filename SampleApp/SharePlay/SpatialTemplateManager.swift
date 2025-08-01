#if os(visionOS)
import Foundation
import GroupActivities
import OSLog
import simd
import SwiftUI
import Observation

// visionOS 26: Enhanced participant positioning support
struct ParticipantPositioning {
    let participantID: String
    let isNearby: Bool
    let actualPose: Pose3D?
    let seatPose: Pose3D?
    let isSpatial: Bool
}

@Observable
class SpatialTemplateManager {
    private let logger = Logger(subsystem: "com.metalsplatter", category: "SpatialTemplate")
    
    var currentTemplate: (any SpatialTemplate)?
    var participantRoles: [String: String] = [:] // Role assignments by participant ID
    var participantPositions: [String: ParticipantPositioning] = [:] // visionOS 26: Enhanced positioning
    
    private weak var sessionManager: SharePlaySessionManager?
    
    init() {
        logger.info("SpatialTemplateManager initialized")
    }
    
    func configure(with sessionManager: SharePlaySessionManager) {
        logger.info("Configuring SpatialTemplateManager with session manager (visionOS 26)")
        self.sessionManager = sessionManager
    }
    
    // MARK: - visionOS 26 Participant Positioning
    
    func updateParticipantPositioning(_ participant: Participant, _ state: SystemCoordinator.ParticipantState) {
        let positioning = ParticipantPositioning(
            participantID: participant.id.uuidString,
            isNearby: participant.isNearbyWithLocalParticipant,
            actualPose: state.pose,
            seatPose: state.seat?.pose,
            isSpatial: state.isSpatial
        )
        
        participantPositions[participant.id.uuidString] = positioning
        
        logger.info("visionOS 26 - Updated positioning for participant \(participant.id): nearby=\(positioning.isNearby), spatial=\(positioning.isSpatial)")
        
        print("[SPATIAL] 📍 Participant \(participant.id) positioning updated:")
        print("[SPATIAL]   🏠 Nearby: \(positioning.isNearby)")
        print("[SPATIAL]   🌐 Spatial: \(positioning.isSpatial)")
        if positioning.isNearby {
            print("[SPATIAL]   📍 Using actual pose (can't be repositioned)")
        } else {
            print("[SPATIAL]   💺 Can use seat pose (repositionable)")
        }
    }
    
    func getContentPositionForParticipant(_ participantID: String) -> Pose3D? {
        guard let positioning = participantPositions[participantID] else { 
            logger.warning("No positioning data for participant \(participantID)")
            return nil 
        }
        
        if positioning.isNearby {
            // visionOS 26: For nearby participants, use their actual pose since they can't be repositioned
            logger.info("Using actual pose for nearby participant \(participantID)")
            return positioning.actualPose
        } else {
            // visionOS 26: For remote participants, prefer seat pose as they can be repositioned
            logger.info("Using seat pose for remote participant \(participantID)")
            return positioning.seatPose ?? positioning.actualPose
        }
    }
    
    func getPositioningInfo(for participantID: String) -> ParticipantPositioning? {
        return participantPositions[participantID]
    }
    
    // MARK: - Template Creation
    
    func createDefaultViewingTemplate() -> DefaultViewingTemplate {
        logger.info("Creating default viewing template")
        
        return DefaultViewingTemplate()
    }
    
    func createImmersiveTemplate() -> ImmersiveTemplate {
        logger.info("Creating immersive spatial template")
        
        return ImmersiveTemplate()
    }
    
    func createCollaborativeTemplate() -> CollaborativeTemplate {
        logger.info("Creating collaborative spatial template")
        
        return CollaborativeTemplate()
    }
    
    // MARK: - Template Management
    
    func applyTemplate(_ template: any SpatialTemplate, for activityType: SpatialActivityType) async {
        logger.info("Applying spatial template for activity type: \(activityType.rawValue)")
        
        guard sessionManager != nil else {
            logger.error("Cannot apply template - missing session manager")
            return
        }
        
        currentTemplate = template
        
        // Note: The actual template application would be done through the SystemCoordinator
        // when configuring the session, not after the session is already active
        logger.info("Set current template with \(template.elements.count) elements")
    }
    
    func assignRole(_ role: String, to participantID: String) {
        logger.info("Assigning role \(role) to participant \(participantID)")
        participantRoles[participantID] = role
    }
    
    func removeRole(from participantID: String) {
        logger.info("Removing role from participant \(participantID)")
        participantRoles.removeValue(forKey: participantID)
    }
    
    // MARK: - Activity Type Detection
    
    func recommendTemplate(for modelIdentifier: ModelIdentifier?, participantCount: Int) -> any SpatialTemplate {
        let activityType = determineActivityType(modelIdentifier: modelIdentifier, participantCount: participantCount)
        
        switch activityType {
        case .viewing:
            return createDefaultViewingTemplate()
        case .immersive:
            return createImmersiveTemplate()
        case .collaborative:
            return createCollaborativeTemplate()
        }
    }
    
    private func determineActivityType(modelIdentifier: ModelIdentifier?, participantCount: Int) -> SpatialActivityType {
        // Determine activity type based on content and participant count
        if participantCount >= 4 {
            return .collaborative
        } else if modelIdentifier != nil {
            return .immersive
        } else {
            return .viewing
        }
    }
}

// MARK: - Supporting Types

enum SpatialActivityType: String, CaseIterable {
    case viewing = "viewing"
    case immersive = "immersive"
    case collaborative = "collaborative"
}

// MARK: - Concrete Template Implementations

struct DefaultViewingTemplate: SpatialTemplate {
    var elements: [any SpatialTemplateElement] {
        [
            // Host position - center front
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: 0.0, z: -1.5)
            ),
            // Viewer positions - arranged in semi-circle
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: -1.0, z: -1.0)
            ),
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: 1.0, z: -1.0)
            ),
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: -1.5, z: -0.5)
            ),
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: 1.5, z: -0.5)
            ),
            // Observer positions - further back
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: -0.75, z: 0.5)
            ),
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: 0.75, z: 0.5)
            )
        ]
    }
}

struct ImmersiveTemplate: SpatialTemplate {
    var elements: [any SpatialTemplateElement] {
        [
            // Host position - optimal viewing angle
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: 0.0, z: -2.5)
            ),
            // Collaborative positions - around the content
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: -2.0, z: -1.5)
            ),
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: 2.0, z: -1.5)
            ),
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: 0.0, z: 0.0)
            ),
            // Viewer positions - wider arrangement for immersive
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: -1.5, z: -2.0)
            ),
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: 1.5, z: -2.0)
            )
        ]
    }
}

struct CollaborativeTemplate: SpatialTemplate {
    var elements: [any SpatialTemplateElement] {
        [
            // Collaborative positions - around a central point
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: 0.0, z: -1.5)
            ),
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: -1.5, z: 0.0)
            ),
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: 1.5, z: 0.0)
            ),
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: 0.0, z: 1.5)
            ),
            // Host position - slightly elevated perspective
            SpatialTemplateSeatElement(
                position: .app.offsetBy(x: 0.0, z: -2.0)
            )
        ]
    }
}

#endif // os(visionOS)
