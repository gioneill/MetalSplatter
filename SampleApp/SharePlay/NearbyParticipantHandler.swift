import Foundation
import GroupActivities
import ARKit
import RealityKit
import Combine
import OSLog
import QuartzCore

@MainActor
class NearbyParticipantHandler: ObservableObject {
    private let logger = Logger(subsystem: "com.metalsplatter", category: "NearbyParticipants")
    
    @Published var nearbyParticipants: Set<Participant> = []
    @Published var remoteParticipants: Set<Participant> = []
    @Published var participantStates: [String: ParticipantSpatialState] = [:]
    @Published var sharedWorldAnchors: [String: WorldAnchor] = [:]
    
    private var sessionManager: SharePlaySessionManager?
    private var cancellables = Set<AnyCancellable>()
    
    // ARKit session for world anchor sharing
    private var arSession: ARKitSession?
    private var worldTrackingProvider: WorldTrackingProvider?
    
    struct ParticipantSpatialState {
        let participant: Participant
        let isNearby: Bool
        let position: SIMD3<Float>
        let rotation: simd_quatf
        let lastUpdateTime: TimeInterval
        
        // For nearby participants, we might have additional spatial info
        let seatPose: simd_float4x4?
        let participantPose: simd_float4x4?
    }
    
    init() {
        setupARKitSession()
    }
    
    func configure(with sessionManager: SharePlaySessionManager) {
        self.sessionManager = sessionManager
        
        sessionManager.$nearbyParticipants
            .sink { [weak self] participants in
                self?.nearbyParticipants = participants
                self?.updateParticipantStates()
            }
            .store(in: &cancellables)
        
        sessionManager.$remoteParticipants
            .sink { [weak self] participants in
                self?.remoteParticipants = participants
                self?.updateParticipantStates()
            }
            .store(in: &cancellables)
    }
    
    private func setupARKitSession() {
        #if os(visionOS)
        Task {
            arSession = ARKitSession()
            worldTrackingProvider = WorldTrackingProvider()
            
            guard let arSession = arSession,
                  let worldTrackingProvider = worldTrackingProvider else {
                logger.error("Failed to create ARKit session or world tracking provider")
                return
            }
            
            do {
                try await arSession.run([worldTrackingProvider])
                await observeWorldAnchors()
            } catch {
                logger.error("Failed to start ARKit session: \(error)")
            }
        }
        #endif
    }
    
    #if os(visionOS)
    private func observeWorldAnchors() async {
        guard let worldTrackingProvider = worldTrackingProvider else { return }
        
        for await anchorUpdate in worldTrackingProvider.anchorUpdates {
            switch anchorUpdate.event {
            case .added:
                if let worldAnchor = anchorUpdate.anchor as? WorldAnchor,
                   worldAnchor.isSharedWithNearbyParticipants {
                    await handleSharedWorldAnchor(worldAnchor, event: .added)
                }
            case .updated:
                if let worldAnchor = anchorUpdate.anchor as? WorldAnchor,
                   worldAnchor.isSharedWithNearbyParticipants {
                    await handleSharedWorldAnchor(worldAnchor, event: .updated)
                }
            case .removed:
                if let worldAnchor = anchorUpdate.anchor as? WorldAnchor {
                    await handleSharedWorldAnchor(worldAnchor, event: .removed)
                }
            }
        }
    }
    
    private func handleSharedWorldAnchor(_ anchor: WorldAnchor, event: AnchorUpdate<WorldAnchor>.Event) async {
        let anchorID = anchor.id.uuidString
        
        switch event {
        case .added, .updated:
            sharedWorldAnchors[anchorID] = anchor
            logger.info("Shared world anchor \(event == .added ? "added" : "updated"): \(anchorID)")
        case .removed:
            sharedWorldAnchors.removeValue(forKey: anchorID)
            logger.info("Shared world anchor removed: \(anchorID)")
        }
        
        // Notify other components about world anchor changes
        NotificationCenter.default.post(
            name: NSNotification.Name("SharedWorldAnchorUpdate"),
            object: nil,
            userInfo: [
                "anchorID": anchorID,
                "anchor": anchor,
                "event": event
            ]
        )
    }
    
