import Foundation
import Combine
import OSLog
import GroupActivities
import simd
import UniformTypeIdentifiers
import UIKit

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
    
    @MainActor
    private func showSimpleAlert(title: String, message: String) async {
        await MainActor.run {
            guard let root = UIApplication.shared.connectedScenes
                    .compactMap({ ($0 as? UIWindowScene)?.keyWindow?.rootViewController })
                    .first else { return }
            
            let alert = UIAlertController(title: title,
                                          message: message,
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            root.present(alert, animated: true)
        }
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
        
        // Already loaded? Nothing to do.
        guard currentModel != modelIdentifier else { return }
        
        // Quick local check
        if case .available = handleModelAvailabilityCheck(modelIdentifier) {
            await loadSharedModel(modelIdentifier, from: participant)
            return
        }
        
        // Interactive picker loop for missing files
        let expectedName = modelIdentifier.displayName
        
        while true {
            let pickedURL: URL
            do {
                pickedURL = try await DocumentPicker.pickFile(allowedTypes: [.item])
            } catch {
                logger.warning("User cancelled picker → aborting model load")
                return
            }
            
            // Validate the filename matches
            if pickedURL.lastPathComponent.compare(expectedName, options: [.caseInsensitive]) == .orderedSame {
                // Success!
                let newIdentifier = ModelIdentifier.gaussianSplat(pickedURL)
                await loadSharedModel(newIdentifier, from: participant)
                return
            }
            
            // Not a match → show error and loop
            logger.notice("Picked '\(pickedURL.lastPathComponent)' — need '\(expectedName)'")
            await showSimpleAlert(
                title: "Wrong File",
                message: "Please pick the same file the host chose: \(expectedName)"
            )
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
    
    func didReceiveImmersiveSceneUpdate(isActive: Bool, modelIdentifier: ModelIdentifier?, from participant: Participant) async {
        print("[SHAREPLAY] 🌐 Received immersive scene update: isActive=\(isActive)")
        
        if isActive, let modelIdentifier = modelIdentifier {
            // Host entered immersive space - we need to join them
            
            // First ensure we have the model
            if case .available = handleModelAvailabilityCheck(modelIdentifier) {
                // We have it - load and enter immersive space
                await loadSharedModel(modelIdentifier, from: participant)
                await enterImmersiveSpace(with: modelIdentifier)
            } else {
                // Need to pick the file first
                let expectedName = modelIdentifier.displayName
                
                while true {
                    let pickedURL: URL
                    do {
                        pickedURL = try await DocumentPicker.pickFile(allowedTypes: [.item])
                    } catch DocumentPicker.PickerError.cancelled {
                        // User cancelled - they choose not to join immersive space
                        logger.info("User cancelled joining immersive space")
                        return
                    } catch {
                        // Other error - show it
                        await showSimpleAlert(
                            title: "Error",
                            message: "Failed to pick file: \(error.localizedDescription)"
                        )
                        return
                    }
                    
                    // Validate the filename matches
                    if pickedURL.lastPathComponent.compare(expectedName, options: [.caseInsensitive]) == .orderedSame {
                        // Success! Load model and enter immersive space
                        let newIdentifier = ModelIdentifier.gaussianSplat(pickedURL)
                        await loadSharedModel(newIdentifier, from: participant)
                        await enterImmersiveSpace(with: newIdentifier)
                        return
                    }
                    
                    // Not a match → show error and loop
                    await showSimpleAlert(
                        title: "Wrong File",
                        message: "Please pick the same file the host chose: \(expectedName)"
                    )
                }
            }
        } else {
            // Host exited immersive space - we should too
            await exitImmersiveSpace()
        }
    }
    
    func didReceiveOriginUpdate(position: SIMD3<Float>, rotation: simd_quatf, scale: Float, from participant: Participant) async {
        print("[SHAREPLAY] 🎯 Received origin update from \(participant.id): pos=\(position), rot=\(rotation), scale=\(scale)")
        logger.info("Received origin update from participant \(participant.id)")
        
        // Post notification for VisionSceneRenderer to handle
        NotificationCenter.default.post(
            name: NSNotification.Name("ApplySharedOrigin"),
            object: nil,
            userInfo: [
                "position": position,
                "rotation": rotation,
                "scale": scale
            ]
        )
    }
    
    private func enterImmersiveSpace(with modelIdentifier: ModelIdentifier) async {
        // Post notification for ContentView to handle
        NotificationCenter.default.post(
            name: NSNotification.Name("EnterImmersiveSpaceRequested"),
            object: nil,
            userInfo: ["modelIdentifier": modelIdentifier]
        )
    }
    
    private func exitImmersiveSpace() async {
        // Post notification for ContentView to handle
        NotificationCenter.default.post(
            name: NSNotification.Name("ExitImmersiveSpaceRequested"),
            object: nil
        )
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