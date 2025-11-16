#if os(visionOS)

import CompositorServices
import Metal
import MetalSplatter
import os
import SampleBoxRenderer
import simd
import Spatial
import SwiftUI
import Combine
import ARKit
import ARUnderstanding

extension LayerRenderer.Clock.Instant.Duration {
    var timeInterval: TimeInterval {
        let secs = TimeInterval(components.seconds)
        let sub  = Double(components.attoseconds) / 1_000_000_000_000_000_000.0 // 1e18
        return secs + sub
    }
}

struct Camera {
    var position: SIMD3<Float>
    var rotation: simd_quatf
    var scale: Float
    
    init(position: SIMD3<Float> = SIMD3<Float>(0, 0, -1.5),
         rotation: simd_quatf = simd_quatf(angle: 0, axis: SIMD3<Float>(0, 1, 0)),
         scale: Float = 1.0) {
        self.position = position
        self.rotation = rotation
        self.scale = scale
    }
    
    var transform: simd_float4x4 {
        let translationMatrix = matrix4x4_translation(position.x, position.y, position.z)
        let rotationMatrix = simd_float4x4(rotation)
        let scaleMatrix = matrix4x4_scale(scale, scale, scale)
        
        return translationMatrix * rotationMatrix * scaleMatrix
    }
    
    mutating func translate(by delta: SIMD3<Float>) {
        position += delta
    }
    
    mutating func rotate(by quaternion: simd_quatf) {
        rotation = quaternion * rotation
    }
    
    mutating func setScale(_ newScale: Float) {
        scale = max(0.1, min(10.0, newScale)) // Clamp between 0.1 and 10.0
    }
    
    mutating func setPerspectiveCenteredScale(_ newScale: Float, around center: SIMD3<Float>) {
        let clampedScale = max(0.1, min(10.0, newScale))
        let scaleChange = clampedScale / scale
        
        // Calculate offset from center to current position
        let offset = position - center
        
        // Scale the offset and update position
        position = center + offset * scaleChange
        
        // Set the new scale
        scale = clampedScale
    }
}

class SimplePinchState {
    var lastRightPinchPosition: SIMD3<Float>?
    var lastLeftPinchPosition: SIMD3<Float>?
    var initialTwoHandDistance: Float?

    // Hysteresis + baseline
    var initialScale: Float?
    var isRightPinching = false
    var isLeftPinching  = false
    let pinchStartThreshold:  Float = 0.02  // m (2 cm)
    let pinchReleaseThreshold: Float = 0.025 // m (2.5 cm)
    
    // Joint tracking stability
    var rightTrackingFailures = 0
    var leftTrackingFailures = 0
    let maxTrackingFailures = 1200  // ~10 seconds at 120fps for joint recovery
    let maxTrackingFailuresNoHandAnchor = 3  // Strict limit when hand anchor itself is lost
    
    // Hand initialization tracking
    var rightHandSeen = false
    var leftHandSeen = false
    
    // Joint recovery state
    var rightJointsLost = false
    var leftJointsLost = false
    
    // Sensitivity settings
    let translationScale: Float = 3.0  // Increased for better movement

    // Pinch engage/release debouncing
    var rightReleaseOverFrames = 0
    var leftReleaseOverFrames = 0
    var rightEngageUnderFrames = 0
    var leftEngageUnderFrames = 0
    let engageFrames = 2       // require 2 consecutive frames under start threshold to engage
    let releaseFrames = 6      // require 6 consecutive frames over release threshold to disengage
    
    func reset() {
        lastRightPinchPosition = nil
        lastLeftPinchPosition = nil
        initialTwoHandDistance = nil
        initialScale = nil
        isRightPinching = false
        isLeftPinching = false
        rightTrackingFailures = 0
        leftTrackingFailures = 0
        rightHandSeen = false
        leftHandSeen = false
        rightJointsLost = false
        leftJointsLost = false
    }
}

// Matrix helper functions

func matrix4x4_scale(_ x: Float, _ y: Float, _ z: Float) -> simd_float4x4 {
    return simd_float4x4([
        SIMD4<Float>(x, 0, 0, 0),
        SIMD4<Float>(0, y, 0, 0),
        SIMD4<Float>(0, 0, z, 0),
        SIMD4<Float>(0, 0, 0, 1)
    ])
}

@MainActor
@Observable
class VisionSceneRenderer {
    private static let log =
        Logger(subsystem: Bundle.main.bundleIdentifier!,
               category: "VisionSceneRenderer")

    let layerRenderer: LayerRenderer
    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    var model: ModelIdentifier?
    var modelRenderer: (any ModelRenderer)?

    let inFlightSemaphore = DispatchSemaphore(value: Constants.maxSimultaneousRenders)

    var camera = Camera()

    let arSession: ARKitSession
    let worldTracking: WorldTrackingProvider
    let handTrackingProvider: HandTrackingProvider
    
    var cameraSync: SharePlayCameraSync?
    var sharePlaySessionManager: SharePlaySessionManager?
    var nearbyParticipantHandler: NearbyParticipantHandler?
    
    private var arTask: Task<Void, Never>?
    private var gestureState = SimplePinchState()
    private var frameCount = 0
    private var shouldStopRendering = false
    private var bothHandsInitialized = false
    private var lastLoggedCameraPosition: SIMD3<Float>?
    private var lastLoggedCameraRotation: simd_quatf?
    private var lastLoggedCameraScale: Float?
    private var latestPresentationTime: TimeInterval = 0
    private var didLogFirstHandUpdate = false
    private var lastAppliedTranslation = SIMD3<Float>(repeating: 0)
    private let smoothing: Float = 0.2 // 0..1, higher = snappier
    private var currentModelURL: URL?
    private var lastGestureLogTime: TimeInterval = 0
    private let gestureLogInterval: TimeInterval = 0.5 // Log every 0.5 seconds
    // Per-hand logging and freshness tracking
    private var lastGestureLogTimeRight: TimeInterval = 0
    private var lastGestureLogTimeLeft: TimeInterval = 0
    private var rightLastTrackedTime: TimeInterval = 0
    private var leftLastTrackedTime: TimeInterval = 0
    private let staleUpdateThreshold: TimeInterval = 0.35 // seconds; allow brief tracking flicker during active pinch
    private let maxPinchDeltaPerFrame: Float = 0.05 // meters; clamp outlier per-frame fingertip movement

