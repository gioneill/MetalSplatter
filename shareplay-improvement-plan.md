# SharePlay Improvement Plan

This document outlines the plan to improve the SharePlay experience by implementing intuitive hand gesture controls for manipulating the 3D scene.

## Project Structure

To keep the code organized, we'll follow this structure:

```
/Sources
|--/Camera.swift
|--/ContentView.swift
|--/ImmersiveView.swift
|--/Models/
|   |--/Camera.swift
|   |--/Splat.swift
|--/Renderers/
|   |--/MetalKitRenderer.swift
|   |--/VisionSceneRenderer.swift
```

## Step 1: Create the `Camera` struct

The `Camera` struct will manage the camera's position and orientation.

```swift
// In Camera.swift

import simd

struct Camera {
    var transform: simd_float4x4 = matrix_identity_float4x4

    var position: SIMD3<Float> {
        get {
            return SIMD3<Float>(transform.columns.3.x, transform.columns.3.y, transform.columns.3.z)
        }
        set(newValue) {
            transform.columns.3.x = newValue.x
            transform.columns.3.y = newValue.y
            transform.columns.3.z = newValue.z
        }
    }

    // ... other camera properties and methods
}
```

## Step 2: Create the `Splat` class

The `Splat` class will be responsible for loading and rendering the 3D model.

```swift
// In Splat.swift

import Metal
import MetalKit

class Splat {
    // ... properties for managing the 3D model

    func render(viewMatrix: simd_float4x4, projectionMatrix: simd_float4x4, to commandBuffer: MTLCommandBuffer) {
        // ... rendering logic
    }
}
```

## Step 3: Create the `Scene` class

The `Scene` class will manage the `Splat` object and the `Camera` object.

```swift
// In Scene.swift

import Foundation

class Scene {
    let splat: Splat
    var camera: Camera

    init(device: MTLDevice) {
        self.splat = Splat(device: device)
        self.camera = Camera()
    }

    func update(at time: TimeInterval) {
        // ... update logic for the scene
    }
}
```

## Step 4: Update the Renderers

The `MetalKitSceneRenderer` and `VisionSceneRenderer` will use the `Scene` class to render the scene.

```swift
// In MetalKitSceneRenderer.swift

class MetalKitSceneRenderer {
    let device: MTLDevice
    let scene: Scene

    init(device: MTLDevice) {
        self.device = device
        self.scene = Scene(device: device)
    }

    func draw(in view: MTKView) {
        // ... rendering logic using the scene
    }
}
```

## Step 5: Implement Gesture Controls

We'll use a `DragGesture` to handle the hand tracking and update the camera's position and orientation.

```swift
// In ContentView.swift

struct ContentView: View {
    @State private var scene = Scene(device: MTLCreateSystemDefaultDevice()!)

    var body: some View {
        ImmersiveView(scene: $scene)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // ... update camera based on gesture
                    }
            )
    }
}
```

## Step 6: Implement UI Controls

We'll add a button to reset the camera's position.

```swift
// In ContentView.swift

struct ContentView: View {
    @State private var scene = Scene(device: MTLCreateSystem-default-device()!)

    var body: some View {
        ZStack {
            ImmersiveView(scene: $scene)
            VStack {
                Spacer()
                Button("Reset View") {
                    // ... reset camera position
                }
                .padding()
            }
        }
    }
}
```
