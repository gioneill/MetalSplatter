#if os(visionOS)
import Foundation
import GroupActivities
import OSLog
import simd
import Spatial
import QuartzCore

@MainActor
class ParticipantStateTracker: ObservableObject {
    private let logger = Logger(subsystem: "com.metalsplatter", category: "ParticipantStateTracker")
    
    @Published var participantStates: [String: EnhancedParticipantState] = [:]
    @Published var spatialParticipants: Set<String> = []
    @Published var contentAnchorPoints: [String: Pose3D] = [:]
    
    private var sessionManager: SharePlaySessionManager?
    private var updateTask: Task<Void, Never>?
    
    struct EnhancedParticipantState: Equatable {
        let participant: Participant
        let isNearby: Bool
        let isSpatial: Bool
        let pose: Pose3D
        let seatPose: Pose3D?
        let lastUpdateTime: TimeInterval
        
        // Content positioning helpers
        func contentPosition(offset: SIMD3<Float> = SIMD3<Float>(0, 0, 0)) -> Pose3D {
            let offsetPose = Pose3D(position: Point3D(x: Double(offset.x), y: Double(offset.y), z: Double(offset.z)), rotation: Rotation3D.identity)
            return pose * offsetPose
        }
        
        func seatContentPosition(offset: SIMD3<Float> = SIMD3<Float>(0, 0, 0)) -> Pose3D? {
            guard let seatPose = seatPose else { return nil }
            let offsetPose = Pose3D(position: Point3D(x: Double(offset.x), y: Double(offset.y), z: Double(offset.z)), rotation: Rotation3D.identity)
            return seatPose * offsetPose
        }
        
        static func == (lhs: EnhancedParticipantState, rhs: EnhancedParticipantState) -> Bool {
            return lhs.participant.id == rhs.participant.id &&
                   lhs.isNearby == rhs.isNearby &&
                   lhs.isSpatial == rhs.isSpatial &&
                   lhs.pose == rhs.pose &&
                   lhs.seatPose == rhs.seatPose
        }
    }
    
    init() {
        logger.info("ParticipantStateTracker initialized")
    }
    
    func configure(with sessionManager: SharePlaySessionManager) {
        logger.info("Configuring ParticipantStateTracker with session manager")
        self.sessionManager = sessionManager
        startStateTracking()
    }
    
