import Foundation
import GroupActivities
import Combine
import OSLog
import simd
import QuartzCore
#if os(visionOS)
import Spatial
import SwiftUI
#endif

import Observation

@MainActor
protocol SharePlaySessionDelegate: AnyObject {
    func participantsDidUpdate(nearby: Set<Participant>, remote: Set<Participant>) async
    func didReceiveModelSelection(_ modelIdentifier: ModelIdentifier, from sender: Participant) async
    func didReceiveCameraUpdate(position: SIMD3<Float>, rotation: simd_quatf, timestamp: TimeInterval, from sender: Participant) async
    func didReceiveViewingStateUpdate(_ state: SyncMessage.ViewingState, from sender: Participant) async
    func didReceiveParticipantPointer(position: SIMD3<Float>, participantID: String, from sender: Participant) async
    func didReceiveAnnotation(_ annotation: SyncMessage.AnnotationMessage, from sender: Participant) async
    func didReceiveImmersiveSceneUpdate(isActive: Bool, modelIdentifier: ModelIdentifier?, from sender: Participant) async
    func didReceiveOriginUpdate(position: SIMD3<Float>, rotation: simd_quatf, scale: Float, from sender: Participant) async
}

@Observable
class SharePlaySessionManager {
    private let logger = Logger(subsystem: "com.metalsplatter", category: "SharePlay")
    
    var isSharePlayActive = false
    var activeParticipants: Set<Participant> = []
    var nearbyParticipants: Set<Participant> = []
    var remoteParticipants: Set<Participant> = []
    var sessionState: GroupSession<SplatViewingActivity>.State = .waiting
    
    private var groupSession: GroupSession<SplatViewingActivity>?
    private var messenger: GroupSessionMessenger?
    private var cancellables = Set<AnyCancellable>()
    
    #if os(visionOS)
    private var spatialTemplateManager: SpatialTemplateManager?
    #endif
    
    private var lastCameraUpdateTime: TimeInterval = 0
    private let cameraUpdateThrottle: TimeInterval = 1.0 / 30.0 // 30 FPS max
    
    private let delegates = NSHashTable<AnyObject>.weakObjects()

    func addDelegate(_ delegate: SharePlaySessionDelegate) {
        delegates.add(delegate)
    }

    func removeDelegate(_ delegate: SharePlaySessionDelegate) {
        delegates.remove(delegate)
    }

    private func notify(_ block: @escaping (SharePlaySessionDelegate) async -> Void) async {
        for case let d as SharePlaySessionDelegate in delegates.allObjects {
            await block(d)
        }
    }
    
    init() {
        setupGroupSessionListener()
        
        #if os(visionOS)
        spatialTemplateManager = SpatialTemplateManager()
        #endif
    }
    
    private func setupGroupSessionListener() {
        Task {
            for await session in SplatViewingActivity.sessions() {
                await configureGroupSession(session)
            }
        }
    }
    
    func startActivity(with modelIdentifier: ModelIdentifier?) async {
        print("[SHAREPLAY] 🚀 Starting SharePlay activity (visionOS 26 mode)...")
        print("[SHAREPLAY] 📋 Model identifier: \(String(describing: modelIdentifier))")
        print("[SHAREPLAY] 📊 Current state - Active: \(isSharePlayActive), Participants: \(activeParticipants.count)")
        logger.info("visionOS 26 - Starting SharePlay activity with model: \(modelIdentifier?.displayName ?? "none")")
        
        let activity = SplatViewingActivity(modelIdentifier: modelIdentifier)
        print("[SHAREPLAY] 🎯 Created SplatViewingActivity with identifier: \(SplatViewingActivity.activityIdentifier)")
        
        do {
            print("[SHAREPLAY] 🔄 Activating SharePlay activity (visionOS 26 - no eligibility check)...")
            // visionOS 26: Always call activate() - presents Share Window menu if no active call
            _ = try await activity.activate()
            print("[SHAREPLAY] ✅ SharePlay activity activated successfully (Share Window menu shown if needed)!")
            logger.info("visionOS 26 - SharePlay activity activated successfully")
        } catch {
            print("[SHAREPLAY] ❌ Failed to activate SharePlay activity: \(error)")
            print("[SHAREPLAY] 🔍 Error details: \(error.localizedDescription)")
            logger.error("visionOS 26 - Failed to activate SharePlay activity: \(error)")
        }
    }
    
