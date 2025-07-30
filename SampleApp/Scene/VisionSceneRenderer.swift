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
}

class SimplePinchState {
    var lastRightPinchPosition: SIMD3<Float>?
    var lastLeftPinchPosition: SIMD3<Float>?
    var initialTwoHandDistance: Float?

    // Hysteresis + baseline
    var initialScale: Float?
    var isRightPinching = false
    var isLeftPinching  = false
    let pinchStartThreshold:  Float = 0.035   // start when ≤ 3.5 cm
    let pinchReleaseThreshold: Float = 0.045  // release when > 4.5 cm
    
    // Sensitivity settings
    let translationScale: Float = 3.0  // Increased for better movement
    
    func reset() {
        lastRightPinchPosition = nil
        lastLeftPinchPosition = nil
        initialTwoHandDistance = nil
        initialScale = nil
        isRightPinching = false
        isLeftPinching = false
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
class VisionSceneRenderer: ObservableObject {
    private static let log =
        Logger(subsystem: Bundle.main.bundleIdentifier!,
               category: "VisionSceneRenderer")

    let layerRenderer: LayerRenderer
    let device: MTLDevice
    let commandQueue: MTLCommandQueue

    var model: ModelIdentifier?
    var modelRenderer: (any ModelRenderer)?

    let inFlightSemaphore = DispatchSemaphore(value: Constants.maxSimultaneousRenders)

    @Published var camera = Camera()

    let arSession: ARKitSession
    let worldTracking: WorldTrackingProvider
    let handTrackingProvider: HandTrackingProvider
    
    var cameraSync: SharePlayCameraSync?
    var sharePlaySessionManager: SharePlaySessionManager?
    
    private var arTask: Task<Void, Never>?
    private var gestureState = SimplePinchState()
    private var frameCount = 0
    private var shouldStopRendering = false
    private var lastLoggedCameraPosition: SIMD3<Float>?
    private var lastLoggedCameraRotation: simd_quatf?
    private var lastLoggedCameraScale: Float?
    private var latestPresentationTime: TimeInterval = 0
    private var didLogFirstHandUpdate = false
    private var lastAppliedTranslation = SIMD3<Float>(repeating: 0)
    private let smoothing: Float = 0.2 // 0..1, higher = snappier
    private var currentModelURL: URL?

    init(_ layerRenderer: LayerRenderer) {
        self.layerRenderer = layerRenderer
        self.device = layerRenderer.device
        self.commandQueue = self.device.makeCommandQueue()!

        worldTracking = WorldTrackingProvider()
        handTrackingProvider = HandTrackingProvider()
        arSession = ARKitSession()
        
        setupCameraSync()
        setupOriginNotifications()
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
                camera.position = SIMD3<Float>(0, 0, -1.5)
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
            guard authStatus[.handTracking] == .allowed, authStatus[.worldSensing] == .allowed else {
                print("[GESTURE] ⚠️ Required permissions not granted. Cannot start AR session.")
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
                    do {
                        print("[GESTURE] 🔧 Starting ARSession with providers…")
                        while !Task.isCancelled {
                            try await session.run([world, hands])
                            print("[GESTURE] ⚠️ ARSession.run returned; waiting for layer to run, then restarting")
                            // Give the compositor time and avoid tight spinning
                            try? await Task.sleep(nanoseconds: 500_000_000) // 500 ms backoff
                        }
                    } catch {
                        print("[GESTURE] ❌ ARSession failed: \(error)")
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
                if frameCount % 30 == 0 {
                    print("[GESTURE] 👋 Hand \(hand.chirality) - isTracked: \(hand.isTracked)")
                }
                
                // Get current device anchor for transformation
                _ = worldTracking.queryDeviceAnchor(atTimestamp: latestPresentationTime)
                processHandPinch(hand)
                
            case .removed:
                print("[GESTURE] 👋 Hand removed: \(handAnchor.anchor.chirality)")
                resetHandState(handAnchor.anchor.chirality)
            }
        }
        
        print("[GESTURE] ⚠️ processAllAnchors loop ended - this should not happen during normal operation")
    }
    
    private func runRenderLoop() async {
        await renderLoop()
    }
    
    @MainActor
    private func processHandPinch(_ hand: HandAnchor) {
        print("[GESTURE] 🖐️ processHandPinch called for \(hand.chirality) hand")
        
        guard let skeleton = hand.handSkeleton else { 
            print("[GESTURE] ❌ No hand skeleton available for \(hand.chirality) hand")
            return 
        }
        
        let thumbTip = skeleton.joint(.thumbTip)
        let indexTip = skeleton.joint(.indexFingerTip)
        
        print("[GESTURE] 📍 Hand joints - thumbTip tracked: \(thumbTip.isTracked), indexTip tracked: \(indexTip.isTracked)")
        
        guard thumbTip.isTracked && indexTip.isTracked else {
            print("[GESTURE] ⚠️ Hand joints not tracked for \(hand.chirality) hand - resetting state")
            resetHandState(hand.chirality)
            return
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
        
        var active = (hand.chirality == .right)
            ? gestureState.isRightPinching
            : gestureState.isLeftPinching
        
        print("[GESTURE] 🤏 \(hand.chirality) hand pinch distance: \(pinchDistance), start: \(startT), release: \(releaseT), active: \(active)")
        
        if active {
            if pinchDistance > releaseT {
                print("[GESTURE] ❌ \(hand.chirality) hand released - resetting state")
                resetHandState(hand.chirality)    // released
            } else {
                print("[GESTURE] ✅ \(hand.chirality) hand still pinching - handling movement")
                handlePinchMovement(hand: hand)   // still pinching → translate
            }
        } else {
            if pinchDistance <= startT {
                // pinch just engaged
                print("[GESTURE] ✅ \(hand.chirality) hand pinch just engaged - starting movement")
                if hand.chirality == .right { gestureState.isRightPinching = true }
                else                         { gestureState.isLeftPinching = true }
                handlePinchMovement(hand: hand)   // start translating immediately
            } else {
                print("[GESTURE] ❌ \(hand.chirality) hand not pinching (distance too large)")
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
        
        switch hand.chirality {
        case .right:
            print("[GESTURE] ➡️ Processing right hand movement")
            if let lastPos = gestureState.lastRightPinchPosition {
                let delta = currentPinchPos - lastPos
                print("[GESTURE] 📊 Right hand delta: \(delta)")
                
                // Pure 3-axis translation only
                let translation = SIMD3<Float>(
                    delta.x * gestureState.translationScale,  // Left/Right
                    delta.y * gestureState.translationScale,  // Up/Down  
                    delta.z * gestureState.translationScale   // Forward/Back
                )
                
                let blended = lastAppliedTranslation + (translation - lastAppliedTranslation) * smoothing
                camera.translate(by: blended)
                lastAppliedTranslation = blended
                
                if frameCount % 60 == 0 {
                    print("[GESTURE] 👋 Right pinch move: \(translation)")
                }
            } else {
                print("[GESTURE] 📍 First right hand pinch position recorded")
            }
            gestureState.lastRightPinchPosition = currentPinchPos
            
        case .left:
            print("[GESTURE] ⬅️ Processing left hand movement")
            if let lastPos = gestureState.lastLeftPinchPosition {
                let delta = currentPinchPos - lastPos
                print("[GESTURE] 📊 Left hand delta: \(delta)")
                
                // Left hand also does pure 3-axis translation
                let translation = SIMD3<Float>(
                    delta.x * gestureState.translationScale,
                    delta.y * gestureState.translationScale,
                    delta.z * gestureState.translationScale
                )
                
                let blended = lastAppliedTranslation + (translation - lastAppliedTranslation) * smoothing
                camera.translate(by: blended)
                lastAppliedTranslation = blended
                
                if frameCount % 60 == 0 {
                    print("[GESTURE] 👋 Left pinch move: \(translation)")
                }
            } else {
                print("[GESTURE] 📍 First left hand pinch position recorded")
            }
            gestureState.lastLeftPinchPosition = currentPinchPos
            
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
            gestureState.initialTwoHandDistance = nil
            gestureState.initialScale = nil
            return
        }

        let currentDist = simd_distance(r, l)

        // Capture baseline once (on gesture start)
        if gestureState.initialTwoHandDistance == nil {
            gestureState.initialTwoHandDistance = max(currentDist, 0.001)
            gestureState.initialScale = camera.scale
            print("🤏 Two-handed scaling baseline set: distance=\(currentDist), scale=\(camera.scale)")
            return
        }

        guard let baseDist = gestureState.initialTwoHandDistance, baseDist > 0,
              let baseScale = gestureState.initialScale else { return }

        let ratio = currentDist / baseDist
        let targetScale = baseScale * ratio
        
        // Add mild smoothing to scale
        let t: Float = 0.2 // 0..1
        let smoothed = camera.scale + (targetScale - camera.scale) * t
        camera.setScale(smoothed)   // scale scene from baseline
        
        if frameCount % 30 == 0 {
            print("🤏 Two-handed scale: ratio=\(ratio), target=\(targetScale), smoothed=\(smoothed)")
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
    
    private func resetHandState(_ chirality: HandAnchor.Chirality) {
        switch chirality {
        case .right:
            gestureState.lastRightPinchPosition = nil
            gestureState.isRightPinching = false
        case .left:
            gestureState.lastLeftPinchPosition = nil
            gestureState.isLeftPinching = false
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
        
        let pose = SavedCameraPose(
            position: camera.position,
            rotation: camera.rotation,
            scale: camera.scale
        )
        
        PoseStore.save(pose: pose, for: url)
        
        // Post notification for UI feedback
        NotificationCenter.default.post(
            name: NSNotification.Name("OriginSaved"),
            object: nil
        )
    }
    
    private func loadSavedOrigin(for modelIdentifier: ModelIdentifier) -> SavedCameraPose? {
        guard case .gaussianSplat(let url) = modelIdentifier else { return nil }
        return PoseStore.load(for: url)
    }
    
    deinit {
        print("🗑️ VisionSceneRenderer deinit - stopping render loop")
        shouldStopRendering = true
        arTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}

#endif // os(visionOS)

