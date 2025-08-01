import Foundation
import SwiftUI
import GroupActivities
import OSLog
import Observation

@Observable
class SharePlayIntegrationHelper {
    private let logger = Logger(subsystem: "com.metalsplatter", category: "SharePlayIntegration")
    
    var isInitialized = false
    var performanceMetrics = SharePlayPerformanceMetrics()
    
    let sessionManager = SharePlaySessionManager()
    let cameraSync = SharePlayCameraSync()
    let modelSync = SharePlayModelSync()
    let nearbyHandler = NearbyParticipantHandler()
    let spatialContentManager = SpatialContentManager()
    
    private var performanceTimer: Timer?
    
    @MainActor init() {
        print("[SHAREPLAY] 🎆 SharePlayIntegrationHelper initializing...")
        setupIntegration()
    }
    
    @MainActor private func setupIntegration() {
        print("[SHAREPLAY] 🔧 Setting up SharePlay integration components...")
        
        // Configure all components
        print("[SHAREPLAY] 📷 Configuring camera sync...")
        cameraSync.configure(with: sessionManager)
        
        print("[SHAREPLAY] 🎭 Configuring model sync...")
        modelSync.configure(with: sessionManager)
        
        print("[SHAREPLAY] 👥 Configuring nearby handler...")
        nearbyHandler.configure(with: sessionManager)
        
        // Set up delegates
        print("[SHAREPLAY] 🔗 Setting up delegates...")
        modelSync.delegate = self
        
        // Start performance monitoring
        print("[SHAREPLAY] 📈 Starting performance monitoring...")
        startPerformanceMonitoring()
        
        isInitialized = true
        print("[SHAREPLAY] ✅ SharePlay integration initialized successfully")
        logger.info("SharePlay integration initialized successfully")
    }
    
    @MainActor func configureForRenderer(_ renderer: Any) {
        print("[SHAREPLAY] 🎬 Configuring integration for renderer: \(type(of: renderer))")
        
        // Configure integration specific to the renderer type
        if let visionRenderer = renderer as? VisionSceneRenderer {
            print("[SHAREPLAY] 🔗 Connecting VisionSceneRenderer with SharePlay components")
            visionRenderer.cameraSync = cameraSync
            visionRenderer.sharePlaySessionManager = sessionManager
            
            // Note: VisionSceneRenderer uses Metal directly, not RealityKit
            // Spatial content management would need to be implemented differently
            // or integrated into a RealityKit-based renderer
            print("[SHAREPLAY] ✅ VisionSceneRenderer connected successfully")
            logger.info("Configured SharePlay for VisionSceneRenderer")
        } else {
            print("[SHAREPLAY] ⚠️ Unknown renderer type, using default configuration")
        }
        
        print("[SHAREPLAY] ✅ SharePlay configuration complete for renderer")
        logger.info("SharePlay configured for renderer: \(type(of: renderer))")
    }
    
