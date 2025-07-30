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
        logger.info("Starting SharePlay activity with model: \(modelIdentifier?.displayName ?? "none")")
        
        let activity = SplatViewingActivity(modelIdentifier: modelIdentifier)
        
        do {
            _ = try await activity.activate()
            logger.info("SharePlay activity activated successfully")
        } catch {
            logger.error("Failed to activate SharePlay activity: \(error)")
        }
    }
    
    private func configureGroupSession(_ session: GroupSession<SplatViewingActivity>) async {
        logger.info("Configuring group session with \(session.activeParticipants.count) participants")
        
        groupSession = session
        messenger = GroupSessionMessenger(session: session)
        
        session.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] state in
                self?.sessionState = state
                self?.isSharePlayActive = (state == .joined)
                self?.logger.info("Session state changed to: \(String(describing: state))")
            }
            .store(in: &cancellables)
        
        session.$activeParticipants
            .receive(on: DispatchQueue.main)
            .sink { [weak self] participants in
                Task {
                    await self?.updateParticipants(participants)
                }
            }
            .store(in: &cancellables)
        
        setupMessageHandling()
        
        session.join()
        
        // Enable group immersive space for visionOS
        #if os(visionOS)
        if let coordinator = await session.systemCoordinator {
            var configuration = SystemCoordinator.Configuration()
            configuration.supportsGroupImmersiveSpace = true
            coordinator.configuration = configuration
        }
        #endif
    }
    
    private func updateParticipants(_ participants: Set<Participant>) async {
        activeParticipants = participants
        
        nearbyParticipants = Set(participants.filter { participant in
            participant.isNearbyWithLocalParticipant &&
            participant.id != groupSession?.localParticipant.id
        })
        
        remoteParticipants = Set(participants.filter { participant in
            !participant.isNearbyWithLocalParticipant &&
            participant.id != groupSession?.localParticipant.id
        })
        
        logger.info("Updated participants - Total: \(participants.count), Nearby: \(self.nearbyParticipants.count), Remote: \(self.remoteParticipants.count)")
        
        await notify { await $0.participantsDidUpdate(nearby: self.nearbyParticipants, remote: self.remoteParticipants) }
    }
    
    private func setupMessageHandling() {
        guard let messenger = messenger else { return }
        
        Task {
            for await (data, context) in messenger.messages(of: Data.self) {
                do {
                    let message = try JSONDecoder().decode(SyncMessage.self, from: data)
                    let participant = context.source
                    await handleSyncMessage(message, from: participant)
                } catch {
                    logger.error("Failed to decode message: \(error)")
                }
            }
        }
    }
    
    private func handleSyncMessage(_ message: SyncMessage, from sender: Participant) async {
        logger.debug("Received message from \(sender.id): \(String(describing: message))")
        
        switch message {
        case .modelSelection(let modelIdentifier):
            await notify { await $0.didReceiveModelSelection(modelIdentifier, from: sender) }
            
        case .cameraUpdate(let position, let rotation, let timestamp):
            await notify {
                await $0.didReceiveCameraUpdate(
                    position: position,
                    rotation: rotation,
                    timestamp: timestamp,
                    from: sender
                )
            }
            
        case .viewingStateUpdate(let state):
            await notify { await $0.didReceiveViewingStateUpdate(state, from: sender) }
            
        case .participantPointer(let position, let participantID):
            await notify { await $0.didReceiveParticipantPointer(position: position, participantID: participantID, from: sender) }
            
        case .annotation(let annotation):
            await notify { await $0.didReceiveAnnotation(annotation, from: sender) }
        }
    }
    
    func sendModelSelection(_ modelIdentifier: ModelIdentifier) {
        guard let messenger = messenger else { return }
        
        Task {
            do {
                let message = SyncMessage.modelSelection(modelIdentifier)
                let data = try JSONEncoder().encode(message)
                try await messenger.send(data)
                logger.debug("Sent model selection: \(modelIdentifier.description)")
            } catch {
                logger.error("Failed to send model selection: \(error)")
            }
        }
    }
    
    func sendCameraUpdate(position: SIMD3<Float>, rotation: simd_quatf) {
        guard let messenger = messenger else { return }
        
        let currentTime = CACurrentMediaTime()
        guard currentTime - lastCameraUpdateTime >= cameraUpdateThrottle else { return }
        lastCameraUpdateTime = currentTime
        
        Task {
            do {
                let message = SyncMessage.cameraUpdate(
                    position: position,
                    rotation: rotation,
                    timestamp: currentTime
                )
                let data = try JSONEncoder().encode(message)
                try await messenger.send(data)
                
                logger.debug("Sent camera update")
            } catch {
                logger.error("Failed to send camera update: \(error)")
            }
        }
    }
    
    func sendViewingStateUpdate(_ state: SyncMessage.ViewingState) {
        guard let messenger = messenger else { return }
        
        Task {
            do {
                let message = SyncMessage.viewingStateUpdate(state)
                let data = try JSONEncoder().encode(message)
                try await messenger.send(data)
                logger.debug("Sent viewing state update")
            } catch {
                logger.error("Failed to send viewing state update: \(error)")
            }
        }
    }
    
    func sendParticipantPointer(position: SIMD3<Float>, participantID: String) {
        guard let messenger = messenger else { return }
        
        Task {
            do {
                let message = SyncMessage.participantPointer(position: position, participantID: participantID)
                let data = try JSONEncoder().encode(message)
                try await messenger.send(data)
                logger.info("Sent participant pointer update")
            } catch {
                logger.error("Failed to send participant pointer: \(error)")
            }
        }
    }
    
    func sendAnnotation(_ annotation: SyncMessage.AnnotationMessage) {
        guard let messenger = messenger else { return }
        
        Task {
            do {
                let message = SyncMessage.annotation(annotation)
                let data = try JSONEncoder().encode(message)
                try await messenger.send(data)
                logger.info("Sent annotation")
            } catch {
                logger.error("Failed to send annotation: \(error)")
            }
        }
    }
    
    func endSession() {
        logger.info("Ending SharePlay session")
        
        groupSession?.leave()
        groupSession = nil
        messenger = nil
        cancellables.removeAll()
        
        isSharePlayActive = false
        activeParticipants.removeAll()
        nearbyParticipants.removeAll()
        remoteParticipants.removeAll()
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