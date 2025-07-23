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
    
    weak var delegate: SharePlaySessionDelegate?
    
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
        
        switch await activity.prepareForActivation() {
        case .activationPreferred:
            do {
                _ = try await activity.activate()
                logger.info("SharePlay activity activated successfully")
            } catch {
                logger.error("Failed to activate SharePlay activity: \(error)")
            }
        case .activationDisabled:
            logger.warning("SharePlay activation is disabled")
        case .cancelled:
            logger.info("SharePlay activation was cancelled")
        @unknown default:
            logger.warning("Unknown SharePlay activation result")
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
                self?.updateParticipants(participants)
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
    
    private func updateParticipants(_ participants: Set<Participant>) {
        activeParticipants = participants
        
        // Note: isNearbyWithLocalParticipant may not be available in current visionOS
        // This is a placeholder for the visionOS 26 API
        nearbyParticipants = Set(participants.filter { participant in
            // participant.isNearbyWithLocalParticipant && 
            participant.id != groupSession?.localParticipant.id
        })
        
        remoteParticipants = Set(participants.filter { participant in
            // !participant.isNearbyWithLocalParticipant &&
            participant.id != groupSession?.localParticipant.id
        })
        
        logger.info("Updated participants - Total: \(participants.count), Nearby: \(self.nearbyParticipants.count), Remote: \(self.remoteParticipants.count)")
        
        delegate?.participantsDidUpdate(
            nearby: nearbyParticipants,
            remote: remoteParticipants
        )
    }
    
    private func setupMessageHandling() {
        guard let messenger = messenger else { return }
        
        Task {
            for await (message, context) in messenger.messages(of: SyncMessage.self) {
                if let participant = context.source {
                    await handleSyncMessage(message, from: participant)
                }
            }
        }
    }
    
    private func handleSyncMessage(_ message: SyncMessage, from sender: Participant) async {
        logger.debug("Received message from \(sender.id): \(String(describing: message))")
        
        switch message {
        case .modelSelection(let modelIdentifier):
            await delegate?.didReceiveModelSelection(modelIdentifier, from: sender)
            
        case .cameraUpdate(let position, let rotation, let timestamp):
            await delegate?.didReceiveCameraUpdate(
                position: position,
                rotation: rotation,
                timestamp: timestamp,
                from: sender
            )
            
        case .viewingStateUpdate(let state):
            await delegate?.didReceiveViewingStateUpdate(state, from: sender)
            
        case .participantPointer(let position, let participantID):
            await delegate?.didReceiveParticipantPointer(
                position: position,
                participantID: participantID,
                from: sender
            )
            
        case .annotation(let annotation):
            await delegate?.didReceiveAnnotation(annotation, from: sender)
        }
    }
    
    func sendModelSelection(_ modelIdentifier: ModelIdentifier) {
        guard let messenger = messenger else { return }
        
        Task {
            do {
                try await messenger.send(.modelSelection(modelIdentifier))
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
                try await messenger.send(.cameraUpdate(
                    position: position,
                    rotation: rotation,
                    timestamp: currentTime
                ))
                
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
                try await messenger.send(.viewingStateUpdate(state))
                logger.debug("Sent viewing state update")
            } catch {
                logger.error("Failed to send viewing state update: \(error)")
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

protocol SharePlaySessionDelegate: AnyObject {
    func participantsDidUpdate(nearby: Set<Participant>, remote: Set<Participant>) async
    func didReceiveModelSelection(_ modelIdentifier: ModelIdentifier, from participant: Participant) async
    func didReceiveCameraUpdate(position: SIMD3<Float>, rotation: simd_quatf, timestamp: TimeInterval, from participant: Participant) async
    func didReceiveViewingStateUpdate(_ state: SyncMessage.ViewingState, from participant: Participant) async
    func didReceiveParticipantPointer(position: SIMD3<Float>, participantID: String, from participant: Participant) async
    func didReceiveAnnotation(_ annotation: SyncMessage.AnnotationMessage, from participant: Participant) async
}