# Plan: Support for Compressed PLY Gaussian Splat Files

This document outlines the precise steps required to update the MetalSplatter project to support both standard and compressed PLY splat files, enabling the SampleApp to load either format automatically.

## Phase 1: Update `SplatIO` for Data Modeling and Autodetection

### Step 1.1: Create Unified Scene Data Structures

**File:** `SplatIO/Sources/SplatScene.swift` (New File)
**Purpose:** To define a single, unified data type that can represent both standard and compressed splat scenes, and to define the structs for the compressed format.

**Action:** Create the new file and add the following public types:

```swift
import Foundation

/// Represents the bounding box and value ranges for a chunk of compressed splats.
public struct PLYChunk {
    public var min_x, min_y, min_z: Float
    public var max_x, max_y, max_z: Float
    public var min_scale_x, min_scale_y, min_scale_z: Float
    public var max_scale_x, max_scale_y, max_scale_z: Float
    public var min_r, min_g, min_b: Float
    public var max_r, max_g, max_b: Float
}

/// Represents a single vertex with its data packed into 32-bit integers.
public struct PLYPackedVertex {
    public var packed_position: UInt32
    public var packed_rotation: UInt32
    public var packed_scale: UInt32
    public var packed_color: UInt32
}

/// An enumeration representing a splat scene, which can either be in the standard
/// format or the chunked, compressed format.
public enum SplatScene {
    case standard([SplatScenePoint])
    case compressed(chunks: [PLYChunk], vertices: [PLYPackedVertex])
}
```

### Step 1.2: Implement Autodetection Logic

**File:** `SplatIO/Sources/AutodetectSceneReader.swift`
**Purpose:** To make this the primary entry point for loading any splat file. It will read the file header to determine the format and then delegate parsing to the appropriate logic.

**Action:** Modify the `AutodetectSceneReader` class.

1.  Change the existing `read(from:)` function signature to return `SplatScene`.
2.  Replace the function's implementation with the logic below, which uses a single `PLYReader` instance to inspect the header and then parse accordingly.

```swift
// In class AutodetectSceneReader...

public func read(from url: URL) throws -> SplatScene {
    let plyReader = PLYReader()
    let header = try plyReader.readHeader(from: url)
    let fileData = try Data(contentsOf: url, options: .mappedIfSafe)

    // Check for the 'chunk' element to identify the compressed format.
    if header.elements.contains(where: { $0.name == "chunk" }) {
        // Handle as COMPRESSED
        guard let chunkElement = header.elements.first(where: { $0.name == "chunk" }),
              let vertexElement = header.elements.first(where: { $0.name == "vertex" }) else {
            throw NSError(domain: "AutodetectSceneReader", code: 2, userInfo: [NSLocalizedDescriptionKey: "Compressed file missing 'chunk' or 'vertex' element."])
        }

        let chunkData = try plyReader.readData(for: chunkElement, from: fileData, with: header)
        let chunks = try chunkData.map { (element: PLYElement) throws -> PLYChunk in
            // Mapping logic from PLYElement.properties dictionary to PLYChunk struct
            // This will be verbose, mapping each of the 18 float properties.
            // e.g., guard let min_x = element.properties["min_x"] as? Float else { ... }
            // ...
            return PLYChunk(/*...all 18 properties...*/)
        }

        let vertexData = try plyReader.readData(for: vertexElement, from: fileData, with: header)
        let vertices = try vertexData.map { (element: PLYElement) throws -> PLYPackedVertex in
            // Mapping logic for the 4 UInt32 properties
            guard let pos = element.properties["packed_position"] as? UInt32,
                  let rot = element.properties["packed_rotation"] as? UInt32,
                  let scale = element.properties["packed_scale"] as? UInt32,
                  let color = element.properties["packed_color"] as? UInt32 else {
                throw NSError(domain: "AutodetectSceneReader", code: 3, userInfo: [NSLocalizedDescriptionKey: "Invalid packed vertex data."])
            }
            return PLYPackedVertex(packed_position: pos, packed_rotation: rot, packed_scale: scale, packed_color: color)
        }

        return .compressed(chunks: chunks, vertices: vertices)

    } else {
        // Handle as STANDARD
        let splatReader = SplatPLYSceneReader()
        // This assumes SplatPLYSceneReader can also work from pre-read data or a URL.
        // If not, its logic needs to be integrated here directly.
        let points = try splatReader.read(from: url) // Or refactor to use the data we already have
        return .standard(points)
    }
}
```
*(Note: The existing `SplatPLYSceneReader` might need to be refactored to allow its core parsing logic to be called from `AutodetectSceneReader` without re-reading the file.)*