    private func startStateTracking() {
        guard let sessionManager = sessionManager else {
            logger.error("Cannot start state tracking - no session manager")
            return
        }
        
        updateTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.updateParticipantStates()
                try? await Task.sleep(for: .milliseconds(100)) // Update at 10 FPS
            }
        }
        
        logger.info("Started participant state tracking")
    }
    
    private func updateParticipantStates() async {
        guard let sessionManager = sessionManager else { return }
        
        let nearbyParticipants = sessionManager.nearbyParticipants
        let remoteParticipants = sessionManager.remoteParticipants
        
        var newStates: [String: EnhancedParticipantState] = [:]
        var newSpatialParticipants: Set<String> = []
        
        // Process all participants (both nearby and remote)
        let allParticipants = nearbyParticipants.union(remoteParticipants)
        
        for participant in allParticipants {
            let participantID = participant.id.uuidString
            let isNearby = nearbyParticipants.contains(participant)
            
            // Create a basic state since we don't have access to SystemCoordinator data
            let enhancedState = EnhancedParticipantState(
                participant: participant,
                isNearby: isNearby,
                isSpatial: false, // Default to false since we can't determine this
                pose: Pose3D.identity, // Default pose
                seatPose: nil,
                lastUpdateTime: CACurrentMediaTime()
            )
            
            newStates[participantID] = enhancedState
            
            // Log state changes
            if let previousState = participantStates[participantID] {
                if previousState.isSpatial != enhancedState.isSpatial {
                    logger.info("Participant \(participantID) spatial state changed: \(enhancedState.isSpatial)")
                }
                if previousState.pose != enhancedState.pose {
                    logger.debug("Participant \(participantID) pose updated")
                }
            }
        }
        
        // Update published properties
        let statesChanged = participantStates != newStates
        let spatialChanged = spatialParticipants != newSpatialParticipants
        
        if statesChanged || spatialChanged {
            participantStates = newStates
            spatialParticipants = newSpatialParticipants
            
            logger.debug("Updated participant states: \(newStates.count) total, \(newSpatialParticipants.count) spatial")
            
            // Update content anchor points for spatial participants
            updateContentAnchorPoints()
            
            // Post notification for other components
            NotificationCenter.default.post(
                name: NSNotification.Name("ParticipantStatesUpdated"),
                object: nil,
                userInfo: [
                    "participantStates": participantStates,
                    "spatialParticipants": spatialParticipants
                ]
            )
        }
    }
    
    private func updateContentAnchorPoints() {
        var newAnchorPoints: [String: Pose3D] = [:]
        
        for (participantID, state) in participantStates {
            if state.isSpatial {
                // For spatial participants, use their actual pose
                newAnchorPoints[participantID] = state.pose
            } else if let seatPose = state.seatPose {
                // For non-spatial participants, use their seat pose
                newAnchorPoints[participantID] = seatPose
            }
        }
        
        contentAnchorPoints = newAnchorPoints
    }
    
    // MARK: - Public Interface
    
    func getParticipantState(for participantID: String) -> EnhancedParticipantState? {
        return participantStates[participantID]
    }
    
    func getSpatialParticipants() -> [EnhancedParticipantState] {
        return spatialParticipants.compactMap { participantStates[$0] }
    }
    
    func getNearbyParticipants() -> [EnhancedParticipantState] {
        return participantStates.values.filter { $0.isNearby }
    }
    
    func getRemoteParticipants() -> [EnhancedParticipantState] {
        return participantStates.values.filter { !$0.isNearby }
    }
    
    func getContentAnchorPoint(for participantID: String, offset: SIMD3<Float> = SIMD3<Float>(0, 0, 0)) -> Pose3D? {
        guard let baseAnchor = contentAnchorPoints[participantID] else { return nil }
        
        let offsetPose = Pose3D(position: Point3D(x: Double(offset.x), y: Double(offset.y), z: Double(offset.z)), rotation: Rotation3D.identity)
        return baseAnchor * offsetPose
    }
    
    func positionContentRelativeToParticipant(_ participantID: String, offset: SIMD3<Float> = SIMD3<Float>(0, 0, 0)) -> simd_float4x4? {
        guard let anchorPoint = getContentAnchorPoint(for: participantID, offset: offset) else { return nil }
        
        // Convert Pose3D to simd_float4x4
        let affineTransform = AffineTransform3D(pose: anchorPoint)
        let matrix = affineTransform.matrix
        return simd_float4x4(
            SIMD4<Float>(Float(matrix.columns.0.x), Float(matrix.columns.0.y), Float(matrix.columns.0.z), 0),
            SIMD4<Float>(Float(matrix.columns.1.x), Float(matrix.columns.1.y), Float(matrix.columns.1.z), 0),
            SIMD4<Float>(Float(matrix.columns.2.x), Float(matrix.columns.2.y), Float(matrix.columns.2.z), 0),
            SIMD4<Float>(Float(matrix.columns.3.x), Float(matrix.columns.3.y), Float(matrix.columns.3.z), 1)
        )
    }
    
    func getParticipantVisualizationData() -> [(id: String, position: SIMD3<Float>, isNearby: Bool, isSpatial: Bool)] {
        return participantStates.compactMap { (id, state) in
            let position = SIMD3<Float>(
                Float(state.pose.position.x),
                Float(state.pose.position.y),
                Float(state.pose.position.z)
            )
            return (id: id, position: position, isNearby: state.isNearby, isSpatial: state.isSpatial)
        }
    }
    
    func createSharedContentLayout() -> SharedContentLayout {
        let spatialParticipants = getSpatialParticipants()
        let nearbyParticipants = getNearbyParticipants()
        let remoteParticipants = getRemoteParticipants()
        
        return SharedContentLayout(
            spatialParticipants: spatialParticipants,
            nearbyParticipants: nearbyParticipants,
            remoteParticipants: remoteParticipants,
            contentAnchorPoints: contentAnchorPoints
        )
    }
    
    deinit {
        updateTask?.cancel()
        updateTask = nil
        logger.info("ParticipantStateTracker deinitialized")
    }
}

// MARK: - Supporting Types

struct SharedContentLayout {
    let spatialParticipants: [ParticipantStateTracker.EnhancedParticipantState]
    let nearbyParticipants: [ParticipantStateTracker.EnhancedParticipantState]
    let remoteParticipants: [ParticipantStateTracker.EnhancedParticipantState]
    let contentAnchorPoints: [String: Pose3D]
    
    var totalParticipants: Int {
        return spatialParticipants.count + nearbyParticipants.count + remoteParticipants.count
    }
    
    var hasSpatialParticipants: Bool {
        return !spatialParticipants.isEmpty
    }
    
    func getOptimalContentPosition() -> Pose3D? {
        // Calculate optimal content position based on all participants
        guard !contentAnchorPoints.isEmpty else { return nil }
        
        let positions = contentAnchorPoints.values.map { $0.position }
        let avgX = positions.map { $0.x }.reduce(0, +) / Double(positions.count)
        let avgY = positions.map { $0.y }.reduce(0, +) / Double(positions.count)
        let avgZ = positions.map { $0.z }.reduce(0, +) / Double(positions.count)
        
        return Pose3D(position: Point3D(x: avgX, y: avgY, z: avgZ), rotation: Rotation3D.identity)
    }
}

#endif // os(visionOS)