    func createSharedWorldAnchor(at transform: simd_float4x4) async -> WorldAnchor? {
        guard let arSession = arSession else {
            logger.error("ARKit session not available")
            return nil
        }
        
        do {
            let anchor = WorldAnchor(originFromAnchorTransform: transform, sharedWithNearbyParticipants: true)
            // World anchors are automatically tracked when created, no need to explicitly add to session
            
            logger.info("Created shared world anchor: \(anchor.id.uuidString)")
            return anchor
        }
    }
    #endif
    
    private func updateParticipantStates() {
        // Update spatial states for all participants
        let allParticipants = nearbyParticipants.union(remoteParticipants)
        
        for participant in allParticipants {
            let isNearby = nearbyParticipants.contains(participant)
            
            // For this example, we'll use placeholder spatial data
            // In a real implementation, you'd get this from the GroupSession's participant states
            let state = ParticipantSpatialState(
                participant: participant,
                isNearby: isNearby,
                position: SIMD3<Float>(0, 0, 0), // Would come from actual spatial data
                rotation: simd_quatf(ix: 0, iy: 0, iz: 0, r: 1),
                lastUpdateTime: CACurrentMediaTime(),
                seatPose: nil, // Would come from spatial template if available
                participantPose: nil // Would come from participant tracking
            )
            
            participantStates[participant.id.uuidString] = state
        }
        
        // Remove states for participants who left
        let currentParticipantIDs = Set(allParticipants.map { $0.id.uuidString })
        for participantID in participantStates.keys {
            if !currentParticipantIDs.contains(participantID) {
                participantStates.removeValue(forKey: participantID)
            }
        }
        
//        logger.info("Updated participant states - Nearby: \(nearbyParticipants.count), Remote: \(remoteParticipants.count)")
    }
    
    func getPositionForContentRelativeToParticipant(_ participantID: String, offset: SIMD3<Float> = SIMD3<Float>(0, 0, 0)) -> simd_float4x4? {
        guard let state = participantStates[participantID] else { return nil }
        
        if state.isNearby {
            // For nearby participants, position relative to their actual pose
            // Since we can't move them, we position content relative to where they actually are
            if let participantPose = state.participantPose {
                return participantPose * matrix4x4_translation(offset.x, offset.y, offset.z)
            } else {
                // Fallback to basic position
                let translation = matrix4x4_translation(
                    state.position.x + offset.x,
                    state.position.y + offset.y,
                    state.position.z + offset.z
                )
                return translation * simd_float4x4(state.rotation)
            }
        } else {
            // For FaceTime participants, position relative to their seat
            // The system moves their spatial Persona to match their seat
            if let seatPose = state.seatPose {
                return seatPose * matrix4x4_translation(offset.x, offset.y, offset.z)
            } else {
                // Fallback to participant pose
                let translation = matrix4x4_translation(
                    state.position.x + offset.x,
                    state.position.y + offset.y,
                    state.position.z + offset.z
                )
                return translation * simd_float4x4(state.rotation)
            }
        }
    }
    
    func getVisualIndicatorsForParticipants() -> [(participantID: String, position: SIMD3<Float>, isNearby: Bool)] {
        return participantStates.compactMap { (participantID, state) in
            return (participantID, state.position, state.isNearby)
        }
    }
    
    func handleParticipantGesture(participantID: String, gestureType: ParticipantGesture, position: SIMD3<Float>) {
        logger.info("Participant \(participantID) performed gesture: \(gestureType.rawValue) at \(position)")
        
        // Send gesture information to other participants
        if let sessionManager = sessionManager {
            Task {
                // This would be implemented as part of the gesture synchronization system
                // For now, we'll use the participant pointer message
                sessionManager.sendParticipantPointer(position: position, participantID: participantID)
            }
        }
        
        // Post local notification for UI updates
        NotificationCenter.default.post(
            name: NSNotification.Name("ParticipantGesture"),
            object: nil,
            userInfo: [
                "participantID": participantID,
                "gestureType": gestureType,
                "position": position,
                "isNearby": participantStates[participantID]?.isNearby ?? false
            ]
        )
    }
}

enum ParticipantGesture: String, CaseIterable {
    case point = "point"
    case grab = "grab"
    case pinch = "pinch"
    case tap = "tap"
}