## Phase 2: Update Metal Shaders and Renderer

### Step 2.1: Define Shared Data Structures for Metal

**File:** `MetalSplatter/Resources/ShaderCommon.h`
**Purpose:** To define C structs that exactly match the memory layout of the Swift structs, allowing data to be passed to the GPU.

**Action:** Add the following struct definitions to the file:

```c
#ifndef ShaderCommon_h
#define ShaderCommon_h

#include <simd/simd.h>

// ... (existing structs)

// Represents the bounding box for a chunk of splats
typedef struct {
    simd_float3 minPosition;
    simd_float3 maxPosition;
    simd_float3 minScale;
    simd_float3 maxScale;
    simd_float3 minColor;
    simd_float3 maxColor;
} ChunkData;

// Represents a single splat with data packed into integers
typedef struct {
    unsigned int packedPosition;
    unsigned int packedRotation;
    unsigned int packedScale;
    unsigned int packedColor;
} PackedSplatData;

#endif /* ShaderCommon_h */
```

### Step 2.2: Implement GPU Decompression Shader

**File:** `MetalSplatter/Resources/SingleStageRenderPath.metal`
**Purpose:** To create the vertex shader that performs on-the-fly decompression of the splat data.

**Action:** Add a new vertex function to the file.

```metal
#include "ShaderCommon.h"

// ... (existing functions)

vertex SplatOut vertex_decompress(
    const device PackedSplatData* packedSplats [[buffer(0)]],
    const device ChunkData* chunks [[buffer(1)]],
    // A buffer that maps each vertex to its corresponding chunk index
    const device uint* chunkMap [[buffer(2)]],
    uint vid [[vertex_id]]
) {
    PackedSplatData packed = packedSplats[vid];
    uint chunkIdx = chunkMap[vid];
    ChunkData chunk = chunks[chunkIdx];

    // Decompress color (RGBA, 8 bits each)
    float4 color = float4(
        float((packed.packedColor >> 24) & 0xFF) / 255.0,
        float((packed.packedColor >> 16) & 0xFF) / 255.0,
        float((packed.packedColor >>  8) & 0xFF) / 255.0,
        float((packed.packedColor >>  0) & 0xFF) / 255.0
    );
    // De-quantize color using chunk bounds
    color.rgb = chunk.minColor + color.rgb * (chunk.maxColor - chunk.minColor);

    // Decompress position (10 bits each for x, y, z)
    float3 pos_quant = float3(
        float((packed.packedPosition >> 20) & 0x3FF),
        float((packed.packedPosition >> 10) & 0x3FF),
        float((packed.packedPosition >>  0) & 0x3FF)
    );
    float3 position = chunk.minPosition + (pos_quant / 1023.0) * (chunk.maxPosition - chunk.minPosition);

    // Decompress scale (10 bits each for x, y, z)
    float3 scale_quant = float3(
        float((packed.packedScale >> 20) & 0x3FF),
        float((packed.packedScale >> 10) & 0x3FF),
        float((packed.packedScale >>  0) & 0x3FF)
    );
    float3 scale = chunk.minScale + (scale_quant / 1023.0) * (chunk.maxScale - chunk.minScale);
    // The article mentions storing scale as log(scale), so we need to exponentiate
    scale = exp(scale);

    // Decompress rotation (quaternion)
    float4 rot_quant = float4(
        float((packed.packedRotation >> 24) & 0xFF),
        float((packed.packedRotation >> 16) & 0xFF),
        float((packed.packedRotation >>  8) & 0xFF),
        float((packed.packedRotation >>  0) & 0xFF)
    );
    // Convert from [0, 255] to [-1, 1]
    float4 q = (rot_quant / 255.0 - 0.5) * 2.0;
    // Normalize to get a valid unit quaternion
    simd_quatf rotation = normalize(simd_quatf(q));

    // Construct the final SplatOut object to pass to the next stage
    SplatOut out;
    out.position = float4(position, 1.0);
    out.color = color;
    out.scale = scale;
    out.rotation = rotation;

    return out;
}
```

