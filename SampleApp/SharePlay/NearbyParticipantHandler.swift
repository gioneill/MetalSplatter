import Foundation
import GroupActivities
import ARKit
import RealityKit
import Combine
import OSLog
import QuartzCore
import Spatial
import MetalSplatter

#if os(visionOS)
@MainActor
class NearbyParticipantHandler: ObservableObject {
    private let logger = Logger(subsystem: "com.metalsplatter", category: "NearbyParticipants")
    
    @Published var nearbyParticipants: Set<Participant> = []
    @Published var remoteParticipants: Set<Participant> = []
    @Published var participantStates: [String: ParticipantSpatialState] = [:]
    @Published var sharedWorldAnchors: [String: WorldAnchor] = [:]
    
    private var sessionManager: SharePlaySessionManager?
    private var participantStateTracker: ParticipantStateTracker?
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
        logger.info("NearbyParticipantHandler initializing...")
        print("[SHAREPLAY] 👥 NearbyParticipantHandler initializing...")
        participantStateTracker = ParticipantStateTracker()
        setupARKitSession()
    }
    
    func configure(with sessionManager: SharePlaySessionManager) {
        print("[SHAREPLAY] 🔧 Configuring NearbyParticipantHandler with session manager")
        self.sessionManager = sessionManager
        
        // Configure participant state tracker
        participantStateTracker?.configure(with: sessionManager)
        
        sessionManager.$nearbyParticipants
            .sink { [weak self] participants in
                print("[SHAREPLAY] 🏠 Nearby participants updated: \(participants.count) participants")
                for participant in participants {
                    print("[SHAREPLAY]   👤 Nearby: \(participant.id)")
                }
                self?.nearbyParticipants = participants
                self?.updateParticipantStates()
            }
            .store(in: &cancellables)
        
        sessionManager.$remoteParticipants
            .sink { [weak self] participants in
                print("[SHAREPLAY] 📹 Remote participants updated: \(participants.count) participants")
                for participant in participants {
                    print("[SHAREPLAY]   👤 Remote: \(participant.id)")
                }
                self?.remoteParticipants = participants
                self?.updateParticipantStates()
            }
            .store(in: &cancellables)
        
        // Listen for participant state updates
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ParticipantStatesUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            self?.handleParticipantStateUpdate(notification)
        }
        
        print("[SHAREPLAY] ✅ NearbyParticipantHandler configuration complete")
    }
    
    private func setupARKitSession() {
        #if os(visionOS)
        print("[SHAREPLAY] 🌐 Setting up ARKit session for world anchors...")
        Task {
            arSession = ARKitSession()
            worldTrackingProvider = WorldTrackingProvider()
            
            guard let arSession = arSession,
                  let worldTrackingProvider = worldTrackingProvider else {
                print("[SHAREPLAY] ❌ Failed to create ARKit session or world tracking provider")
                logger.error("Failed to create ARKit session or world tracking provider")
                return
            }
            
            // Add provider support guards
            guard WorldTrackingProvider.isSupported else {
                print("[SHAREPLAY] ❌ WorldTrackingProvider not supported")
                logger.error("WorldTrackingProvider not supported")
                return
            }
            
            do {
                print("[SHAREPLAY] 🚀 Starting ARKit session with world tracking...")
                
                await withTaskGroup(of: Void.self) { group in
                    // Start ARKit session
                    group.addTask {
                        do {
                            try await arSession.run([worldTrackingProvider])
                            print("[SHAREPLAY] ✅ ARKit session started successfully")
                        } catch {
                            print("[SHAREPLAY] ❌ ARKit session failed: \(error)")
                        }
                    }
                    
                    // Start world anchor observation
                    group.addTask {
                        await self.observeWorldAnchors()
                    }
                }
            }
        }
        #else
        print("[SHAREPLAY] ⚠️ ARKit session setup skipped - not on visionOS")
        #endif
    }
    
    #if os(visionOS)
    private func observeWorldAnchors() async {
        guard let worldTrackingProvider = worldTrackingProvider else { 
            print("[SHAREPLAY] ❌ No world tracking provider available for anchor observation")
            return 
        }
        
        print("[SHAREPLAY] 👀 Starting to observe world anchor updates...")
        
        for await anchorUpdate in worldTrackingProvider.anchorUpdates {
            let worldAnchor = anchorUpdate.anchor
            print("[SHAREPLAY] ⚓ World anchor update: \(anchorUpdate.event) for \(worldAnchor.id)")
            
            switch anchorUpdate.event {
            case .added:
                if worldAnchor.isSharedWithNearbyParticipants {
                    print("[SHAREPLAY] ➕ Shared world anchor added: \(worldAnchor.id)")
                    await handleSharedWorldAnchor(worldAnchor, event: .added)
                } else {
                    print("[SHAREPLAY] ℹ️ Non-shared world anchor added (ignoring): \(worldAnchor.id)")
                }
            case .updated:
                if worldAnchor.isSharedWithNearbyParticipants {
                    print("[SHAREPLAY] 🔄 Shared world anchor updated: \(worldAnchor.id)")
                    await handleSharedWorldAnchor(worldAnchor, event: .updated)
                }
            case .removed:
                print("[SHAREPLAY] ➖ World anchor removed: \(worldAnchor.id)")
                await handleSharedWorldAnchor(worldAnchor, event: .removed)
            }
        }
        
        print("[SHAREPLAY] ⚠️ World anchor observation loop ended - this should not happen during normal operation")
    }
    
    private func handleSharedWorldAnchor(_ anchor: WorldAnchor, event: AnchorUpdate<WorldAnchor>.Event) async {
        let anchorID = anchor.id.uuidString
        
        switch event {
        case .added, .updated:
            sharedWorldAnchors[anchorID] = anchor
            print("[SHAREPLAY] ⚓ Shared world anchor \(event == .added ? "added" : "updated"): \(anchorID)")
            logger.info("Shared world anchor \(event == .added ? "added" : "updated"): \(anchorID)")
        case .removed:
            sharedWorldAnchors.removeValue(forKey: anchorID)
            print("[SHAREPLAY] 🔥 Shared world anchor removed: \(anchorID)")
            logger.info("Shared world anchor removed: \(anchorID)")
        }
        
        // Notify other components about world anchor changes
        print("[SHAREPLAY] 📡 Posting SharedWorldAnchorUpdate notification")
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
        guard arSession != nil else {
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
        print("[SHAREPLAY] 🔄 Updating participant states...")
        
        // Update spatial states for all participants
        let allParticipants = nearbyParticipants.union(remoteParticipants)
        let beforeStatesCount = participantStates.count
        
        for participant in allParticipants {
            let isNearby = nearbyParticipants.contains(participant)
            
            // Get actual spatial data from enhanced participant state if available
            let enhancedState = participantStateTracker?.getParticipantState(for: participant.id.uuidString)
            let position = enhancedState?.pose.position ?? Point3D.zero
            let rotation = enhancedState?.pose.rotation ?? Rotation3D.identity
            
            let state = ParticipantSpatialState(
                participant: participant,
                isNearby: isNearby,
                position: SIMD3<Float>(Float(position.x), Float(position.y), Float(position.z)),
                rotation: simd_quatf(rotation),
                lastUpdateTime: CACurrentMediaTime(),
                seatPose: enhancedState?.seatPose.map { convertPose3DToFloat4x4($0) },
                participantPose: enhancedState.map { convertPose3DToFloat4x4($0.pose) }
            )
            
            participantStates[participant.id.uuidString] = state
            print("[SHAREPLAY] 💾 Updated state for participant \(participant.id) (\(isNearby ? "nearby" : "remote"))")
        }
        
        // Remove states for participants who left
        let currentParticipantIDs = Set(allParticipants.map { $0.id.uuidString })
        var removedCount = 0
        for participantID in participantStates.keys {
            if !currentParticipantIDs.contains(participantID) {
                participantStates.removeValue(forKey: participantID)
                print("[SHAREPLAY] 🗟️ Removed state for departed participant: \(participantID)")
                removedCount += 1
            }
        }
        
        let afterStatesCount = participantStates.count
        print("[SHAREPLAY] ✅ Participant states updated - Total: \(afterStatesCount) (was \(beforeStatesCount)), Nearby: \(self.nearbyParticipants.count), Remote: \(self.remoteParticipants.count), Removed: \(removedCount)")
        logger.info("Updated participant states - Nearby: \(self.nearbyParticipants.count), Remote: \(self.remoteParticipants.count)")
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
        let isNearby = participantStates[participantID]?.isNearby ?? false
        print("[SHAREPLAY] 👆 Participant \(participantID) (\(isNearby ? "nearby" : "remote")) performed gesture: \(gestureType.rawValue) at \(position)")
        logger.info("Participant \(participantID) performed gesture: \(gestureType.rawValue) at \(position)")
        
        // Send gesture information to other participants
        if let sessionManager = sessionManager {
            print("[SHAREPLAY] 📤 Sending gesture as participant pointer to other participants")
            Task {
                // This would be implemented as part of the gesture synchronization system
                // For now, we'll use the participant pointer message
                sessionManager.sendParticipantPointer(position: position, participantID: participantID)
            }
        } else {
            print("[SHAREPLAY] ⚠️ No session manager available to send gesture")
        }
        
        // Post local notification for UI updates
        print("[SHAREPLAY] 📡 Posting ParticipantGesture notification for local UI")
        NotificationCenter.default.post(
            name: NSNotification.Name("ParticipantGesture"),
            object: nil,
            userInfo: [
                "participantID": participantID,
                "gestureType": gestureType,
                "position": position,
                "isNearby": isNearby
            ]
        )
    }
    
    // MARK: - Enhanced Participant State Handling
    
    private func handleParticipantStateUpdate(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let enhancedStates = userInfo["participantStates"] as? [String: ParticipantStateTracker.EnhancedParticipantState],
              let spatialParticipants = userInfo["spatialParticipants"] as? Set<String> else {
            return
        }
        
        print("[SHAREPLAY] 🔄 Handling participant state update: \(enhancedStates.count) participants, \(spatialParticipants.count) spatial")
        
        // Update our legacy participant states for backward compatibility
        updateLegacyParticipantStates(from: enhancedStates)
        
        // Handle spatial participant positioning
        handleSpatialParticipantPositioning(enhancedStates: enhancedStates, spatialParticipants: spatialParticipants)
    }
    
    private func updateLegacyParticipantStates(from enhancedStates: [String: ParticipantStateTracker.EnhancedParticipantState]) {
        var newLegacyStates: [String: ParticipantSpatialState] = [:]
        
        for (participantID, enhancedState) in enhancedStates {
            let position = SIMD3<Float>(
                Float(enhancedState.pose.position.x),
                Float(enhancedState.pose.position.y),
                Float(enhancedState.pose.position.z)
            )
            
            // Convert Pose3D to simd_float4x4 for legacy compatibility
            let pose4x4 = convertPose3DToFloat4x4(enhancedState.pose)
            let seatPose4x4 = enhancedState.seatPose.map { convertPose3DToFloat4x4($0) }
            
            let legacyState = ParticipantSpatialState(
                participant: enhancedState.participant,
                isNearby: enhancedState.isNearby,
                position: position,
                rotation: simd_quatf(enhancedState.pose.rotation),
                lastUpdateTime: enhancedState.lastUpdateTime,
                seatPose: seatPose4x4,
                participantPose: pose4x4
            )
            
            newLegacyStates[participantID] = legacyState
        }
        
        participantStates = newLegacyStates
    }
    
    private func handleSpatialParticipantPositioning(enhancedStates: [String: ParticipantStateTracker.EnhancedParticipantState], spatialParticipants: Set<String>) {
        // Position content relative to spatial participants
        for participantID in spatialParticipants {
            guard let state = enhancedStates[participantID] else { continue }
            
            print("[SHAREPLAY] ✨ Positioning content for spatial participant \(participantID)")
            logger.info("Positioning content for spatial participant \(participantID) at pose: \(state.pose)")
            
            // Post notification for content positioning
            NotificationCenter.default.post(
                name: NSNotification.Name("PositionContentForSpatialParticipant"),
                object: nil,
                userInfo: [
                    "participantID": participantID,
                    "pose": state.pose,
                    "isNearby": state.isNearby,
                    "seatPose": state.seatPose as Any
                ]
            )
        }
    }
    
    // MARK: - Enhanced Public Interface
    
    func getEnhancedParticipantState(for participantID: String) -> ParticipantStateTracker.EnhancedParticipantState? {
        return participantStateTracker?.getParticipantState(for: participantID)
    }
    
    func getSpatialParticipants() -> [ParticipantStateTracker.EnhancedParticipantState] {
        return participantStateTracker?.getSpatialParticipants() ?? []
    }
    
    func getSharedContentLayout() -> SharedContentLayout? {
        return participantStateTracker?.createSharedContentLayout()
    }
    
    func positionContentRelativeToParticipant(_ participantID: String, offset: SIMD3<Float> = SIMD3<Float>(0, 0, 0)) -> simd_float4x4? {
        return participantStateTracker?.positionContentRelativeToParticipant(participantID, offset: offset)
    }
    
    func getOptimalContentPosition() -> simd_float4x4? {
        guard let layout = getSharedContentLayout(),
              let optimalPose = layout.getOptimalContentPosition() else {
            return nil
        }
        
        return convertPose3DToFloat4x4(optimalPose)
    }
    
    func getParticipantVisualizationData() -> [(id: String, position: SIMD3<Float>, isNearby: Bool, isSpatial: Bool)] {
        return participantStateTracker?.getParticipantVisualizationData() ?? []
    }
    
    // MARK: - Utility Methods
    
    private func convertPose3DToFloat4x4(_ pose: Pose3D) -> simd_float4x4 {
        let affineTransform = AffineTransform3D(pose: pose)
        let matrix = affineTransform.matrix
        return simd_float4x4(
            SIMD4<Float>(Float(matrix.columns.0.x), Float(matrix.columns.0.y), Float(matrix.columns.0.z), 0),
            SIMD4<Float>(Float(matrix.columns.1.x), Float(matrix.columns.1.y), Float(matrix.columns.1.z), 0),
            SIMD4<Float>(Float(matrix.columns.2.x), Float(matrix.columns.2.y), Float(matrix.columns.2.z), 0),
            SIMD4<Float>(Float(matrix.columns.3.x), Float(matrix.columns.3.y), Float(matrix.columns.3.z), 1)
        )
    }
    
    private func convertFloat4x4ToPose3D(_ matrix: simd_float4x4) -> Pose3D {
        // Extract translation from the last column
        let translation = Vector3D(
            x: Double(matrix.columns.3.x),
            y: Double(matrix.columns.3.y),
            z: Double(matrix.columns.3.z)
        )
        
        // Extract rotation matrix (upper 3x3)
        let rotationMatrix = simd_float3x3(
            simd_float3(matrix.columns.0.x, matrix.columns.0.y, matrix.columns.0.z),
            simd_float3(matrix.columns.1.x, matrix.columns.1.y, matrix.columns.1.z),
            simd_float3(matrix.columns.2.x, matrix.columns.2.y, matrix.columns.2.z)
        )
        
        // Convert to quaternion (simplified - assumes no scaling)
        let quat = simd_quatf(rotationMatrix)
        let rotation = Rotation3D(quaternion: simd_quatd(
            ix: Double(quat.imag.x),
            iy: Double(quat.imag.y),
            iz: Double(quat.imag.z),
            r: Double(quat.real)
        ))
        
        return Pose3D(position: Point3D(translation), rotation: rotation)
    }
    
    deinit {
        print("[SHAREPLAY] 🗑️ NearbyParticipantHandler deinit - cleaning up")
        
        // Cancel all Combine subscriptions
        cancellables.removeAll()
        
        // Remove notification observers
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("ParticipantStatesUpdated"), object: nil)
        
        logger.info("NearbyParticipantHandler deinitialized")
    }
}
#endif // os(visionOS)

enum ParticipantGesture: String, CaseIterable {
    case point = "point"
    case grab = "grab"
    case pinch = "pinch"
    case tap = "tap"
}
