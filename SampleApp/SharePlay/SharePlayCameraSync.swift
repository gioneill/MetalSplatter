import Foundation
import simd
import Combine
import GroupActivities
import QuartzCore
import SwiftUI

class SharePlayCameraSync: ObservableObject {
    @Published var remoteViewports: [String: RemoteViewportState] = [:]
    @Published var syncedRotation: simd_quatf = simd_quatf(angle: 0, axis: [0,1,0])
    @Published var syncedPosition: SIMD3<Float> = SIMD3<Float>(0, 0, -1.5)
    
    private weak var sessionManager: SharePlaySessionManager?
    private var cancellables = Set<AnyCancellable>()
    
    struct RemoteViewportState {
        let position: SIMD3<Float>
        let rotation: simd_quatf
        let timestamp: TimeInterval
        let participantID: String
        let isNearby: Bool
    }
    
    init() {
        print("[SHAREPLAY] 📷 SharePlayCameraSync initialized")
        setupNotifications()
    }
    
    @MainActor
    func configure(with sessionManager: SharePlaySessionManager) {
        print("[SHAREPLAY] 🔧 Configuring SharePlayCameraSync with session manager")
        self.sessionManager = sessionManager
        sessionManager.addDelegate(self)
        
        sessionManager.$activeParticipants
            .sink { [weak self] participants in
                print("[SHAREPLAY] 👥 Camera sync updating remote participants: \(participants.count) total")
                self?.updateRemoteParticipants(participants)
            }
            .store(in: &cancellables)
        
        print("[SHAREPLAY] ✅ SharePlayCameraSync configuration complete")
    }
    
    private func setupNotifications() {
        print("[SHAREPLAY] 📡 Setting up camera sync notifications")
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("CameraDidUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userInfo = notification.userInfo,
               let position = userInfo["position"] as? SIMD3<Float>,
               let rotation = userInfo["rotation"] as? simd_quatf {
                print("[SHAREPLAY] 📷 Local camera update received: pos=\(position), rot=\(rotation)")
                Task { @MainActor in
                    self?.sendCameraUpdate(position: position, rotation: rotation)
                }
            } else {
                print("[SHAREPLAY] ⚠️ Invalid camera update notification received")
            }
        }
        print("[SHAREPLAY] ✅ Camera sync notifications setup complete")
    }
    
    private func updateRemoteParticipants(_ participants: Set<Participant>) {
        let currentParticipantIDs = Set(participants.map { $0.id.uuidString })
        let remoteParticipantIDs = Set(remoteViewports.keys)
        
        print("[SHAREPLAY] 🔄 Updating remote participants: current=\(currentParticipantIDs.count), cached=\(remoteParticipantIDs.count)")
        
        // Remove participants who left
        let leavingParticipants = remoteParticipantIDs.subtracting(currentParticipantIDs)
        for participantID in leavingParticipants {
            print("[SHAREPLAY] 👋 Removing viewport for participant: \(participantID)")
            remoteViewports.removeValue(forKey: participantID)
        }
        
        if !leavingParticipants.isEmpty {
            print("[SHAREPLAY] ✅ Removed \(leavingParticipants.count) participants from camera sync")
        }
    }
    
    @MainActor
    func sendCameraUpdate(position: SIMD3<Float>, rotation: simd_quatf) {
        guard let sessionManager = sessionManager else { 
            print("[SHAREPLAY] ❌ No session manager available for camera update")
            return 
        }
        
        print("[SHAREPLAY] 📤 Sending camera update via session manager")
        sessionManager.sendCameraUpdate(position: position, rotation: rotation)
    }
    
    func applySyncedTransforms(to baseTransform: simd_float4x4) -> simd_float4x4 {
        let rotationMatrix = simd_float4x4(syncedRotation)
        
        let translationMatrix = matrix4x4_translation(
            syncedPosition.x,
            syncedPosition.y,
            syncedPosition.z
        )
        
        return baseTransform * translationMatrix * rotationMatrix
    }
    
    func updateSyncedCamera(position: SIMD3<Float>, rotation: simd_quatf) {
        print("[SHAREPLAY] 🔄 Updating synced camera state: pos=\(position), rot=\(rotation)")
        self.syncedPosition = position
        self.syncedRotation = rotation
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
        print("[SHAREPLAY] 🗑️ SharePlayCameraSync deinit - cleaning up notifications")
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
            print("[SHAREPLAY] 📷 Received camera update from participant \(participant.id): pos=\(position), rot=\(rotation), nearby=\(isNearby)")
            
            remoteViewports[participant.id.uuidString] = RemoteViewportState(
                position: position,
                rotation: rotation,
                timestamp: timestamp,
                participantID: participant.id.uuidString,
                isNearby: isNearby
            )
            
            print("[SHAREPLAY] 💾 Stored viewport state for participant \(participant.id)")
            
            // Update synced camera state for all participants
            updateSyncedCamera(position: position, rotation: rotation)
            
            // Notify renderer of camera update
            print("[SHAREPLAY] 📡 Posting SharePlayCameraUpdate notification to renderer")
            NotificationCenter.default.post(
                name: NSNotification.Name("SharePlayCameraUpdate"),
                object: nil,
                userInfo: [
                    "position": position,
                    "rotation": rotation
                ]
            )
            
            print("[SHAREPLAY] ✅ Camera update processing complete for participant \(participant.id)")
        }
    }
    
    func didReceiveViewingStateUpdate(_ state: SyncMessage.ViewingState, from participant: Participant) async {
        // Handle viewing state updates if needed
    }
    
    func didReceiveParticipantPointer(position: SIMD3<Float>, participantID: String, from participant: Participant) async {
        // Handle pointer updates
        await MainActor.run {
            let isNearby = sessionManager?.nearbyParticipants.contains { $0.id == participant.id } ?? false
            print("[SHAREPLAY] 👆 Received participant pointer from \(participant.id): pos=\(position), participantID=\(participantID), nearby=\(isNearby)")
            
            NotificationCenter.default.post(
                name: NSNotification.Name("ParticipantPointerUpdate"),
                object: nil,
                userInfo: [
                    "position": position,
                    "participantID": participantID,
                    "isNearby": isNearby
                ]
            )
            
            print("[SHAREPLAY] ✅ Participant pointer notification posted")
        }
    }
    
    func didReceiveAnnotation(_ annotation: SyncMessage.AnnotationMessage, from participant: Participant) async {
        // Handle annotation updates
        await MainActor.run {
            let isNearby = sessionManager?.nearbyParticipants.contains { $0.id == participant.id } ?? false
            print("[SHAREPLAY] 💬 Received annotation from \(participant.id): '\(annotation.text)' at \(annotation.position), nearby=\(isNearby)")
            
            NotificationCenter.default.post(
                name: NSNotification.Name("AnnotationReceived"),
                object: nil,
                userInfo: [
                    "annotation": annotation,
                    "isNearby": isNearby
                ]
            )
            
            print("[SHAREPLAY] ✅ Annotation notification posted")
        }
    }
}