    init(_ layerRenderer: LayerRenderer) {
        self.layerRenderer = layerRenderer
        self.device = layerRenderer.device
        self.commandQueue = self.device.makeCommandQueue()!

        worldTracking = WorldTrackingProvider()
        handTrackingProvider = HandTrackingProvider()
        arSession = ARKitSession()
        
        setupCameraSync()
        setupOriginNotifications()
        setupSpatialParticipantNotifications()
    }
    
    private func setupCameraSync() {
        // Listen for camera updates from SharePlay
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SharePlayCameraUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let userInfo = notification.userInfo,
                   let position = userInfo["position"] as? SIMD3<Float>,
                   let rotation = userInfo["rotation"] as? simd_quatf {
                    self?.camera.position = position
                    self?.camera.rotation = rotation
                }
            }
        }
    }
    
    private func setupOriginNotifications() {
        // Listen for set origin requests
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SetNewOrigin"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.setOriginForCurrentModel()
            }
        }
        
        // Listen for SharePlay origin sync requests
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SharePlaySyncOrigin"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.syncOriginToSharePlay()
            }
        }
        
        // Listen for shared origin updates from other participants
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ApplySharedOrigin"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                if let userInfo = notification.userInfo,
                   let position = userInfo["position"] as? SIMD3<Float>,
                   let rotation = userInfo["rotation"] as? simd_quatf,
                   let scale = userInfo["scale"] as? Float {
                    self?.applySharedOrigin(position: position, rotation: rotation, scale: scale)
                }
            }
        }
    }
    
    private func setupSpatialParticipantNotifications() {
        // Listen for spatial participant positioning requests
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("PositionContentForSpatialParticipant"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleSpatialParticipantPositioning(notification)
            }
        }
        
        // Listen for participant state updates for content positioning
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ParticipantStatesUpdated"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                self?.handleParticipantStatesUpdate(notification)
            }
        }
    }

    func load(_ model: ModelIdentifier?, cameraPosition: SIMD3<Float>? = nil, usePreprocessComputeShader: Bool = false) async throws {
        print("🎯 VisionSceneRenderer.load called with model: \(String(describing: model))")
        guard model != self.model else { 
            print("⚠️ Model is same as current model, skipping load")
            return 
        }
        self.model = model

        modelRenderer = nil
        switch model {
        case .gaussianSplat(let url):
            print("📊 Loading Gaussian Splat from URL: \(url)")
            print("📊 File exists: \(FileManager.default.fileExists(atPath: url.path))")
            
            // Store current model URL for origin management
            currentModelURL = url
            
            let splat = try SplatRenderer(device: device,
                                          colorFormat: layerRenderer.configuration.colorFormat,
                                          depthFormat: layerRenderer.configuration.depthFormat,
                                          sampleCount: 1,
                                          maxViewCount: layerRenderer.properties.viewCount,
                                          maxSimultaneousRenders: Constants.maxSimultaneousRenders)
            splat.usePreprocessComputeShader = usePreprocessComputeShader
            print("📊 Reading splat data...")
            try await splat.read(from: url)
            print("✅ Splat data loaded successfully") 
            print("📊 Splat point count: \(splat.splatCount)")
            modelRenderer = splat
            print("✅ Model renderer assigned")
            
            // Set camera position: custom -> saved origin -> default
            if let position = cameraPosition {
                camera.position = position
                print("📷 Using custom camera position: \(position)")
            } else if let savedPose = loadSavedOrigin(for: model!) {
                camera.position = savedPose.position
                camera.rotation = savedPose.rotation
                camera.scale = savedPose.scale
                print("📷 Using saved origin: pos=\(savedPose.position), rot=\(savedPose.rotation), scale=\(savedPose.scale)")
            } else {
                // Default position for gaussian splats
                camera.position = SIMD3<Float>(0, 0, -2.5)
                print("📷 Using default camera position: \(camera.position)")
            }
        case .sampleBox:
            print("📦 Loading sample box")
            
            // Clear model URL since this isn't a PLY file
            currentModelURL = nil
            
            do {
                modelRenderer = try SampleBoxRenderer(device: device,
                                                      colorFormat: layerRenderer.configuration.colorFormat,
                                                      depthFormat: layerRenderer.configuration.depthFormat,
                                                      sampleCount: 1,
                                                      maxViewCount: layerRenderer.properties.viewCount,
                                                      maxSimultaneousRenders: Constants.maxSimultaneousRenders)
                print("✅ Sample box renderer created")
            } catch {
                print("❌ Failed to create SampleBoxRenderer: \(error)")
                Self.log.error("Failed to create SampleBoxRenderer: \(error)")
                throw error
            }
            
            // Set custom camera position if provided
            if let position = cameraPosition {
                camera.position = position
            } else {
                // Default position for sample box
                camera.position = SIMD3<Float>(0, 0, -3.5)
            }
        case .none:
            print("⚠️ No model provided")
            currentModelURL = nil
            break
        }
        print("🎯 VisionSceneRenderer.load completed")
    }

    func startRenderLoop() {
        guard arTask == nil else { 
            print("[GESTURE] ⚠️ Render loop already started.")
            return
        }

        arTask = Task { @MainActor in
            self.shouldStopRendering = false
            // ➊ Wait for the layer to be running
            await waitUntilLayerRunning()
            print("[GESTURE]  Layer is running; starting ARKit providers")

            // First, request authorization from the user.
            print("[GESTURE] 🔐 Requesting ARKit permissions...")
            let permissions: [ARKitSession.AuthorizationType] = [.handTracking, .worldSensing]
            let authStatus = await arSession.requestAuthorization(for: permissions)
            print("[GESTURE] 📋 Authorization status: \(authStatus)")

            // If we don't have the necessary permissions, we can't proceed.
            let handTrackingStatus = authStatus[.handTracking]
            let worldSensingStatus = authStatus[.worldSensing]
            
            guard handTrackingStatus == .allowed, worldSensingStatus == .allowed else {
                print("[GESTURE] ⚠️ Required permissions not granted:")
                print("[GESTURE]   Hand tracking: \(String(describing: handTrackingStatus))")
                print("[GESTURE]   World sensing: \(String(describing: worldSensingStatus))")
                self.arTask = nil
                return
            }

            // Check if the providers are supported on the current device/environment.
            guard WorldTrackingProvider.isSupported else {
                print("[GESTURE] ❌ WorldTrackingProvider is not supported on this device.")
                self.arTask = nil
                return
            }
            guard HandTrackingProvider.isSupported else {
                print("[GESTURE] ❌ HandTrackingProvider is not supported on this device.")
                self.arTask = nil
                return
            }

            // Local strong references for ARKit session task
            let session = self.arSession
            let world   = self.worldTracking
            let hands   = self.handTrackingProvider

            // Use a TaskGroup to run the AR session, anchor processing, and render loop concurrently.
            await withTaskGroup(of: Void.self) { group in
                // Task 1: Run the ARSession. This task runs for the lifetime of the session.
                group.addTask {
                    var consecutiveFailures = 0
                    let maxFailures = 5
                    
                    do {
                        print("[GESTURE] 🔧 Starting ARSession with providers…")
                        while !Task.isCancelled && consecutiveFailures < maxFailures {
                            do {
                                try await session.run([world, hands])
                                consecutiveFailures = 0 // Reset on success
                                print("[GESTURE] ⚠️ ARSession.run returned; waiting for layer to run, then restarting")
                            } catch {
                                consecutiveFailures += 1
                                let backoffTime = min(pow(2.0, Double(consecutiveFailures)), 30.0) // Exponential backoff, max 30s
                                print("[GESTURE] ❌ ARSession failed (attempt \(consecutiveFailures)/\(maxFailures)): \(error)")
                                print("[GESTURE] ⏱️ Backing off for \(backoffTime) seconds")
                                try? await Task.sleep(nanoseconds: UInt64(backoffTime * 1_000_000_000))
                            }
                        }
                        
                        if consecutiveFailures >= maxFailures {
                            print("[GESTURE] 🛑 ARSession failed \(maxFailures) times consecutively. Stopping attempts.")
                        }
                    }
                }

                // Log session events (errors/interruptions)
                group.addTask {
                    for await event in session.events {
                        print("[GESTURE] ️ Session event: \(event)")
                    }
                }

                // Task 2: Process hand tracking updates.
                group.addTask { [weak self] in
                    await self?.processAllAnchors()
                }

                // Task 3: Run the render loop.
                group.addTask { [weak self] in
                    await self?.runRenderLoop()
                }
            }
        }
    }

    private func waitUntilLayerRunning() async {
        // Poll a few times per second until the compositor is running.
        while layerRenderer.state != .running {
            try? await Task.sleep(nanoseconds: 50_000_000) // 50 ms
            if shouldStopRendering { return }
        }
    }
    
    private func processAllAnchors() async {
        print("[GESTURE] 🔄 Starting processAllAnchors - waiting for hand tracking updates...")
        
        print("[GESTURE] 🎯 Starting to listen for hand anchor updates...")
        
        // Process hand updates from HandTrackingProvider
        for await handAnchor in handTrackingProvider.anchorUpdates {
            if Task.isCancelled { break }

            if !didLogFirstHandUpdate {
                print("[GESTURE] ✅ Receiving hand updates")
                didLogFirstHandUpdate = true
            }

            switch handAnchor.event {
            case .added, .updated:
                let hand = handAnchor.anchor
                if latestPresentationTime - lastGestureLogTime > gestureLogInterval {
                    print("[GESTURE] 👋 Hand \(hand.chirality) - isTracked: \(hand.isTracked) (Event: \(handAnchor.event))")
                    lastGestureLogTime = latestPresentationTime
                }
                
                if hand.isTracked {
                    // Track that we've seen this hand
                    switch hand.chirality {
                    case .right:
                        if !gestureState.rightHandSeen {
                            gestureState.rightHandSeen = true
                            print("[GESTURE] ✅ Right hand now tracked and initialized")
                        }
                    case .left:
                        if !gestureState.leftHandSeen {
                            gestureState.leftHandSeen = true
                            print("[GESTURE] ✅ Left hand now tracked and initialized")
                        }
                    @unknown default:
                        break
                    }
                    
                    // Check if both hands are now initialized
                    if !bothHandsInitialized && gestureState.rightHandSeen && gestureState.leftHandSeen {
                        bothHandsInitialized = true
                        print("[GESTURE] 🎉 Both hands initialized - enabling gesture processing")
                    }
                    
                    // Get current device anchor for transformation
                    _ = worldTracking.queryDeviceAnchor(atTimestamp: latestPresentationTime)
                    processHandPinch(hand)
                } else {
                    // Hand anchor itself is not tracked - use strict limit
                    if latestPresentationTime - lastGestureLogTime > gestureLogInterval {
                        print("[GESTURE] ⚠️ Hand \(hand.chirality) anchor is not tracked, skipping pinch processing.")
                        lastGestureLogTime = latestPresentationTime
                    }
                    
                    switch hand.chirality {
                    case .right:
                        gestureState.rightTrackingFailures += 1
                        if gestureState.rightTrackingFailures >= gestureState.maxTrackingFailuresNoHandAnchor {
                            print("[GESTURE] ❌ Right hand anchor lost - full reset")
                            resetHandState(hand.chirality, preserveInitialization: false)
                            // Check if we need to reset bothHandsInitialized
                            if !gestureState.leftHandSeen || !gestureState.rightHandSeen {
                                bothHandsInitialized = false
                                print("[GESTURE] 🔄 Hand lost - resetting initialization state")
                            }
                        } else {
                            print("[GESTURE] ⚠️ Right hand anchor not tracked (\(gestureState.rightTrackingFailures)/\(gestureState.maxTrackingFailuresNoHandAnchor))")
                        }
                    case .left:
                        gestureState.leftTrackingFailures += 1
                        if gestureState.leftTrackingFailures >= gestureState.maxTrackingFailuresNoHandAnchor {
                            print("[GESTURE] ❌ Left hand anchor lost - full reset")
                            resetHandState(hand.chirality, preserveInitialization: false)
                            // Check if we need to reset bothHandsInitialized
                            if !gestureState.leftHandSeen || !gestureState.rightHandSeen {
                                bothHandsInitialized = false
                                print("[GESTURE] 🔄 Hand lost - resetting initialization state")
                            }
                        } else {
                            print("[GESTURE] ⚠️ Left hand anchor not tracked (\(gestureState.leftTrackingFailures)/\(gestureState.maxTrackingFailuresNoHandAnchor))")
                        }
                    @unknown default:
                        break
                    }
                }
                
            case .removed:
                print("[GESTURE] 👋 Hand removed: \(handAnchor.anchor.chirality)")
                resetHandState(handAnchor.anchor.chirality, preserveInitialization: false)
                // Update initialization state when hand is completely removed
                switch handAnchor.anchor.chirality {
                case .right:
                    gestureState.rightHandSeen = false
                case .left:
                    gestureState.leftHandSeen = false
                @unknown default:
                    break
                }
                // Check if we need to reset bothHandsInitialized
                if !gestureState.leftHandSeen || !gestureState.rightHandSeen {
                    bothHandsInitialized = false
                    print("[GESTURE] 🔄 Hand removed - resetting initialization state")
                }
            }
        }
        
        print("[GESTURE] ⚠️ processAllAnchors loop ended - this should not happen during normal operation")
    }
    
    private func runRenderLoop() async {
        await renderLoop()
    }
    
    @MainActor
    private func processHandPinch(_ hand: HandAnchor) {
        if latestPresentationTime - lastGestureLogTime > gestureLogInterval {
            print("[GESTURE] 🖐️ processHandPinch called for \(hand.chirality) hand")
            lastGestureLogTime = latestPresentationTime
        }
        
        guard let skeleton = hand.handSkeleton else { 
            print("[GESTURE] ❌ No hand skeleton available for \(hand.chirality) hand")
            return 
        }
        
        // Prefer both hands initialized, but allow single-hand translation before that.
        if !bothHandsInitialized {
            if latestPresentationTime - lastGestureLogTime > gestureLogInterval {
                print("[GESTURE] ⏳ Both hands not yet initialized — allowing single-hand translation but suppressing two-hand scaling.")
                lastGestureLogTime = latestPresentationTime
            }
            // We intentionally DO NOT return here; translation can proceed for the active hand.
        }
        
        let thumbTip = skeleton.joint(.thumbTip)
        let indexTip = skeleton.joint(.indexFingerTip)
        
        // Enhanced logging for joint tracking
        let jointsTracked = thumbTip.isTracked && indexTip.isTracked
        if !jointsTracked && latestPresentationTime - lastGestureLogTime > gestureLogInterval {
            print("[GESTURE] 🔍 \(hand.chirality) hand: anchor tracked=true, thumb tracked=\(thumbTip.isTracked), index tracked=\(indexTip.isTracked)")
            lastGestureLogTime = latestPresentationTime
        }
        
        guard jointsTracked else {
            // Handle joint tracking loss with recovery
            switch hand.chirality {
            case .right:
                // If we are actively pinching but the joints have been stale for too long, reset immediately to avoid using stale data
                let now = latestPresentationTime
                if gestureState.isRightPinching && (now - rightLastTrackedTime) > staleUpdateThreshold {
                    print("[GESTURE] ⏰ Right joints stale for \(now - rightLastTrackedTime)s during active pinch — resetting right hand state.")
                    resetHandState(.right)
                }
                if !gestureState.rightJointsLost {
                    gestureState.rightJointsLost = true
                    print("[GESTURE] ⚠️ Right hand joints lost but hand still visible - entering recovery mode")
                }
                gestureState.rightTrackingFailures += 1
                if gestureState.rightTrackingFailures >= gestureState.maxTrackingFailures {
                    print("[GESTURE] ⏰ Right hand joints lost for >10 seconds - resetting state")
                    resetHandState(hand.chirality)
                } else if gestureState.rightTrackingFailures % 120 == 0 { // Log every ~1 second
                    let secondsLost = gestureState.rightTrackingFailures / 120
                    print("[GESTURE] ⏳ Right hand joints lost for \(secondsLost)s - waiting for recovery...")
                }
            case .left:
                // If we are actively pinching but the joints have been stale for too long, reset immediately to avoid using stale data
                let now = latestPresentationTime
                if gestureState.isLeftPinching && (now - leftLastTrackedTime) > staleUpdateThreshold {
                    print("[GESTURE] ⏰ Left joints stale for \(now - leftLastTrackedTime)s during active pinch — resetting left hand state.")
                    resetHandState(.left)
                }
                if !gestureState.leftJointsLost {
                    gestureState.leftJointsLost = true
                    print("[GESTURE] ⚠️ Left hand joints lost but hand still visible - entering recovery mode")
                }
                gestureState.leftTrackingFailures += 1
                if gestureState.leftTrackingFailures >= gestureState.maxTrackingFailures {
                    print("[GESTURE] ⏰ Left hand joints lost for >10 seconds - resetting state")
                    resetHandState(hand.chirality)
                } else if gestureState.leftTrackingFailures % 120 == 0 { // Log every ~1 second
                    let secondsLost = gestureState.leftTrackingFailures / 120
                    print("[GESTURE] ⏳ Left hand joints lost for \(secondsLost)s - waiting for recovery...")
                }
            @unknown default:
                break
            }
            return
        }
        
        // Joints are tracked - check if we're recovering
        switch hand.chirality {
        case .right:
            if gestureState.rightJointsLost {
                print("[GESTURE] ✅ Right hand joints recovered after \(gestureState.rightTrackingFailures) frames!")
                gestureState.rightJointsLost = false
            }
            gestureState.rightTrackingFailures = 0
            rightLastTrackedTime = latestPresentationTime
        case .left:
            if gestureState.leftJointsLost {
                print("[GESTURE] ✅ Left hand joints recovered after \(gestureState.leftTrackingFailures) frames!")
                gestureState.leftJointsLost = false
            }
            gestureState.leftTrackingFailures = 0
            leftLastTrackedTime = latestPresentationTime
        @unknown default:
            break
        }
        
        // Check if pinching with hysteresis
        let thumbPos = SIMD3<Float>(thumbTip.anchorFromJointTransform.columns.3.x,
                                   thumbTip.anchorFromJointTransform.columns.3.y,
                                   thumbTip.anchorFromJointTransform.columns.3.z)
        let indexPos = SIMD3<Float>(indexTip.anchorFromJointTransform.columns.3.x,
                                   indexTip.anchorFromJointTransform.columns.3.y,
                                   indexTip.anchorFromJointTransform.columns.3.z)
        
        let pinchDistance = simd_distance(thumbPos, indexPos)
        let startT = gestureState.pinchStartThreshold
        let releaseT = gestureState.pinchReleaseThreshold
        
        let active = (hand.chirality == .right)
            ? gestureState.isRightPinching
            : gestureState.isLeftPinching
        
        if latestPresentationTime - lastGestureLogTime > gestureLogInterval {
            print("[GESTURE] 🤏 \(hand.chirality) hand pinch distance: \(pinchDistance), start: \(startT), release: \(releaseT), active: \(active)")
            lastGestureLogTime = latestPresentationTime
        }
        
        if active {
            if pinchDistance > releaseT {
                // Debounce release: require several consecutive frames over threshold
                switch hand.chirality {
                case .right:
                    gestureState.rightReleaseOverFrames += 1
                    if gestureState.rightReleaseOverFrames >= gestureState.releaseFrames {
                        print("[GESTURE] 🔓 right hand RELEASED (distance: \(pinchDistance*100)cm > \(releaseT*100)cm for \(gestureState.rightReleaseOverFrames) frames) - resetting state")
                        gestureState.rightReleaseOverFrames = 0
                        resetHandState(.right)
                    } else {
                        // Don't apply movement or reset last position; wait for stability
                        if latestPresentationTime - lastGestureLogTime > gestureLogInterval {
                            print("[GESTURE] ⏳ right hand potential release (\(gestureState.rightReleaseOverFrames)/\(gestureState.releaseFrames)) — holding state")
                            lastGestureLogTime = latestPresentationTime
                        }
                    }
                case .left:
                    gestureState.leftReleaseOverFrames += 1
                    if gestureState.leftReleaseOverFrames >= gestureState.releaseFrames {
                        print("[GESTURE] 🔓 left hand RELEASED (distance: \(pinchDistance*100)cm > \(releaseT*100)cm for \(gestureState.leftReleaseOverFrames) frames) - resetting state")
                        gestureState.leftReleaseOverFrames = 0
                        resetHandState(.left)
                    } else {
                        if latestPresentationTime - lastGestureLogTime > gestureLogInterval {
                            print("[GESTURE] ⏳ left hand potential release (\(gestureState.leftReleaseOverFrames)/\(gestureState.releaseFrames)) — holding state")
                            lastGestureLogTime = latestPresentationTime
                        }
                    }
                @unknown default: break
                }
            } else {
                // Still under release threshold — reset counters and apply movement
                switch hand.chirality {
                case .right: gestureState.rightReleaseOverFrames = 0
                case .left:  gestureState.leftReleaseOverFrames = 0
                @unknown default: break
                }
                if latestPresentationTime - lastGestureLogTime > gestureLogInterval {
                    print("[GESTURE] ✅ \(hand.chirality) hand still pinching (distance: \(pinchDistance*100)cm) — handling movement")
                    lastGestureLogTime = latestPresentationTime
                }
                handlePinchMovement(hand: hand)
            }
        } else {
            if pinchDistance <= startT {
                // Debounce engage: require a couple frames under start threshold
                var ready = false
                switch hand.chirality {
                case .right:
                    gestureState.rightEngageUnderFrames += 1
                    ready = gestureState.rightEngageUnderFrames >= gestureState.engageFrames
                case .left:
                    gestureState.leftEngageUnderFrames += 1
                    ready = gestureState.leftEngageUnderFrames >= gestureState.engageFrames
                @unknown default: break
                }
                if ready {
                    print("[GESTURE] 🔒 \(hand.chirality) hand PINCH ENGAGED (distance: \(pinchDistance*100)cm ≤ \(startT*100)cm) - starting movement")
                    if hand.chirality == .right { gestureState.isRightPinching = true; gestureState.rightEngageUnderFrames = 0 }
                    else                         { gestureState.isLeftPinching  = true; gestureState.leftEngageUnderFrames  = 0 }
                    handlePinchMovement(hand: hand)
                } else {
                    if latestPresentationTime - lastGestureLogTime > gestureLogInterval {
                        print("[GESTURE] ⏳ \(hand.chirality) hand potential engage (\(hand.chirality == .right ? gestureState.rightEngageUnderFrames : gestureState.leftEngageUnderFrames)/\(gestureState.engageFrames))")
                        lastGestureLogTime = latestPresentationTime
                    }
                }
            } else {
                // Not close enough to engage — reset engage counters
                switch hand.chirality {
                case .right: gestureState.rightEngageUnderFrames = 0
                case .left:  gestureState.leftEngageUnderFrames = 0
                @unknown default: break
                }
                if latestPresentationTime - lastGestureLogTime > gestureLogInterval {
                    print("[GESTURE] ❌ \(hand.chirality) hand not pinching (distance: \(pinchDistance*100)cm > \(startT*100)cm)")
                    lastGestureLogTime = latestPresentationTime
                }
            }
        }
        
        // After per-hand updates:
        checkTwoHandedScaling()
    }
    
    @MainActor
    private func handlePinchMovement(hand: HandAnchor) {
        print("[GESTURE] 🎯 handlePinchMovement called for \(hand.chirality) hand")

        let currentPinchPos = getPinchWorldPosition(hand: hand)
        print("[GESTURE] 📍 Current pinch position: \(currentPinchPos)")
        let now = latestPresentationTime

        switch hand.chirality {
        case .right:
            if now - lastGestureLogTimeRight > gestureLogInterval {
                print("[GESTURE] ➡️ Processing right hand movement")
                lastGestureLogTimeRight = now
            }
            if let lastPos = gestureState.lastRightPinchPosition {
                var delta = currentPinchPos - lastPos
                let mag = simd_length(delta)
                if mag > maxPinchDeltaPerFrame {
                    let scale = maxPinchDeltaPerFrame / max(mag, 1e-6)
                    delta *= scale
                    if now - lastGestureLogTimeRight > gestureLogInterval {
                        print("[GESTURE] 🚧 Right delta clamped from |\(mag)|m to \(maxPinchDeltaPerFrame)m: \(delta)")
                        lastGestureLogTimeRight = now
                    }
                }
                if now - lastGestureLogTimeRight > gestureLogInterval {
                    print("[GESTURE] 📊 Right hand delta: \(delta)")
                    lastGestureLogTimeRight = now
                }
                let translation = SIMD3<Float>(
                    delta.x * gestureState.translationScale,
                    delta.y * gestureState.translationScale,
                    delta.z * gestureState.translationScale
                )
                let blended = lastAppliedTranslation + (translation - lastAppliedTranslation) * smoothing
                camera.translate(by: blended)
                lastAppliedTranslation = blended
                if now - lastGestureLogTimeRight > gestureLogInterval {
                    print("[GESTURE] 👋 Right pinch move: \(translation)")
                    lastGestureLogTimeRight = now
                }
                // Adopt clamped position (prevents spike adoption)
                gestureState.lastRightPinchPosition = lastPos + delta
            } else {
                print("[GESTURE] 📍 First right hand pinch position recorded")
                gestureState.lastRightPinchPosition = currentPinchPos
            }

        case .left:
            if now - lastGestureLogTimeLeft > gestureLogInterval {
                print("[GESTURE] ⬅️ Processing left hand movement")
                lastGestureLogTimeLeft = now
            }
            if let lastPos = gestureState.lastLeftPinchPosition {
                var delta = currentPinchPos - lastPos
                let mag = simd_length(delta)
                if mag > maxPinchDeltaPerFrame {
                    let scale = maxPinchDeltaPerFrame / max(mag, 1e-6)
                    delta *= scale
                    if now - lastGestureLogTimeLeft > gestureLogInterval {
                        print("[GESTURE] 🚧 Left delta clamped from |\(mag)|m to \(maxPinchDeltaPerFrame)m: \(delta)")
                        lastGestureLogTimeLeft = now
                    }
                }
                if now - lastGestureLogTimeLeft > gestureLogInterval {
                    print("[GESTURE] 📊 Left hand delta: \(delta)")
                    lastGestureLogTimeLeft = now
                }
                let translation = SIMD3<Float>(
                    delta.x * gestureState.translationScale,
                    delta.y * gestureState.translationScale,
                    delta.z * gestureState.translationScale
                )
                let blended = lastAppliedTranslation + (translation - lastAppliedTranslation) * smoothing
                camera.translate(by: blended)
                lastAppliedTranslation = blended
                if now - lastGestureLogTimeLeft > gestureLogInterval {
                    print("[GESTURE] 👋 Left pinch move: \(translation)")
                    lastGestureLogTimeLeft = now
                }
                gestureState.lastLeftPinchPosition = lastPos + delta
            } else {
                print("[GESTURE] 📍 First left hand pinch position recorded")
                gestureState.lastLeftPinchPosition = currentPinchPos
            }

        @unknown default:
            print("[GESTURE] ❓ Unknown hand chirality: \(hand.chirality)")
            break
        }
    }
    
    @MainActor
    private func checkTwoHandedScaling() {
        // Need both hands actively pinching and positions
        guard gestureState.isRightPinching,
              gestureState.isLeftPinching,
              let r = gestureState.lastRightPinchPosition,
              let l = gestureState.lastLeftPinchPosition else {
            // Log why two-handed scaling isn't happening
            if latestPresentationTime - lastGestureLogTime > gestureLogInterval * 2 { // Less frequent for this one
                print("[GESTURE] 🤏 Two-handed scaling not active: right=\(gestureState.isRightPinching), left=\(gestureState.isLeftPinching), rightPos=\(gestureState.lastRightPinchPosition != nil), leftPos=\(gestureState.lastLeftPinchPosition != nil)")
                lastGestureLogTime = latestPresentationTime
            }
            gestureState.initialTwoHandDistance = nil
            gestureState.initialScale = nil
            return
        }

        // Require recent updates from both hands to avoid scaling against stale positions
        let now = latestPresentationTime
        if (now - rightLastTrackedTime) > staleUpdateThreshold || (now - leftLastTrackedTime) > staleUpdateThreshold {
            if latestPresentationTime - lastGestureLogTime > gestureLogInterval * 2 {
                print("[GESTURE] ⏸️ Two-handed scaling paused due to stale hand data (right age=\(now - rightLastTrackedTime)s, left age=\(now - leftLastTrackedTime)s)")
                lastGestureLogTime = latestPresentationTime
            }
            gestureState.initialTwoHandDistance = nil
            gestureState.initialScale = nil
            return
        }

        let currentDist = simd_distance(r, l)

        // Capture baseline once (on gesture start)
        if gestureState.initialTwoHandDistance == nil {
            gestureState.initialTwoHandDistance = max(currentDist, 0.001)
            gestureState.initialScale = camera.scale
            print("[GESTURE] 🎯 TWO-HANDED SCALING STARTED: baseline distance=\(currentDist*100)cm, baseline scale=\(camera.scale)")
            return
        }

        guard let baseDist = gestureState.initialTwoHandDistance, baseDist > 0,
              let baseScale = gestureState.initialScale else { return }

        let ratio = currentDist / baseDist
        let targetScale = baseScale * ratio
        
        // Add mild smoothing to scale
        let t: Float = 0.2 // 0..1
        let smoothed = camera.scale + (targetScale - camera.scale) * t
        
        // Implement perspective-centered scaling
        // Instead of just setting scale, we need to scale around the user's viewpoint
        setPerspectiveCenteredScale(smoothed)
        
        if latestPresentationTime - lastGestureLogTime > gestureLogInterval {
            print("[GESTURE] 🎯 Two-handed ZOOM: currentDist=\(currentDist*100)cm, ratio=\(ratio), target=\(targetScale), smoothed=\(smoothed)")
            lastGestureLogTime = latestPresentationTime
        }
    }
    
    @MainActor
    func syncCameraState() {
        // Send camera update through SharePlay
        cameraSync?.sendCameraUpdate(position: camera.position, rotation: camera.rotation)
    }
    
    private func getPinchWorldPosition(hand: HandAnchor) -> SIMD3<Float> {
        guard let skeleton = hand.handSkeleton else {
            return SIMD3<Float>(0, 0, 0)
        }
        
        let thumbTip = skeleton.joint(.thumbTip)
        let indexTip = skeleton.joint(.indexFingerTip)
        
        // Midpoint between thumb and index
        let thumbPos = thumbTip.anchorFromJointTransform.columns.3
        let indexPos = indexTip.anchorFromJointTransform.columns.3
        let pinchPos = (SIMD3<Float>(thumbPos.x, thumbPos.y, thumbPos.z) + 
                       SIMD3<Float>(indexPos.x, indexPos.y, indexPos.z)) / 2.0
        
        // Transform to world space
        let handWorldTransform = hand.originFromAnchorTransform
        let worldPos = handWorldTransform * SIMD4<Float>(pinchPos.x, pinchPos.y, pinchPos.z, 1.0)
        
        return SIMD3<Float>(worldPos.x, worldPos.y, worldPos.z)
    }
    
    private func resetHandState(_ chirality: HandAnchor.Chirality, preserveInitialization: Bool = true) {
        switch chirality {
        case .right:
            gestureState.lastRightPinchPosition = nil
            gestureState.isRightPinching = false
            gestureState.rightTrackingFailures = 0
            gestureState.rightJointsLost = false
            if !preserveInitialization {
                gestureState.rightHandSeen = false
            }
        case .left:
            gestureState.lastLeftPinchPosition = nil
            gestureState.isLeftPinching = false
            gestureState.leftTrackingFailures = 0
            gestureState.leftJointsLost = false
            if !preserveInitialization {
                gestureState.leftHandSeen = false
            }
        @unknown default:
            break
        }
        // Clear two-hand baseline whenever either hand releases
        gestureState.initialTwoHandDistance = nil
        gestureState.initialScale = nil
    }

    private func viewports(drawable: LayerRenderer.Drawable, deviceAnchor: DeviceAnchor?) -> [ModelRendererViewportDescriptor] {
        // Turn common 3D GS PLY files rightside-up. This isn't generally meaningful, it just
        // happens to be a useful default for the most common datasets at the moment.
        let commonUpCalibration = matrix4x4_rotation(radians: .pi, axis: SIMD3<Float>(0, 0, 1))

        let simdDeviceAnchor = deviceAnchor?.originFromAnchorTransform ?? matrix_identity_float4x4

        return drawable.views.enumerated().map { (index, view) in
            let userViewpointMatrix = (simdDeviceAnchor * view.transform).inverse
            let projectionMatrix = drawable.computeProjection(viewIndex: index)
            let screenSize = SIMD2(x: Int(view.textureMap.viewport.width),
                                   y: Int(view.textureMap.viewport.height))
            return ModelRendererViewportDescriptor(viewport: view.textureMap.viewport,
                                                   projectionMatrix: projectionMatrix,
                                                   viewMatrix: userViewpointMatrix * camera.transform * commonUpCalibration,
                                                   screenSize: screenSize)
        }
    }


    func renderFrame() {
        guard let frame = layerRenderer.queryNextFrame() else { 
            if frameCount == 0 {
                print("⚠️ No frame available from layerRenderer")
            }
            return 
        }

        frame.startUpdate()
        frame.endUpdate()

        guard let timing = frame.predictTiming() else { 
            if frameCount == 0 {
                print("⚠️ No timing available from frame")
            }
            return 
        }
        LayerRenderer.Clock().wait(until: timing.optimalInputTime)

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            fatalError("Failed to create command buffer")
        }

        let drawables = frame.queryDrawables()
        guard let drawable = drawables.first else { 
            if frameCount < 5 {
                print("⚠️ No drawable available (frame \(frameCount))")
            }
            return 
        }

        _ = inFlightSemaphore.wait(timeout: DispatchTime.distantFuture)

        frame.startSubmission()

        let time = LayerRenderer.Clock.Instant.epoch.duration(to: drawable.frameTiming.presentationTime).timeInterval
        self.latestPresentationTime = time
        let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: time)
        drawable.deviceAnchor = deviceAnchor
        
        // Hand gesture processing is handled asynchronously in processAllAnchors()

        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
            semaphore.signal()
        }

        let viewports = self.viewports(drawable: drawable, deviceAnchor: deviceAnchor)

        frameCount += 1
        
        // Log camera changes
        let cameraChanged = lastLoggedCameraPosition != camera.position ||
                          lastLoggedCameraRotation != camera.rotation ||
                          lastLoggedCameraScale != camera.scale
        
        if cameraChanged {
            print("[GESTURE] 📷 Camera changed at frame \(frameCount):")
            print("[GESTURE]   Position: \(camera.position)")
            print("[GESTURE]   Rotation: \(camera.rotation)")
            print("[GESTURE]   Scale: \(camera.scale)")
            lastLoggedCameraPosition = camera.position
            lastLoggedCameraRotation = camera.rotation
            lastLoggedCameraScale = camera.scale
        }
        
        // Log initial frame info
        if frameCount == 1 {
            print("🎬 First frame rendered")
            print("  Model: \(modelRenderer != nil ? "Loaded" : "Not loaded")")
            if let splat = modelRenderer as? SplatRenderer {
                print("  Splat points: \(splat.splatCount)")
            }
        }
        
        do {
            if let renderer = modelRenderer {
                try renderer.render(viewports: viewports,
                                   colorTexture: drawable.colorTextures[0],
                                   colorStoreAction: .store,
                                   depthTexture: drawable.depthTextures[0],
                                   rasterizationRateMap: drawable.rasterizationRateMaps.first,
                                   renderTargetArrayLength: layerRenderer.configuration.layout == .layered ? drawable.views.count : 1,
                                   to: commandBuffer)
            } else {
                if frameCount == 1 {
                    print("⚠️ No model renderer available to render")
                }
            }
        } catch {
            print("❌ Render error: \(error)")
            Self.log.error("Unable to render scene: \(error.localizedDescription)")
        }

        drawable.encodePresent(commandBuffer: commandBuffer)

        commandBuffer.commit()

        frame.endSubmission()
    }

    func renderLoop() async {
        var loopCount = 0
        while !shouldStopRendering {
            loopCount += 1
            
            if layerRenderer.state == .invalidated {
                Self.log.warning("Layer is invalidated")
                return
            } else if layerRenderer.state == .paused {
                layerRenderer.waitUntilRunning()
                continue
            } else {
                autoreleasepool {
                    self.renderFrame()
                }
                await Task.yield()
            }
        }
    }
    
    func stopRenderLoop() {
        guard arTask != nil else { return }
        print("🛑 Stopping render loop")
        shouldStopRendering = true
        arTask?.cancel()
        arTask = nil
    }
    
    // MARK: - Origin Management
    
    @MainActor
    func setOriginForCurrentModel() {
        guard let url = currentModelURL else {
            print("⚠️ No current model URL to save origin for")
            return
        }
        
        print("📍 Setting origin for model URL: \(url)")
        print("📍 URL type: \(url.isFileURL ? "File URL" : "Other URL")")
        print("📍 URL path: \(url.path)")
        print("📍 Is bundle resource: \(url.path.contains(Bundle.main.bundlePath))")
        
        let pose = SavedCameraPose(
            position: camera.position,
            rotation: camera.rotation,
            scale: camera.scale
        )
        
        print("📍 Saving pose - position: \(pose.position), rotation: \(pose.rotation), scale: \(pose.scale)")
        
        PoseStore.save(pose: pose, for: url)
        
        // Post notification for UI feedback
        NotificationCenter.default.post(
            name: NSNotification.Name("OriginSaved"),
            object: nil
        )
    }
    
    @MainActor
    private func syncOriginToSharePlay() {
        print("[SHAREPLAY] 📍 Syncing current origin to SharePlay participants")
        
        // Send current camera state to SharePlay
        sharePlaySessionManager?.sendOriginUpdate(
            position: camera.position,
            rotation: camera.rotation,
            scale: camera.scale
        )
    }
    
    @MainActor
    private func applySharedOrigin(position: SIMD3<Float>, rotation: simd_quatf, scale: Float) {
        print("[SHAREPLAY] 📍 Applying shared origin: pos=\(position), rot=\(rotation), scale=\(scale)")
        
        camera.position = position
        camera.rotation = rotation
        camera.scale = scale
        
        // Save this as the new origin for the current model
        if let url = currentModelURL {
            let pose = SavedCameraPose(
                position: position,
                rotation: rotation,
                scale: scale
            )
            PoseStore.save(pose: pose, for: url)
        }
        
        // Show confirmation message
        NotificationCenter.default.post(
            name: NSNotification.Name("OriginSaved"),
            object: nil
        )
    }
    
    private func loadSavedOrigin(for modelIdentifier: ModelIdentifier) -> SavedCameraPose? {
        guard case .gaussianSplat(let url) = modelIdentifier else { 
            print("📍 loadSavedOrigin: Not a gaussian splat model")
            return nil 
        }
        
        print("📍 Loading saved origin for URL: \(url)")
        print("📍 URL path: \(url.path)")
        
        let savedPose = PoseStore.load(for: url)
        if let pose = savedPose {
            print("📍 Found saved origin - position: \(pose.position), rotation: \(pose.rotation), scale: \(pose.scale)")
        } else {
            print("📍 No saved origin found for this model")
        }
        
        return savedPose
    }
    
    // MARK: - Perspective-Centered Scaling
    
    @MainActor
    private func setPerspectiveCenteredScale(_ newScale: Float) {
        // Calculate the center point for scaling (user's perspective)
        // In visionOS, the user's viewpoint is effectively at the camera position
        // We want to scale around a point in front of the user at a reasonable distance
        
        // Calculate the camera's forward direction using its rotation
        let forwardInCameraSpace = SIMD3<Float>(0, 0, -2.0) // 2 meters forward in camera space
        let rotationMatrix = simd_float4x4(camera.rotation)
        let forwardVector = rotationMatrix * SIMD4<Float>(forwardInCameraSpace, 0)
        let forwardInWorldSpace = SIMD3<Float>(forwardVector.x, forwardVector.y, forwardVector.z)
        
        // Scaling center is in front of the camera in the direction it's facing
        let scalingCenter = camera.position + forwardInWorldSpace
        
        // Apply perspective-centered scaling
        camera.setPerspectiveCenteredScale(newScale, around: scalingCenter)
        
        if latestPresentationTime - lastGestureLogTime > gestureLogInterval {
            print("[GESTURE] 🎯 Perspective-centered scale: \(newScale), center: \(scalingCenter)")
            lastGestureLogTime = latestPresentationTime
        }
    }
    
    // MARK: - Spatial Participant Positioning
    
    @MainActor
    private func handleSpatialParticipantPositioning(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let participantID = userInfo["participantID"] as? String else {
            print("[SPATIAL] ⚠️ Invalid spatial participant positioning notification")
            return
        }
        
        print("[SPATIAL] ✨ Handling spatial participant positioning for \(participantID)")
        
        // For now, we'll log the positioning request
        // In a more advanced implementation, you might adjust the camera or content positioning
        // based on the participant's spatial presence
        
        if let pose = userInfo["pose"] {
            print("[SPATIAL] 📍 Participant \(participantID) pose: \(pose)")
            
            // Example: Adjust content positioning based on spatial participants
            adjustContentForSpatialParticipants()
        }
    }
    
    @MainActor
    private func handleParticipantStatesUpdate(_ notification: Notification) {
        guard let nearbyHandler = nearbyParticipantHandler else { return }
        
        let spatialParticipants = nearbyHandler.getSpatialParticipants()
        let visualizationData = nearbyHandler.getParticipantVisualizationData()
        
        print("[SPATIAL] 🔄 Participant states updated: \(spatialParticipants.count) spatial participants")
        
        // Log participant positions for debugging
        for data in visualizationData {
            print("[SPATIAL]   👤 \(data.id): pos=\(data.position), nearby=\(data.isNearby), spatial=\(data.isSpatial)")
        }
        
        // Adjust content based on spatial participant distribution
        if !spatialParticipants.isEmpty {
            adjustContentForSpatialParticipants()
        }
    }
    
    @MainActor
    private func adjustContentForSpatialParticipants() {
        guard let nearbyHandler = nearbyParticipantHandler,
              let optimalPosition = nearbyHandler.getOptimalContentPosition() else {
            return
        }
        
        print("[SPATIAL] 🎯 Adjusting content for spatial participants")
        
        // Extract position from the optimal content position matrix
        let optimalPos = SIMD3<Float>(
            optimalPosition.columns.3.x,
            optimalPosition.columns.3.y,
            optimalPosition.columns.3.z
        )
        
        // Subtle adjustment of camera position to account for spatial participants
        // This creates a more centered viewing experience when multiple people are present
        let currentPos = camera.position
        let adjustment = (optimalPos - currentPos) * 0.1 // Gentle adjustment factor
        
        // Only apply adjustment if it's not too drastic
        let adjustmentMagnitude = simd_length(adjustment)
        if adjustmentMagnitude > 0.01 && adjustmentMagnitude < 2.0 {
            camera.position = currentPos + adjustment
            print("[SPATIAL] 📷 Adjusted camera position by \(adjustment) for spatial participants")
            
            // Sync the adjusted camera position if SharePlay is active
            syncCameraState()
        }
    }
    
    @MainActor
    func configureSpatialParticipantHandler(_ handler: NearbyParticipantHandler) {
        print("[SPATIAL] 🔧 Configuring spatial participant handler")
        nearbyParticipantHandler = handler
    }
    
    @MainActor
    deinit {
        print("🗑️ VisionSceneRenderer deinit - stopping render loop")
        shouldStopRendering = true
        arTask?.cancel()
        
        // Remove all notification observers
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("SharePlayCameraUpdate"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("SetNewOrigin"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("SharePlaySyncOrigin"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("ApplySharedOrigin"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("PositionContentForSpatialParticipant"), object: nil)
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name("ParticipantStatesUpdated"), object: nil)
    }
}

#endif // os(visionOS)