### Step 2.3: Update `SplatRenderer` for Dual-Path Rendering

**File:** `MetalSplatter/Sources/SplatRenderer.swift`
**Purpose:** To manage both rendering pipelines (standard and compressed) and select the correct one based on the loaded data.

**Action:**

1.  **Add new properties** to the `SplatRenderer` class for the compressed data buffers and the new pipeline state.
    ```swift
    var compressedRenderPipelineState: MTLRenderPipelineState!
    var chunkBuffer: MTLBuffer?
    var packedSplatBuffer: MTLBuffer?
    var chunkMapBuffer: MTLBuffer?
    ```
2.  **In `init()`**, build the `compressedRenderPipelineState` using the `vertex_decompress` shader function.
3.  **Create a new `update(scene: SplatScene)` function.** This will be the new main entry point for providing data to the renderer.
    ```swift
    public func update(scene: SplatScene) {
        switch scene {
        case .standard(let points):
            // Existing logic to create the vertex buffer from `points`
            // e.g., self.vertexBuffer = device.makeBuffer(bytes: points, ...)
            self.activeSplatCount = points.count
            self.renderPath = .standard // An internal state to track which path to use

        case .compressed(let chunks, let vertices):
            self.chunkBuffer = device.makeBuffer(bytes: chunks, ...)
            self.packedSplatBuffer = device.makeBuffer(bytes: vertices, ...)

            // Create the chunk-to-vertex mapping buffer
            let splatsPerChunk = 256 // As per the article
            var map = [UInt32]()
            map.reserveCapacity(vertices.count)
            for i in 0..<vertices.count {
                map.append(UInt32(i / splatsPerChunk))
            }
            self.chunkMapBuffer = device.makeBuffer(bytes: map, ...)

            self.activeSplatCount = vertices.count
            self.renderPath = .compressed // An internal state
        }
    }
    ```
4.  **In the `draw(in:)` function**, use the internal `renderPath` state to select the correct pipeline and buffers.
    ```swift
    // In draw(in:) or similar render function
    renderEncoder.setRenderPipelineState(renderPath == .standard ? standardRenderPipelineState : compressedRenderPipelineState)

    if renderPath == .standard {
        renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
    } else {
        renderEncoder.setVertexBuffer(packedSplatBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(chunkBuffer, offset: 0, index: 1)
        renderEncoder.setVertexBuffer(chunkMapBuffer, offset: 0, index: 2)
    }
    // ... set other buffers (uniforms, etc.)
    renderEncoder.drawPrimitives(.triangle, vertexStart: 0, vertexCount: activeSplatCount * 6)
    ```

## Phase 3: Integrate into the SampleApp

### Step 3.1: Update the Model Loading Logic

**File:** `SampleApp/Model/SplatRenderer+ModelRenderer.swift` (and potentially `ModelRenderer.swift`)
**Purpose:** To adapt the model loading layer to use the new `SplatScene` enum.

**Action:**

1.  Find the function responsible for loading splat data (e.g., `load(splat:)`).
2.  Change its signature to accept the unified scene object: `func load(scene: SplatScene)`.
3.  Inside this function, simply pass the object to the renderer: `self.splatRenderer.update(scene: scene)`.

### Step 3.2: Update the Main App File Loading

**File:** `SampleApp/App/SampleApp.swift` (or wherever `RV-compressed.ply` is loaded)
**Purpose:** To use the `AutodetectSceneReader` as the single point for loading all `.ply` files.

**Action:**

1.  Locate the code that loads the `.ply` file.
2.  Replace the existing call to `SplatPLYSceneReader` or other readers with a call to the autodetector.
    ```swift
    // Old code (example)
    // let points = try SplatPLYSceneReader().read(from: url)
    // modelRenderer.load(points: points)

    // New code
    do {
        let scene = try AutodetectSceneReader().read(from: url)
        modelRenderer.load(scene: scene)
    } catch {
        // Handle errors
        print("Failed to load splat scene: \(error)")
    }
    ```

This completes the plan. Following these steps will result in a robust application that can handle both splat file formats seamlessly.
