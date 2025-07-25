# SharePlay Improvement Plan

This document outlines the plan to improve the SharePlay experience by implementing intuitive hand gesture controls for manipulating the 3D scene and providing a more intelligent user experience.

## Current Architecture

The rendering and scene management logic is primarily handled by `VisionSceneRenderer`, which is an `ObservableObject`. This class is responsible for:

- Loading and managing 3D models (`ModelRenderer`).
- Managing the user's viewpoint via a `Camera` struct.
- Running the main render loop.
- Synchronizing camera state with other participants via SharePlay.

The `Camera` struct is defined directly within `VisionSceneRenderer.swift` and manages the position, rotation, and scale of the user's viewpoint.

```swift
// In VisionSceneRenderer.swift

struct Camera {
    var position: SIMD3<Float>
    var rotation: simd_quatf
    var scale: Float

    // ... methods for manipulating the transform ...
}
```

## Implemented Features

### 1. Camera-based Rendering
The `VisionSceneRenderer` no longer uses a simple, automatic rotation. Instead, it uses the `camera.transform` property to generate the view matrix for rendering. This allows for dynamic, user-controlled movement.

### 2. SharePlay Camera Synchronization
The `SharePlayCameraSync` class and `VisionSceneRenderer` work together to synchronize the camera state across all devices in a SharePlay session. Updates are sent when the local user moves, and the renderer listens for notifications to update the camera when a remote user moves.

## Future Work: Implementation Plan

### Step 1: Implement Gesture Controls

We will use SwiftUI's gesture system to handle hand tracking input and manipulate the camera. The gestures will be added to the main content view and will interact with the `VisionSceneRenderer` instance.

- **One-Handed Pinch/Drag:** Translate the camera's position in the X/Y plane.
- **Two-Handed Pinch/Spread:** Scale the scene (zoom in/out) by modifying the `camera.scale` property.

```swift
// In a SwiftUI View (e.g., ContentView or ImmersiveView)

@StateObject private var renderer: VisionSceneRenderer
// ...

var body: some View {
    ImmersiveView(renderer: renderer)
        .gesture(
            // Gesture for translation
            DragGesture()
                .onChanged { value in
                    // Calculate translation delta
                    // renderer.camera.translate(by: delta)
                    // renderer.syncCameraState()
                }
        )
        .gesture(
            // Gesture for scaling (e.g., MagnifyGesture)
            MagnifyGesture()
                .onChanged { value in
                    // renderer.camera.setScale(value.magnification)
                    // renderer.syncCameraState()
                }
        )
}
```

### Step 2: Implement UI Controls

A simple UI control will be added to allow the user to reset the camera's position and orientation to its initial state.

```swift
// In a SwiftUI View

@StateObject private var renderer: VisionSceneRenderer
// ...

var body: some View {
    ZStack {
        ImmersiveView(renderer: renderer)
        VStack {
            Spacer()
            Button("Reset View") {
                // renderer.resetCamera()
                // renderer.syncCameraState()
            }
            .padding()
        }
    }
}
```

### Step 3: Calculate Intelligent Starting Position

To improve the initial user experience, we will calculate the centroid of the loaded 3D model and use it to set the initial camera position. This will place the user in a "center of interest" rather than at the world origin.

This logic will be added to the `load` method in `VisionSceneRenderer.swift`.

```swift
// In VisionSceneRenderer.swift

func load(_ model: ModelIdentifier?, ...) async throws {
    // ... after loading the splat data ...
    
    // 1. Calculate the centroid of all points in the model
    let centroid = calculateCentroid(of: splat.points)
    
    // 2. Set the initial camera position at an offset from the centroid
    let cameraOffset = SIMD3<Float>(0, 0.5, 2.0) // Example offset
    self.camera.position = centroid + cameraOffset
    
    // ...
}
```