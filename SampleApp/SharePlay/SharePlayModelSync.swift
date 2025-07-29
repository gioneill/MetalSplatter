import Foundation
import Combine
import OSLog
import GroupActivities
import simd

@MainActor
class SharePlayModelSync: ObservableObject {
    private let logger = Logger(subsystem: "com.metalsplatter", category: "ModelSync")
    
    @Published var currentModel: ModelIdentifier?
    @Published var isLoadingSharedModel = false
    @Published var sharedModelLoadingProgress: Double = 0.0
    
    private var sessionManager: SharePlaySessionManager?
    private var cancellables = Set<AnyCancellable>()
    
    weak var delegate: SharePlayModelSyncDelegate?
    
    init() {
        setupNotifications()
    }
    
    func configure(with sessionManager: SharePlaySessionManager) {
        self.sessionManager = sessionManager
        sessionManager.delegate = self
    }
    
    private func setupNotifications() {
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ModelDidLoad"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let modelIdentifier = notification.userInfo?["modelIdentifier"] as? ModelIdentifier {
                Task { @MainActor in
                    self?.handleLocalModelLoad(modelIdentifier)
                }
            }
        }
    }
    
    private func handleLocalModelLoad(_ modelIdentifier: ModelIdentifier) {
        guard let sessionManager = sessionManager,
              sessionManager.isSharePlayActive else { return }
        
        // Only send if this is a user-initiated model change
        if currentModel != modelIdentifier {
            currentModel = modelIdentifier
            sessionManager.sendModelSelection(modelIdentifier)
            logger.info("Sent model selection to SharePlay participants: \(modelIdentifier.displayName)")
        }
    }
    
    func selectModel(_ modelIdentifier: ModelIdentifier) async {
        currentModel = modelIdentifier
        
        // Broadcast to SharePlay participants
        sessionManager?.sendModelSelection(modelIdentifier)
        
        // Load locally
        await delegate?.shouldLoadModel(modelIdentifier)
        
        logger.info("Selected and broadcasting model: \(modelIdentifier.displayName)")
    }
    
    private func loadSharedModel(_ modelIdentifier: ModelIdentifier, from participant: Participant) async {
        logger.info("Loading shared model from participant \(participant.id): \(modelIdentifier.displayName)")
        
        isLoadingSharedModel = true
        sharedModelLoadingProgress = 0.0
        
        do {
            // Simulate loading progress for demonstration
            // In a real implementation, this would track actual loading progress
            for i in 1...10 {
                sharedModelLoadingProgress = Double(i) / 10.0
                try await Task.sleep(for: .milliseconds(100))
            }
            
            currentModel = modelIdentifier
            await delegate?.shouldLoadModel(modelIdentifier)
            
            logger.info("Successfully loaded shared model: \(modelIdentifier.displayName)")
        } catch {
            logger.error("Failed to load shared model: \(error)")
        }
        
        isLoadingSharedModel = false
    }
    
    func handleModelAvailabilityCheck(_ modelIdentifier: ModelIdentifier) -> ModelAvailability {
        switch modelIdentifier {
        case .sampleBox:
            return .available
        case .gaussianSplat(let url):
            if FileManager.default.fileExists(atPath: url.path) {
                return .available
            } else {
                return .needsDownload(url)
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
}

enum ModelAvailability {
    case available
    case needsDownload(URL)
    case unavailable(String)
}

extension SharePlayModelSync: SharePlaySessionDelegate {
    func participantsDidUpdate(nearby: Set<Participant>, remote: Set<Participant>) async {
        // Model sync doesn't need to handle participant updates directly
    }
    
    func didReceiveModelSelection(_ modelIdentifier: ModelIdentifier, from participant: Participant) async {
        logger.info("Received model selection from participant \(participant.id): \(modelIdentifier.displayName)")
        
        let availability = handleModelAvailabilityCheck(modelIdentifier)
        
        switch availability {
        case .available:
            await loadSharedModel(modelIdentifier, from: participant)
        case .needsDownload(let url):
            logger.warning("Model not available locally, needs download: \(url)")
            // In a real implementation, you might:
            // 1. Show a dialog to the user
            // 2. Attempt to download the model
            // 3. Use iCloud sharing or other mechanisms
            await showModelUnavailableAlert(modelIdentifier, reason: "Model file not found locally")
        case .unavailable(let reason):
            logger.error("Model unavailable: \(reason)")
            await showModelUnavailableAlert(modelIdentifier, reason: reason)
        }
    }
    
    func didReceiveCameraUpdate(position: SIMD3<Float>, rotation: simd_quatf, timestamp: TimeInterval, from participant: Participant) async {
        // Camera updates are handled by SharePlayCameraSync
    }
    
    func didReceiveViewingStateUpdate(_ state: SyncMessage.ViewingState, from participant: Participant) async {
        // Handle playback state synchronization if needed
        logger.debug("Received viewing state update from \(participant.id): playing=\(state.isPlaying)")
    }
    
    func didReceiveParticipantPointer(position: SIMD3<Float>, participantID: String, from participant: Participant) async {
        // Pointer updates are handled elsewhere
    }
    
    func didReceiveAnnotation(_ annotation: SyncMessage.AnnotationMessage, from participant: Participant) async {
        // Annotation updates are handled elsewhere
    }
    
    private func showModelUnavailableAlert(_ modelIdentifier: ModelIdentifier, reason: String) async {
        // Post notification for UI to handle
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowModelUnavailableAlert"),
            object: nil,
            userInfo: [
                "modelIdentifier": modelIdentifier,
                "reason": reason
            ]
        )
    }
}

protocol SharePlayModelSyncDelegate: AnyObject {
    func shouldLoadModel(_ modelIdentifier: ModelIdentifier) async
}