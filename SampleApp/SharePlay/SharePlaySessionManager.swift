import Foundation
import GroupActivities
import Combine
import OSLog
import simd
import QuartzCore

@MainActor
class SharePlaySessionManager: ObservableObject {
    private let logger = Logger(subsystem: "com.metalsplatter", category: "SharePlay")
    
    @Published var isSharePlayActive = false
    @Published var activeParticipants: Set<Participant> = []
    @Published var nearbyParticipants: Set<Participant> = []
    @Published var remoteParticipants: Set<Participant> = []
    @Published var sessionState: GroupSession<SplatViewingActivity>.State = .waiting
    
    private var groupSession: GroupSession<SplatViewingActivity>?
    private var messenger: GroupSessionMessenger?
    private var cancellables = Set<AnyCancellable>()
    
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
    }
    
    private func setupGroupSessionListener() {
        Task {
            for await session in SplatViewingActivity.sessions() {
                await configureGroupSession(session)
            }
        }
    }
    
    func startActivity(with modelIdentifier: ModelIdentifier?) async {
        print("[SHAREPLAY] 🚀 Starting SharePlay activity...")
        print("[SHAREPLAY] 📋 Model identifier: \(String(describing: modelIdentifier))")
        print("[SHAREPLAY] 📊 Current state - Active: \(isSharePlayActive), Participants: \(activeParticipants.count)")
        logger.info("Starting SharePlay activity with model: \(modelIdentifier?.displayName ?? "none")")
        
        let activity = SplatViewingActivity(modelIdentifier: modelIdentifier)
        print("[SHAREPLAY] 🎯 Created SplatViewingActivity with identifier: \(SplatViewingActivity.activityIdentifier)")
        
        do {
            print("[SHAREPLAY] 🔄 Attempting to activate SharePlay activity...")
            _ = try await activity.activate()
            print("[SHAREPLAY] ✅ SharePlay activity activated successfully!")
            logger.info("SharePlay activity activated successfully")
        } catch {
            print("[SHAREPLAY] ❌ Failed to activate SharePlay activity: \(error)")
            print("[SHAREPLAY] 🔍 Error details: \(error.localizedDescription)")
            logger.error("Failed to activate SharePlay activity: \(error)")
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
        } else {
            print("[SHAREPLAY] ⚠️ No system coordinator available")
        }
        #endif
    }
    
    private func updateParticipants(_ participants: Set<Participant>) async {
        print("[SHAREPLAY] 🔄 Updating participants...")
        activeParticipants = participants
        
        nearbyParticipants = Set(participants.filter { participant in
            participant.isNearbyWithLocalParticipant &&
            participant.id != groupSession?.localParticipant.id
        })
        
        remoteParticipants = Set(participants.filter { participant in
            !participant.isNearbyWithLocalParticipant &&
            participant.id != groupSession?.localParticipant.id
        })
        
        print("[SHAREPLAY] 📊 Participant breakdown:")
        print("[SHAREPLAY]   📱 Total: \(participants.count)")
        print("[SHAREPLAY]   🏠 Nearby: \(self.nearbyParticipants.count)")
        print("[SHAREPLAY]   📹 Remote: \(self.remoteParticipants.count)")
        
        for participant in nearbyParticipants {
            print("[SHAREPLAY]   🏠 Nearby participant: \(participant.id)")
        }
        for participant in remoteParticipants {
            print("[SHAREPLAY]   📹 Remote participant: \(participant.id)")
        }
        
        logger.info("Updated participants - Total: \(participants.count), Nearby: \(self.nearbyParticipants.count), Remote: \(self.remoteParticipants.count)")
        
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
}

@MainActor
protocol SharePlaySessionDelegate: AnyObject {
    func participantsDidUpdate(nearby: Set<Participant>, remote: Set<Participant>) async
    func didReceiveModelSelection(_ modelIdentifier: ModelIdentifier, from participant: Participant) async
    func didReceiveCameraUpdate(position: SIMD3<Float>, rotation: simd_quatf, timestamp: TimeInterval, from participant: Participant) async
    func didReceiveViewingStateUpdate(_ state: SyncMessage.ViewingState, from participant: Participant) async
    func didReceiveParticipantPointer(position: SIMD3<Float>, participantID: String, from participant: Participant) async
    func didReceiveAnnotation(_ annotation: SyncMessage.AnnotationMessage, from participant: Participant) async
}