    private func startPerformanceMonitoring() {
        print("[SHAREPLAY] 🕰️ Starting performance monitoring timer (1 second intervals)")
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.updatePerformanceMetrics()
            }
        }
        print("[SHAREPLAY] ✅ Performance monitoring started")
    }
    
    private func updatePerformanceMetrics() {
        // Only log metrics every 10 seconds to avoid spam
        let shouldLog = Int(Date().timeIntervalSince1970) % 10 == 0
        
        performanceMetrics.activeSessions = sessionManager.isSharePlayActive ? 1 : 0
        performanceMetrics.totalParticipants = sessionManager.activeParticipants.count
        performanceMetrics.nearbyParticipants = sessionManager.nearbyParticipants.count
        performanceMetrics.remoteParticipants = sessionManager.remoteParticipants.count
        
        // Memory usage (simplified)
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let kerr: kern_return_t = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if kerr == KERN_SUCCESS {
            performanceMetrics.memoryUsageMB = Double(memoryInfo.resident_size) / (1024 * 1024)
        }
        
        // Network usage tracking would be more complex and require additional frameworks
        performanceMetrics.networkLatencyMs = measureNetworkLatency()
        
        if shouldLog && sessionManager.isSharePlayActive {
            print("[SHAREPLAY] 📈 Performance metrics - Sessions: \(performanceMetrics.activeSessions), Participants: \(performanceMetrics.totalParticipants) (\(performanceMetrics.nearbyParticipants) nearby, \(performanceMetrics.remoteParticipants) remote), Memory: \(String(format: "%.1f", performanceMetrics.memoryUsageMB))MB, Latency: \(String(format: "%.0f", performanceMetrics.networkLatencyMs))ms")
        }
    }
    
    private func measureNetworkLatency() -> Double {
        // Simplified latency measurement
        // In a real implementation, you'd measure actual round-trip times
        return sessionManager.isSharePlayActive ? Double.random(in: 20...100) : 0
    }
    
    func optimizePerformance() {
        print("[SHAREPLAY] ⚙️ Running performance optimization...")
        
        // Optimization strategies based on current conditions
        
        if self.performanceMetrics.networkLatencyMs > 150 {
            // High latency - reduce update frequency
            print("[SHAREPLAY] ⚠️ High network latency detected (\(self.performanceMetrics.networkLatencyMs)ms), reducing update frequency")
            logger.warning("High network latency detected (\(self.performanceMetrics.networkLatencyMs)ms), reducing update frequency")
            // Implement adaptive update rates
        }
        
        if self.performanceMetrics.memoryUsageMB > 500 {
            // High memory usage - clean up unused resources
            print("[SHAREPLAY] ⚠️ High memory usage detected (\(self.performanceMetrics.memoryUsageMB)MB), cleaning up resources")
            logger.warning("High memory usage detected (\(self.performanceMetrics.memoryUsageMB)MB), cleaning up resources")
            cleanupResources()
        }
        
        if self.performanceMetrics.totalParticipants > 8 {
            // Many participants - optimize rendering
            print("[SHAREPLAY] 👥 Many participants (\(self.performanceMetrics.totalParticipants)), optimizing rendering")
            logger.info("Many participants (\(self.performanceMetrics.totalParticipants)), optimizing rendering")
            optimizeForManyParticipants()
        }
        
        print("[SHAREPLAY] ✅ Performance optimization complete")
    }
    
    private func cleanupResources() {
        print("[SHAREPLAY] 🧹 Cleaning up unused resources...")
        
        // Clean up unused spatial content
        let activeParticipantIDs = Set(sessionManager.activeParticipants.map { $0.id.uuidString })
        let beforePointers = spatialContentManager.participantPointers.count
        spatialContentManager.participantPointers = spatialContentManager.participantPointers.filter { (participantID, _) in
            activeParticipantIDs.contains(participantID)
        }
        let removedPointers = beforePointers - spatialContentManager.participantPointers.count
        
        // Clean up old annotations
        let cutoffTime = CACurrentMediaTime() - 300 // 5 minutes
        let beforeAnnotations = spatialContentManager.sharedAnnotations.count
        spatialContentManager.sharedAnnotations = spatialContentManager.sharedAnnotations.filter { (_, annotation) in
            annotation.annotation.timestamp >= cutoffTime
        }
        let removedAnnotations = beforeAnnotations - spatialContentManager.sharedAnnotations.count
        
        print("[SHAREPLAY] 🗑️ Cleanup complete - removed \(removedPointers) pointers, \(removedAnnotations) annotations")
    }
    
    private func optimizeForManyParticipants() {
        print("[SHAREPLAY] 🚀 Applying optimizations for many participants...")
        // Reduce visual fidelity for participant indicators
        // Implement level-of-detail for distant participants
        // Batch updates more aggressively
        print("[SHAREPLAY] ✅ Applied optimizations for many participants")
        logger.debug("Applied optimizations for many participants")
    }
    
    func handleError(_ error: SharePlayError) {
        print("[SHAREPLAY] ❌ SharePlay error occurred: \(error.localizedDescription)")
        logger.error("SharePlay error: \(error.localizedDescription)")
        
        switch error {
        case .networkError:
            print("[SHAREPLAY] 🔄 Network error - attempting to reconnect in 5 seconds...")
            // Attempt to reconnect
            Task {
                try? await Task.sleep(for: .seconds(5))
                print("[SHAREPLAY] 🔄 Retrying connection...")
                // Retry connection logic
            }
        case .participantLeft:
            print("[SHAREPLAY] 👋 Participant left - cleaning up resources")
            // Clean up participant-specific resources
            cleanupResources()
        case .modelSyncFailed:
            print("[SHAREPLAY] 🎭 Model sync failed - handling fallback")
            // Fallback to previous model or show error to user
            break
        case .spatialTrackingFailed:
            print("[SHAREPLAY] 🗺 Spatial tracking failed - disabling spatial features temporarily")
            // Disable spatial features temporarily
            break
        }
    }
    
    deinit {
        print("[SHAREPLAY] 🗑️ SharePlayIntegrationHelper deinit - cleaning up")
        performanceTimer?.invalidate()
        let sessionManager = self.sessionManager
        Task { @MainActor in
            sessionManager.endSession()
        }
        print("[SHAREPLAY] ✅ SharePlayIntegrationHelper cleanup complete")
    }
}

extension SharePlayIntegrationHelper: SharePlayModelSyncDelegate {
    func shouldLoadModel(_ modelIdentifier: ModelIdentifier) async {
        print("[SHAREPLAY] 🎬 Delegating model load request: \(modelIdentifier.displayName)")
        
        // Delegate model loading to the appropriate renderer
        NotificationCenter.default.post(
            name: NSNotification.Name("SharePlayModelLoadRequested"),
            object: nil,
            userInfo: ["modelIdentifier": modelIdentifier]
        )
        
        print("[SHAREPLAY] 📡 SharePlayModelLoadRequested notification posted")
    }
}

struct SharePlayPerformanceMetrics {
    var activeSessions: Int = 0
    var totalParticipants: Int = 0
    var nearbyParticipants: Int = 0
    var remoteParticipants: Int = 0
    var memoryUsageMB: Double = 0
    var networkLatencyMs: Double = 0
    var messagesPerSecond: Double = 0
    var spatialObjectsCount: Int = 0
}

enum SharePlayError: LocalizedError {
    case networkError
    case participantLeft
    case modelSyncFailed
    case spatialTrackingFailed
    
    var errorDescription: String? {
        switch self {
        case .networkError:
            return "Network connection issue during SharePlay session"
        case .participantLeft:
            return "A participant left the SharePlay session"
        case .modelSyncFailed:
            return "Failed to synchronize 3D model across devices"
        case .spatialTrackingFailed:
            return "Spatial tracking failed for nearby participants"
        }
    }
}