    private func configureGroupSession(_ session: GroupSession<SplatViewingActivity>) async {
        print("[SHAREPLAY] 🔧 Configuring group session...")
        print("[SHAREPLAY] 👥 Session has \(session.activeParticipants.count) participants")
        print("[SHAREPLAY] 🆔 Session ID: \(session.id)")
        print("[SHAREPLAY] 📱 Local participant: \(session.localParticipant.id)")
        logger.info("Configuring group session with \(session.activeParticipants.count) participants")
        
        groupSession = session
        messenger = GroupSessionMessenger(session: session)
        print("[SHAREPLAY] 📡 Created GroupSessionMessenger")
        
        session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                print("[SHAREPLAY] 🔄 Session state changed to: \(String(describing: state))")
                self?.sessionState = state
                self?.isSharePlayActive = (state == .joined)
                print("[SHAREPLAY] 📊 SharePlay now active: \(self?.isSharePlayActive ?? false)")
                self?.logger.info("Session state changed to: \(String(describing: state))")
            }
            .store(in: &cancellables)
        
        session.$activeParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] participants in
                print("[SHAREPLAY] 👥 Active participants changed: \(participants.count) total")
                for participant in participants {
                    print("[SHAREPLAY] 🧑 Participant: \(participant.id) (nearby: \(participant.isNearbyWithLocalParticipant))")
                }
                Task {
                    await self?.updateParticipants(participants)
                }
            }
            .store(in: &cancellables)
        
        setupMessageHandling()
        
        print("[SHAREPLAY] 🔗 Joining session...")
        session.join()
        print("[SHAREPLAY] ✅ Session join requested")
        
        // Enable group immersive space for visionOS
        #if os(visionOS)
        print("[SHAREPLAY] 🌐 Configuring visionOS system coordinator...")
        if let coordinator = await session.systemCoordinator {
            var configuration = SystemCoordinator.Configuration()
            configuration.supportsGroupImmersiveSpace = true
            coordinator.configuration = configuration
            print("[SHAREPLAY] ✅ Group immersive space enabled")
            
            // Configure spatial template manager
            spatialTemplateManager?.configure(with: self)
            setupSystemCoordinatorMonitoring(coordinator)
        } else {
            print("[SHAREPLAY] ⚠️ No system coordinator available")
        }
        #endif
    }
    
    private func updateParticipants(_ participants: Set<Participant>) async {
        print("[SHAREPLAY] 🔄 Updating participants (visionOS 26 mode)...")
        activeParticipants = participants
        
        // visionOS 26: Enhanced nearby vs remote participant distinction
        nearbyParticipants = Set(participants.filter { participant in
            participant.isNearbyWithLocalParticipant &&
            participant.id != groupSession?.localParticipant.id
        })
        
        remoteParticipants = Set(participants.filter { participant in
            !participant.isNearbyWithLocalParticipant &&
            participant.id != groupSession?.localParticipant.id
        })
        
        print("[SHAREPLAY] 📊 Participant breakdown (visionOS 26):")
        print("[SHAREPLAY]   📱 Total: \(participants.count)")
        print("[SHAREPLAY]   🏠 Nearby (via passthrough): \(self.nearbyParticipants.count)")
        print("[SHAREPLAY]   📹 Remote (spatial Personas): \(self.remoteParticipants.count)")
        
        for participant in nearbyParticipants {
            print("[SHAREPLAY]   🏠 Nearby participant: \(participant.id) (physical presence)")
        }
        for participant in remoteParticipants {
            print("[SHAREPLAY]   📹 Remote participant: \(participant.id) (spatial Persona)")
        }
        
        logger.info("visionOS 26 - Updated participants - Total: \(participants.count), Nearby: \(self.nearbyParticipants.count), Remote: \(self.remoteParticipants.count)")
        
        print("[SHAREPLAY] 📢 Notifying delegates of participant update...")
        await notify { await $0.participantsDidUpdate(nearby: self.nearbyParticipants, remote: self.remoteParticipants) }
    }
    
    private func setupMessageHandling() {
        guard let messenger = messenger else { 
            print("[SHAREPLAY] ❌ No messenger available for message handling")
            return 
        }
        
        print("[SHAREPLAY] 📡 Setting up message handling...")
        
        Task {
            print("[SHAREPLAY] 🔄 Starting to listen for messages...")
            for await (data, context) in messenger.messages(of: Data.self) {
                do {
                    let message = try JSONDecoder().decode(SyncMessage.self, from: data)
                    let participant = context.source
                    print("[SHAREPLAY] 📨 Received message from participant \\(participant.id): \\(String(describing: message))")
                    await handleSyncMessage(message, from: participant)
                } catch {
                    print("[SHAREPLAY] ❌ Failed to decode message: \\(error)")
                    logger.error("Failed to decode message: \\(error)")
                }
            }
            print("[SHAREPLAY] ⚠️ Message handling loop ended - this should not happen during normal operation")
        }
    }
    
    private func handleSyncMessage(_ message: SyncMessage, from sender: Participant) async {
        print("[SHAREPLAY] 🔍 Processing message from participant \(sender.id): \(String(describing: message))")
        logger.debug("Received message from \(sender.id): \(String(describing: message))")
        
        switch message {
        case .modelSelection(let modelIdentifier):
            print("[SHAREPLAY] 🎯 Handling model selection: \(modelIdentifier.displayName)")
            await notify { await $0.didReceiveModelSelection(modelIdentifier, from: sender) }
            
        case .cameraUpdate(let position, let rotation, let timestamp):
            print("[SHAREPLAY] 📷 Handling camera update from \(sender.id): pos=\(position), rot=\(rotation), timestamp=\(timestamp)")
            await notify {
                await $0.didReceiveCameraUpdate(
                    position: position,
                    rotation: rotation,
                    timestamp: timestamp,
                    from: sender
                )
            }
            
        case .viewingStateUpdate(let state):
            print("[SHAREPLAY] 👁️ Handling viewing state update from \(sender.id): \(String(describing: state))")
            await notify { await $0.didReceiveViewingStateUpdate(state, from: sender) }
            
        case .participantPointer(let position, let participantID):
            print("[SHAREPLAY] 👆 Handling participant pointer from \(sender.id): pos=\(position), participantID=\(participantID)")
            await notify { await $0.didReceiveParticipantPointer(position: position, participantID: participantID, from: sender) }
            
        case .annotation(let annotation):
            print("[SHAREPLAY] 💬 Handling annotation from \(sender.id): \(annotation.text)")
            await notify { await $0.didReceiveAnnotation(annotation, from: sender) }
            
        case .immersiveSceneUpdate(let isActive, let modelIdentifier):
            print("[SHAREPLAY] 🌐 Handling immersive scene update from \(sender.id): isActive=\(isActive)")
            await notify { 
                await $0.didReceiveImmersiveSceneUpdate(
                    isActive: isActive, 
                    modelIdentifier: modelIdentifier,
                    from: sender
                )
            }
            
        case .originUpdate(let position, let rotation, let scale):
            print("[SHAREPLAY] 🎯 Handling origin update from \(sender.id): pos=\(position), rot=\(rotation), scale=\(scale)")
            await notify {
                await $0.didReceiveOriginUpdate(
                    position: position,
                    rotation: rotation,
                    scale: scale,
                    from: sender
                )
            }
        }
        
        print("[SHAREPLAY] ✅ Message processing complete for participant \(sender.id)")
    }
    
    func sendModelSelection(_ modelIdentifier: ModelIdentifier) {
        guard let messenger = messenger else { 
            print("[SHAREPLAY] ❌ No messenger available to send model selection")
            return 
        }
        
        print("[SHAREPLAY] 📤 Sending model selection: \(modelIdentifier.displayName)")
        
        Task {
            do {
                let message = SyncMessage.modelSelection(modelIdentifier)
                let data = try JSONEncoder().encode(message)
                try await messenger.send(data)
                print("[SHAREPLAY] ✅ Model selection sent successfully: \(modelIdentifier.description)")
                logger.debug("Sent model selection: \(modelIdentifier.description)")
            } catch {
                print("[SHAREPLAY] ❌ Failed to send model selection: \(error)")
                logger.error("Failed to send model selection: \(error)")
            }
        }
    }
    
    func sendCameraUpdate(position: SIMD3<Float>, rotation: simd_quatf) {
        guard let messenger = messenger else { 
            print("[SHAREPLAY] ❌ No messenger available to send camera update")
            return 
        }
        
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastCameraUpdateTime >= cameraUpdateThrottle else { 
            // Throttled - don't spam logs
            return 
        }
        lastCameraUpdateTime = currentTime
        
        print("[SHAREPLAY] 📤 Sending camera update: pos=\(position), rot=\(rotation)")
        
        Task {
            do {
                let message = SyncMessage.cameraUpdate(
                    position: position,
                    rotation: rotation,
                    timestamp: currentTime
                )
                let data = try JSONEncoder().encode(message)
                try await messenger.send(data)
                
                print("[SHAREPLAY] ✅ Camera update sent successfully")
                logger.debug("Sent camera update")
            } catch {
                print("[SHAREPLAY] ❌ Failed to send camera update: \(error)")
                logger.error("Failed to send camera update: \(error)")
            }
        }
    }
    
    func sendViewingStateUpdate(_ state: SyncMessage.ViewingState) {
        guard let messenger = messenger else { 
            print("[SHAREPLAY] ❌ No messenger available to send viewing state update")
            return 
        }
        
        print("[SHAREPLAY] 📤 Sending viewing state update: \(String(describing: state))")
        
        Task {
            do {
                let message = SyncMessage.viewingStateUpdate(state)
                let data = try JSONEncoder().encode(message)
                try await messenger.send(data)
                print("[SHAREPLAY] ✅ Viewing state update sent successfully")
                logger.debug("Sent viewing state update")
            } catch {
                print("[SHAREPLAY] ❌ Failed to send viewing state update: \(error)")
                logger.error("Failed to send viewing state update: \(error)")
            }
        }
    }
    
    func sendParticipantPointer(position: SIMD3<Float>, participantID: String) {
        guard let messenger = messenger else { 
            print("[SHAREPLAY] ❌ No messenger available to send participant pointer")
            return 
        }
        
        print("[SHAREPLAY] 📤 Sending participant pointer: pos=\(position), participantID=\(participantID)")
        
        Task {
            do {
                let message = SyncMessage.participantPointer(position: position, participantID: participantID)
                let data = try JSONEncoder().encode(message)
                try await messenger.send(data)
                print("[SHAREPLAY] ✅ Participant pointer sent successfully")
                logger.info("Sent participant pointer update")
            } catch {
                print("[SHAREPLAY] ❌ Failed to send participant pointer: \(error)")
                logger.error("Failed to send participant pointer: \(error)")
            }
        }
    }
    
    func sendAnnotation(_ annotation: SyncMessage.AnnotationMessage) {
        guard let messenger = messenger else { 
            print("[SHAREPLAY] ❌ No messenger available to send annotation")
            return 
        }
        
        print("[SHAREPLAY] 📤 Sending annotation: '\(annotation.text)' from \(annotation.participantID)")
        
        Task {
            do {
                let message = SyncMessage.annotation(annotation)
                let data = try JSONEncoder().encode(message)
                try await messenger.send(data)
                print("[SHAREPLAY] ✅ Annotation sent successfully")
                logger.info("Sent annotation")
            } catch {
                print("[SHAREPLAY] ❌ Failed to send annotation: \(error)")
                logger.error("Failed to send annotation: \(error)")
            }
        }
    }
    
    func sendImmersiveSceneUpdate(isActive: Bool, modelIdentifier: ModelIdentifier?) {
        guard let messenger = messenger else {
            print("[SHAREPLAY] ❌ No messenger available to send immersive scene update")
            return
        }
        
        print("[SHAREPLAY] 📤 Sending immersive scene update: isActive=\(isActive), model=\(modelIdentifier?.displayName ?? "none")")
        
        Task {
            do {
                let message = SyncMessage.immersiveSceneUpdate(isActive: isActive, modelIdentifier: modelIdentifier)
                let data = try JSONEncoder().encode(message)
                try await messenger.send(data)
                print("[SHAREPLAY] ✅ Immersive scene update sent successfully")
                logger.debug("Sent immersive scene update")
            } catch {
                print("[SHAREPLAY] ❌ Failed to send immersive scene update: \(error)")
                logger.error("Failed to send immersive scene update: \(error)")
            }
        }
    }
    
    func sendOriginUpdate(position: SIMD3<Float>, rotation: simd_quatf, scale: Float) {
        guard let messenger = messenger else {
            print("[SHAREPLAY] ❌ No messenger available to send origin update")
            return
        }
        
        print("[SHAREPLAY] 📤 Sending origin update: pos=\(position), rot=\(rotation), scale=\(scale)")
        
        Task {
            do {
                let message = SyncMessage.originUpdate(position: position, rotation: rotation, scale: scale)
                let data = try JSONEncoder().encode(message)
                try await messenger.send(data)
                print("[SHAREPLAY] ✅ Origin update sent successfully")
                logger.info("Sent origin update")
            } catch {
                print("[SHAREPLAY] ❌ Failed to send origin update: \(error)")
                logger.error("Failed to send origin update: \(error)")
            }
        }
    }
    
    func endSession() {
        print("[SHAREPLAY] 🛑 Ending SharePlay session...")
        logger.info("Ending SharePlay session")
        
        groupSession?.leave()
        groupSession = nil
        messenger = nil
        cancellables.removeAll()
        
        isSharePlayActive = false
        activeParticipants.removeAll()
        nearbyParticipants.removeAll()
        remoteParticipants.removeAll()
        
        print("[SHAREPLAY] ✅ SharePlay session ended successfully")
    }
    
    // MARK: - SystemCoordinator Support
    
