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
        print("[SHAREPLAY] 🎭 SharePlayModelSync initialized")
        setupNotifications()
    }
    
    func configure(with sessionManager: SharePlaySessionManager) {
        print("[SHAREPLAY] 🔧 Configuring SharePlayModelSync with session manager")
        self.sessionManager = sessionManager
        sessionManager.addDelegate(self)
        print("[SHAREPLAY] ✅ SharePlayModelSync configuration complete")
    }
    
    private func setupNotifications() {
        print("[SHAREPLAY] 📡 Setting up model sync notifications")
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ModelDidLoad"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let modelIdentifier = notification.userInfo?["modelIdentifier"] as? ModelIdentifier {
                print("[SHAREPLAY] 📨 Received ModelDidLoad notification: \(modelIdentifier.displayName)")
                Task { @MainActor in
                    self?.handleLocalModelLoad(modelIdentifier)
                }
            } else {
                print("[SHAREPLAY] ⚠️ Invalid ModelDidLoad notification received")
            }
        }
        print("[SHAREPLAY] ✅ Model sync notifications setup complete")
    }
    
    private func handleLocalModelLoad(_ modelIdentifier: ModelIdentifier) {
        guard let sessionManager = sessionManager,
              sessionManager.isSharePlayActive else { 
            print("[SHAREPLAY] ⚠️ Cannot handle local model load - SharePlay not active or no session manager")
            return 
        }
        
        print("[SHAREPLAY] 🎭 Handling local model load: \(modelIdentifier.displayName)")
        
        // Only send if this is a user-initiated model change
        if currentModel != modelIdentifier {
            print("[SHAREPLAY] 🔄 Model changed from \(String(describing: currentModel)) to \(modelIdentifier.displayName)")
            currentModel = modelIdentifier
            sessionManager.sendModelSelection(modelIdentifier)
            print("[SHAREPLAY] 📤 Sent model selection to SharePlay participants")
            logger.info("Sent model selection to SharePlay participants: \(modelIdentifier.displayName)")
        } else {
            print("[SHAREPLAY] ℹ️ Model unchanged, not sending to participants")
        }
    }
    
    func selectModel(_ modelIdentifier: ModelIdentifier) async {
        print("[SHAREPLAY] 🎯 Selecting model: \(modelIdentifier.displayName)")
        currentModel = modelIdentifier
        
        // Broadcast to SharePlay participants
        if let sessionManager = sessionManager {
            print("[SHAREPLAY] 📡 Broadcasting model selection to participants")
            sessionManager.sendModelSelection(modelIdentifier)
        } else {
            print("[SHAREPLAY] ⚠️ No session manager available for broadcasting")
        }
        
        // Load locally
        print("[SHAREPLAY] 💼 Loading model locally via delegate")
        await delegate?.shouldLoadModel(modelIdentifier)
        
        print("[SHAREPLAY] ✅ Model selection complete: \(modelIdentifier.displayName)")
        logger.info("Selected and broadcasting model: \(modelIdentifier.displayName)")
    }
    
    private func loadSharedModel(_ modelIdentifier: ModelIdentifier, from participant: Participant) async {
        print("[SHAREPLAY] 💼 Loading shared model from participant \(participant.id): \(modelIdentifier.displayName)")
        logger.info("Loading shared model from participant \(participant.id): \(modelIdentifier.displayName)")
        
        isLoadingSharedModel = true
        sharedModelLoadingProgress = 0.0
        print("[SHAREPLAY] 🔄 Started loading shared model, progress: 0%")
        
        do {
            // Simulate loading progress for demonstration
            // In a real implementation, this would track actual loading progress
            for i in 1...10 {
                sharedModelLoadingProgress = Double(i) / 10.0
                print("[SHAREPLAY] 📈 Loading progress: \(Int(sharedModelLoadingProgress * 100))%")
                try await Task.sleep(for: .milliseconds(100))
            }
            
            print("[SHAREPLAY] 🔄 Setting current model and notifying delegate")
            currentModel = modelIdentifier
            await delegate?.shouldLoadModel(modelIdentifier)
            
            print("[SHAREPLAY] ✅ Successfully loaded shared model: \(modelIdentifier.displayName)")
            logger.info("Successfully loaded shared model: \(modelIdentifier.displayName)")
        } catch {
            print("[SHAREPLAY] ❌ Failed to load shared model: \(error)")
            logger.error("Failed to load shared model: \(error)")
        }
        
        isLoadingSharedModel = false
        print("[SHAREPLAY] 🏁 Model loading process complete")
    }
    
    func handleModelAvailabilityCheck(_ modelIdentifier: ModelIdentifier) -> ModelAvailability {
        print("[SHAREPLAY] 🔍 Checking model availability: \(modelIdentifier.displayName)")
        
        switch modelIdentifier {
        case .sampleBox:
            print("[SHAREPLAY] ✅ SampleBox is always available")
            return .available
        case .gaussianSplat(let url):
            let exists = FileManager.default.fileExists(atPath: url.path)
            print("[SHAREPLAY] 📁 Gaussian splat file check: \(url.path) exists=\(exists)")
            if exists {
                print("[SHAREPLAY] ✅ Model file available locally")
                return .available
            } else {
                print("[SHAREPLAY] ⚠️ Model file not found, needs download")
                return .needsDownload(url)
            }
        }
    }
    
    deinit {
        print("[SHAREPLAY] 🗑️ SharePlayModelSync deinit - cleaning up notifications")
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
        print("[SHAREPLAY] 📨 Received model selection from participant \(participant.id): \(modelIdentifier.displayName)")
        logger.info("Received model selection from participant \(participant.id): \(modelIdentifier.displayName)")
        
        let availability = handleModelAvailabilityCheck(modelIdentifier)
        
        switch availability {
        case .available:
            print("[SHAREPLAY] ✅ Model available, proceeding to load")
            await loadSharedModel(modelIdentifier, from: participant)
        case .needsDownload(let url):
            print("[SHAREPLAY] ⚠️ Model not available locally, needs download: \(url)")
            logger.warning("Model not available locally, needs download: \(url)")
            // In a real implementation, you might:
            // 1. Show a dialog to the user
            // 2. Attempt to download the model
            // 3. Use iCloud sharing or other mechanisms
            await showModelUnavailableAlert(modelIdentifier, reason: "Model file not found locally")
        case .unavailable(let reason):
            print("[SHAREPLAY] ❌ Model unavailable: \(reason)")
            logger.error("Model unavailable: \(reason)")
            await showModelUnavailableAlert(modelIdentifier, reason: reason)
        }
    }
    
    func didReceiveCameraUpdate(position: SIMD3<Float>, rotation: simd_quatf, timestamp: TimeInterval, from participant: Participant) async {
        // Camera updates are handled by SharePlayCameraSync
    }
    
    func didReceiveViewingStateUpdate(_ state: SyncMessage.ViewingState, from participant: Participant) async {
        // Handle playback state synchronization if needed
        print("[SHAREPLAY] 📺 Received viewing state update from \(participant.id): playing=\(state.isPlaying)")
        logger.debug("Received viewing state update from \(participant.id): playing=\(state.isPlaying)")
    }
    
    func didReceiveParticipantPointer(position: SIMD3<Float>, participantID: String, from participant: Participant) async {
        // Pointer updates are handled elsewhere
    }
    
    func didReceiveAnnotation(_ annotation: SyncMessage.AnnotationMessage, from participant: Participant) async {
        // Annotation updates are handled elsewhere
    }
    
    private func showModelUnavailableAlert(_ modelIdentifier: ModelIdentifier, reason: String) async {
        print("[SHAREPLAY] ⚠️ Showing model unavailable alert: \(modelIdentifier.displayName) - \(reason)")
        
        // Post notification for UI to handle
        NotificationCenter.default.post(
            name: NSNotification.Name("ShowModelUnavailableAlert"),
            object: nil,
            userInfo: [
                "modelIdentifier": modelIdentifier,
                "reason": reason
            ]
        )
        
        print("[SHAREPLAY] 📡 Model unavailable alert notification posted")
    }
}

protocol SharePlayModelSyncDelegate: AnyObject {
    func shouldLoadModel(_ modelIdentifier: ModelIdentifier) async
}