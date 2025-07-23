import Foundation
import simd
import Combine
import GroupActivities
import QuartzCore

class SharePlayCameraSync: ObservableObject {
    @Published var remoteViewports: [String: RemoteViewportState] = [:]
    @Published var syncedRotation: Angle = .zero
    @Published var syncedPosition: SIMD3<Float> = SIMD3<Float>(0, 0, -1.5)
    
    private var sessionManager: SharePlaySessionManager?
    private var cancellables = Set<AnyCancellable>()
    
    private var lastSyncTime: TimeInterval = 0
    private let syncInterval: TimeInterval = 1.0 / 30.0 // 30 FPS
    
    struct RemoteViewportState {
        let position: SIMD3<Float>
        let rotation: simd_quatf
        let timestamp: TimeInterval
        let participantID: String
        let isNearby: Bool
    }
    
    init() {
        setupNotifications()
    }
    
    func configure(with sessionManager: SharePlaySessionManager) {
        self.sessionManager = sessionManager
        sessionManager.delegate = self
        
        sessionManager.$activeParticipants
            .sink { [weak self] participants in
                self?.updateRemoteParticipants(participants)
            }
            .store(in: &cancellables)
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CameraDidUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userInfo = notification.userInfo,
               let position = userInfo["position"] as? SIMD3<Float>,
               let rotation = userInfo["rotation"] as? simd_quatf {
                self?.sendCameraUpdate(position: position, rotation: rotation)
            }
        }
    }
    
    private func updateRemoteParticipants(_ participants: Set<Participant>) {
        let currentParticipantIDs = Set(participants.map { $0.id })
        let remoteParticipantIDs = Set(remoteViewports.keys)
        
        // Remove participants who left
        for participantID in remoteParticipantIDs.subtracting(currentParticipantIDs) {
            remoteViewports.removeValue(forKey: participantID)
        }
    }
    
    func sendCameraUpdate(position: SIMD3<Float>, rotation: simd_quatf) {
        guard let sessionManager = sessionManager else { return }
        
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastSyncTime >= syncInterval else { return }
        lastSyncTime = currentTime
        
        sessionManager.sendCameraUpdate(position: position, rotation: rotation)
    }
    
    func applySyncedTransforms(to baseTransform: simd_float4x4) -> simd_float4x4 {
        let rotationMatrix = matrix4x4_rotation(
            radians: Float(syncedRotation.radians),
            axis: SIMD3<Float>(0, 1, 0)
        )
        
        let translationMatrix = matrix4x4_translation(
            syncedPosition.x,
            syncedPosition.y,
            syncedPosition.z
        )
        
        return baseTransform * translationMatrix * rotationMatrix
    }
    
    func getRemoteParticipantTransforms() -> [(participantID: String, transform: simd_float4x4, isNearby: Bool)] {
        return remoteViewports.compactMap { (participantID, state) in
            let rotationMatrix = simd_float4x4(state.rotation)
            let translationMatrix = matrix4x4_translation(
                state.position.x,
                state.position.y,
                state.position.z
            )
            let transform = translationMatrix * rotationMatrix
            
            return (participantID, transform, state.isNearby)
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

extension SharePlayCameraSync: SharePlaySessionDelegate {
    func participantsDidUpdate(nearby: Set<Participant>, remote: Set<Participant>) async {
        // Already handled in the publisher subscription
    }
    
    func didReceiveModelSelection(_ modelIdentifier: ModelIdentifier, from participant: Participant) async {
        // Will be handled in model sync
    }
    
    func didReceiveCameraUpdate(position: SIMD3<Float>, rotation: simd_quatf, timestamp: TimeInterval, from participant: Participant) async {
        await MainActor.run {
            let isNearby = sessionManager?.nearbyParticipants.contains { $0.id == participant.id } ?? false
            
            remoteViewports[participant.id] = RemoteViewportState(
                position: position,
                rotation: rotation,
                timestamp: timestamp,
                participantID: participant.id,
                isNearby: isNearby
            )
        }
    }
    
    func didReceiveViewingStateUpdate(_ state: SyncMessage.ViewingState, from participant: Participant) async {
        // Handle viewing state updates if needed
    }
    
    func didReceiveParticipantPointer(position: SIMD3<Float>, participantID: String, from participant: Participant) async {
        // Handle pointer updates
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("ParticipantPointerUpdate"),
                object: nil,
                userInfo: [
                    "position": position,
                    "participantID": participantID,
                    "isNearby": sessionManager?.nearbyParticipants.contains { $0.id == participant.id } ?? false
                ]
            )
        }
    }
    
    func didReceiveAnnotation(_ annotation: SyncMessage.AnnotationMessage, from participant: Participant) async {
        // Handle annotation updates
        await MainActor.run {
            NotificationCenter.default.post(
                name: NSNotification.Name("AnnotationReceived"),
                object: nil,
                userInfo: [
                    "annotation": annotation,
                    "isNearby": sessionManager?.nearbyParticipants.contains { $0.id == participant.id } ?? false
                ]
            )
        }
    }
}

// Helper functions for matrix operations
func matrix4x4_rotation(radians: Float, axis: SIMD3<Float>) -> simd_float4x4 {
    let unitAxis = normalize(axis)
    let ct = cosf(radians)
    let st = sinf(radians)
    let ci = 1 - ct
    let x = unitAxis.x, y = unitAxis.y, z = unitAxis.z
    
    return simd_float4x4(
        SIMD4<Float>(    ct + x * x * ci, y * x * ci + z * st, z * x * ci - y * st, 0),
        SIMD4<Float>(x * y * ci - z * st,     ct + y * y * ci, z * y * ci + x * st, 0),
        SIMD4<Float>(x * z * ci + y * st, y * z * ci - x * st,     ct + z * z * ci, 0),
        SIMD4<Float>(                  0,                   0,                   0, 1)
    )
}

func matrix4x4_translation(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    return simd_float4x4(
        SIMD4<Float>(1, 0, 0, 0),
        SIMD4<Float>(0, 1, 0, 0),
        SIMD4<Float>(0, 0, 1, 0),
        SIMD4<Float>(x, y, z, 1)
    )
}