#if os(visionOS)
    private func setupSystemCoordinatorMonitoring(_ coordinator: SystemCoordinator) {
        print("[SHAREPLAY] 🎯 Setting up SystemCoordinator monitoring for visionOS 26 features")
        logger.info("Setting up SystemCoordinator monitoring with visionOS 26 enhancements")
        
        // Note: Remote participant state monitoring not available in current GroupActivities API
        
        // Enhanced local participant monitoring for visionOS 26
        Task {
            for await localState in coordinator.localParticipantStates {
                print("[SHAREPLAY] 🧑 Local participant state changed: isSpatial=\(localState.isSpatial)")
                await handleLocalParticipantStateChange(localState)
            }
        }
        
        // Monitor group immersion style changes
        Task {
            for await immersionStyle in coordinator.groupImmersionStyle {
                if let style = immersionStyle {
                    print("[SHAREPLAY] 🌐 Group immersion style changed: \(String(describing: style))")
                    await handleGroupImmersionStyleChange(style)
                } else {
                    print("[SHAREPLAY] 🌐 Group immersion style cleared")
                }
            }
        }
    }
    
    private func handleRemoteParticipantStatesChange(_ states: [Participant: SystemCoordinator.ParticipantState]) async {
        print("[SHAREPLAY] 🌐 Handling remote participant states change (visionOS 26)")
        logger.info("Remote participant states changed: \(states.count) participants")
        
        for (participant, state) in states {
            let isNearby = participant.isNearbyWithLocalParticipant
            let isSpatial = state.isSpatial
            
            print("[SHAREPLAY] 👤 Participant \(participant.id): nearby=\(isNearby), spatial=\(isSpatial)")
            
            // visionOS 26: Handle positioning differences for nearby vs remote
            if isNearby {
                // Nearby participants can't be repositioned by system - use actual pose
                await handleNearbyParticipantPositioning(participant, state)
            } else {
                // Remote spatial personas can be repositioned to seats
                await handleRemoteParticipantPositioning(participant, state)
            }
            
            // Update spatial template manager with positioning info
            spatialTemplateManager?.updateParticipantPositioning(participant, state)
        }
    }
    
    private func handleNearbyParticipantPositioning(_ participant: Participant, _ state: SystemCoordinator.ParticipantState) async {
        // visionOS 26: Use actual participant pose for nearby participants (they can't be moved)
        print("[SHAREPLAY] 📍 Nearby participant \(participant.id) positioning - using actual pose")
        logger.info("Nearby participant \(participant.id): isSpatial=\(state.isSpatial)")
        
        // Position content relative to their actual position, not seat
        // Content should adapt to where nearby participants actually are
    }
    
    private func handleRemoteParticipantPositioning(_ participant: Participant, _ state: SystemCoordinator.ParticipantState) async {
        // visionOS 26: Remote participants can use either pose or seat.pose
        print("[SHAREPLAY] 💺 Remote participant \(participant.id) positioning - can use seat arrangement")
        logger.info("Remote participant \(participant.id): isSpatial=\(state.isSpatial)")
        
        // Can position content relative to seat.pose since spatial personas can be repositioned
    }

    private func handleLocalParticipantStateChange(_ state: SystemCoordinator.ParticipantState) async {
        print("[SHAREPLAY] 🔄 Handling local participant state change")
        logger.info("Local participant state changed: isSpatial=\(state.isSpatial)")
        
        // Handle spatial state changes
        if state.isSpatial {
            print("[SHAREPLAY] 🌐 Local participant is now in spatial mode")
            // Update any UI or state related to spatial mode
        } else {
            print("[SHAREPLAY] 📱 Local participant is in non-spatial mode")
        }
    }
    
    private func handleGroupImmersionStyleChange(_ style: ImmersionStyle) async {
        print("[SHAREPLAY] 🎨 Handling group immersion style change: \(String(describing: style))")
        logger.info("Group immersion style changed: \(String(describing: style))")
        
        // Handle immersion style changes
        // This could affect how the shared experience is rendered
    }
#endif
}
