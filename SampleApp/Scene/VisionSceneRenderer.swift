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
        let nanoseconds = TimeInterval(components.attoseconds / 1_000_000_000)
        return TimeInterval(components.seconds) + (nanoseconds / TimeInterval(NSEC_PER_SEC))
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
    
    // Sensitivity settings
    let translationScale: Float = 3.0  // Increased for better movement
    let pinchThreshold: Float = 0.025  // 2.5cm for pinch detection
    
    func reset() {
        lastRightPinchPosition = nil
        lastLeftPinchPosition = nil
        initialTwoHandDistance = nil
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
    
    var cameraSync: SharePlayCameraSync?
    var sharePlaySessionManager: SharePlaySessionManager?
    
    private var arTask: Task<Void, Never>?
    private var gestureState = SimplePinchState()
    private var currentDeviceAnchor: CapturedDeviceAnchor?
    private var frameCount = 0
    private var shouldStopRendering = false

    init(_ layerRenderer: LayerRenderer) {
        self.layerRenderer = layerRenderer
        self.device = layerRenderer.device
        self.commandQueue = self.device.makeCommandQueue()!

        worldTracking = WorldTrackingProvider()
        arSession = ARKitSession()
        
        setupCameraSync()
    }
    
    private func setupCameraSync() {
        // Listen for camera updates from SharePlay
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("SharePlayCameraUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            if let userInfo = notification.userInfo,
               let position = userInfo["position"] as? SIMD3<Float>,
               let rotation = userInfo["rotation"] as? simd_quatf {
                self?.camera.position = position
                self?.camera.rotation = rotation
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
            
            // Set custom camera position if provided
            if let position = cameraPosition {
                camera.position = position
            } else {
                // Default position for gaussian splats
                camera.position = SIMD3<Float>(0, 0, -2.5)
            }
        case .sampleBox:
            print("📦 Loading sample box")
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
            break
        }
        print("🎯 VisionSceneRenderer.load completed")
    }

    func startRenderLoop() {
        print("🏃 Starting render loop with ARUnderstanding and WorldTracking")
        
        arTask = Task {
            do {
                try await arSession.run([worldTracking])
            } catch {
                fatalError("Failed to initialize ARSession")
            }

            await withTaskGroup(of: Void.self) { group in
                group.addTask { [weak self] in
                    await self?.processAllAnchors()
                }
                group.addTask { [weak self] in
                    await self?.runRenderLoop()
                }
            }
        }
    }
    
    private func processAllAnchors() async {
        for await update in await ARUnderstanding(providers: [.hands, .device]).anchorUpdates {
            switch update {
            case .hand(let handUpdate):
                if let deviceAnchor = currentDeviceAnchor {
                    await processHandPinch(handUpdate.anchor, deviceAnchor: deviceAnchor)
                }
            case .device(let deviceUpdate):
                currentDeviceAnchor = deviceUpdate.anchor
            default:
                break
            }
        }
    }
    
    private func runRenderLoop() async {
        let renderThread = Thread { [self] in
            print("🎬 Render thread started - inside thread closure")
            print("🎬 About to call renderLoop")
            self.renderLoop()
            print("🎬 Render loop exited")
        }
        renderThread.name = "Render Thread"
        renderThread.start()
        print("🎬 Render thread start() called")
    }
    
    @MainActor
    private func processHandPinch(_ hand: CapturedHandAnchor, deviceAnchor: CapturedDeviceAnchor) {
        guard let skeleton = hand.handSkeleton else { return }
        
        let thumbTip = skeleton.joint(.thumbTip)
        let indexTip = skeleton.joint(.indexFingerTip)
        guard thumbTip.isTracked && indexTip.isTracked else {
            resetHandState(hand.chirality)
            return
        }
        
        // Check if pinching
        let thumbPos = SIMD3<Float>(thumbTip.anchorFromJointTransform.columns.3.x,
                                   thumbTip.anchorFromJointTransform.columns.3.y,
                                   thumbTip.anchorFromJointTransform.columns.3.z)
        let indexPos = SIMD3<Float>(indexTip.anchorFromJointTransform.columns.3.x,
                                   indexTip.anchorFromJointTransform.columns.3.y,
                                   indexTip.anchorFromJointTransform.columns.3.z)
        
        let pinchDistance = simd_distance(thumbPos, indexPos)
        
        if pinchDistance < gestureState.pinchThreshold {
            handlePinchMovement(hand: hand, deviceAnchor: deviceAnchor)
        } else {
            resetHandState(hand.chirality)
        }
        
        // Check for two-handed scaling
        checkTwoHandedScaling()
    }
    
    @MainActor
    private func handlePinchMovement(hand: CapturedHandAnchor, deviceAnchor: CapturedDeviceAnchor) {
        let currentPinchPos = getPinchWorldPosition(hand: hand, deviceAnchor: deviceAnchor)
        
        switch hand.chirality {
        case .right:
            if let lastPos = gestureState.lastRightPinchPosition {
                let delta = currentPinchPos - lastPos
                
                // Pure 3-axis translation only
                let translation = SIMD3<Float>(
                    delta.x * gestureState.translationScale,  // Left/Right
                    delta.y * gestureState.translationScale,  // Up/Down  
                    delta.z * gestureState.translationScale   // Forward/Back
                )
                
                camera.translate(by: translation)
                
                if frameCount % 30 == 0 {
                    print("👋 Right pinch move: \(translation)")
                }
            }
            gestureState.lastRightPinchPosition = currentPinchPos
            
        case .left:
            if let lastPos = gestureState.lastLeftPinchPosition {
                let delta = currentPinchPos - lastPos
                
                // Left hand also does pure 3-axis translation
                let translation = SIMD3<Float>(
                    delta.x * gestureState.translationScale,
                    delta.y * gestureState.translationScale,
                    delta.z * gestureState.translationScale
                )
                
                camera.translate(by: translation)
                
                if frameCount % 30 == 0 {
                    print("👋 Left pinch move: \(translation)")
                }
            }
            gestureState.lastLeftPinchPosition = currentPinchPos
            
        @unknown default:
            break
        }
    }
    
    @MainActor
    private func checkTwoHandedScaling() {
        guard let rightPos = gestureState.lastRightPinchPosition,
              let leftPos = gestureState.lastLeftPinchPosition else {
            gestureState.initialTwoHandDistance = nil
            return
        }
        
        let currentDistance = simd_distance(rightPos, leftPos)
        
        if let initialDistance = gestureState.initialTwoHandDistance {
            let scaleRatio = currentDistance / initialDistance
            let newScale = camera.scale * scaleRatio
            camera.setScale(newScale)
            
            if frameCount % 30 == 0 {
                print("🤏 Two-handed scale: \(scaleRatio), new scale: \(newScale)")
            }
            
            gestureState.initialTwoHandDistance = currentDistance
        } else {
            gestureState.initialTwoHandDistance = currentDistance
        }
    }
    
    @MainActor
    func syncCameraState() {
        // Send camera update through SharePlay
        cameraSync?.sendCameraUpdate(position: camera.position, rotation: camera.rotation)
    }
    
    private func getPinchWorldPosition(hand: CapturedHandAnchor, deviceAnchor: CapturedDeviceAnchor) -> SIMD3<Float> {
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
        let handWorldTransform = deviceAnchor.originFromAnchorTransform * hand.originFromAnchorTransform
        let worldPos = handWorldTransform * SIMD4<Float>(pinchPos.x, pinchPos.y, pinchPos.z, 1.0)
        
        return SIMD3<Float>(worldPos.x, worldPos.y, worldPos.z)
    }
    
    private func resetHandState(_ chirality: HandAnchor.Chirality) {
        switch chirality {
        case .right:
            gestureState.lastRightPinchPosition = nil
        case .left:
            gestureState.lastLeftPinchPosition = nil
        @unknown default:
            break
        }
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
        let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: time)
        drawable.deviceAnchor = deviceAnchor
        
        // Hand gesture processing is now handled asynchronously in processHandGestures()

        let semaphore = inFlightSemaphore
        commandBuffer.addCompletedHandler { (_ commandBuffer)-> Swift.Void in
            semaphore.signal()
        }

        let viewports = self.viewports(drawable: drawable, deviceAnchor: deviceAnchor)

        frameCount += 1
        if frameCount == 1 || frameCount % 60 == 0 {  // Log first frame and every 60 frames
            print("🎞️ Frame \(frameCount): Successfully got drawable and viewports")
            print("🎞️ Model renderer: \(modelRenderer != nil ? "Present" : "nil")")
            if let splat = modelRenderer as? SplatRenderer {
                print("🎞️ Splat points: \(splat.splatCount)")
            } else if modelRenderer != nil {
                print("🎞️ Model renderer type: \(type(of: modelRenderer!))")
            }
            print("📷 Camera position: \(camera.position), rotation: \(camera.rotation), scale: \(camera.scale)")
            print("📐 Viewports count: \(viewports.count)")
            if !viewports.isEmpty {
                print("📐 First viewport screen size: \(viewports[0].screenSize)")
                print("📐 First viewport MTL viewport: \(viewports[0].viewport)")
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

    func renderLoop() {
        print("🔄 Render loop started")
        var loopCount = 0
        while !shouldStopRendering {
            loopCount += 1
            if loopCount == 1 || loopCount % 100 == 0 {
                print("🔄 Render loop iteration \(loopCount), layer state: \(layerRenderer.state)")
            }
            
            if layerRenderer.state == .invalidated {
                print("❌ Layer is invalidated, stopping render loop")
                Self.log.warning("Layer is invalidated")
                return
            } else if layerRenderer.state == .paused {
                if loopCount == 1 || loopCount % 100 == 0 {
                    print("⏸️ LayerRenderer is paused at iteration \(loopCount), waiting...")
                }
                layerRenderer.waitUntilRunning()
                continue
            } else {
                if loopCount == 1 {
                    print("✅ LayerRenderer is running, calling renderFrame")
                }
                autoreleasepool {
                    self.renderFrame()
                }
            }
        }
        print("🔄 Render loop stopped")
    }
    
    func stopRenderLoop() {
        print("🛑 Stopping render loop")
        shouldStopRendering = true
        arTask?.cancel()
        arTask = nil
    }
    
    deinit {
        print("🗑️ VisionSceneRenderer deinit - stopping render loop")
        shouldStopRendering = true
        arTask?.cancel()
        NotificationCenter.default.removeObserver(self)
    }
}

#endif // os(visionOS)

