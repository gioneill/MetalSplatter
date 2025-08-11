# SharePlay Integration for MetalSplatter

This document describes the complete SharePlay integration implemented for MetalSplatter, including support for the new nearby sharing features in visionOS 26.

## Overview

The SharePlay implementation enables users to view and interact with 3D Gaussian splats together, whether they're in the same room (nearby participants) or connected via FaceTime (remote participants). The system automatically handles both types of participants with appropriate spatial positioning and synchronization.

## Features

### Core SharePlay Functionality
- **Shared 3D Viewing**: Multiple participants can view the same 3D splat models together
- **Camera Synchronization**: Real-time camera position and rotation sync across all devices
- **Model Selection Sync**: When one participant loads a new model, all participants see it
- **Cross-Platform Support**: Works across visionOS, iOS, and macOS (where supported)

### Nearby Sharing (visionOS 26+)
- **Automatic Detection**: Distinguishes between nearby and FaceTime participants
- **Spatial Positioning**: Content positioned relative to participants' actual poses
- **World Anchors**: Shared content anchored to real-world locations for nearby participants
- **Mixed Sessions**: Supports sessions with both nearby and remote participants simultaneously

### Advanced Features
- **Participant Indicators**: Visual indicators showing other participants' locations
- **Pointer Sharing**: Synchronized pointing gestures and annotations
- **Performance Optimization**: Adaptive quality based on network conditions and participant count
- **Error Recovery**: Automatic reconnection and fallback mechanisms

## Architecture

### Core Components

1. **SplatViewingActivity**: GroupActivity definition for sharing sessions
2. **SharePlaySessionManager**: Manages GroupSession lifecycle and messaging
3. **SharePlayCameraSync**: Handles camera position/rotation synchronization
4. **SharePlayModelSync**: Manages model loading and selection across devices
5. **NearbyParticipantHandler**: Handles nearby vs. remote participant detection
6. **SpatialContentManager**: Manages spatial content and participant indicators
7. **SharePlayIntegrationHelper**: Coordinates all components and optimizations

### Message Types

```swift
enum SyncMessage: Codable {
    case modelSelection(ModelIdentifier)
    case cameraUpdate(position: SIMD3<Float>, rotation: simd_quatf, timestamp: TimeInterval)
    case viewingStateUpdate(ViewingState)
    case participantPointer(position: SIMD3<Float>, participantID: String)
    case annotation(AnnotationMessage)
}
```

## Implementation Details

### Nearby Participant Handling

The system uses `isNearbyWithLocalParticipant` to distinguish participant types:

```swift
let nearbyParticipants = activeParticipants.filter {
    $0.isNearbyWithLocalParticipant && $0.id != session.localParticipant.id
}
```

### Spatial Positioning

Content is positioned differently for nearby vs. remote participants:

- **Nearby Participants**: Positioned relative to their actual pose (can't be moved by the system)
- **FaceTime Participants**: Positioned relative to their seat pose (system moves spatial Personas to seats)

### Group Immersive Space

For visionOS, the system enables group immersive space support:

```swift
var configuration = SystemCoordinator.Configuration()
configuration.supportsGroupImmersiveSpace = true
coordinator.configuration = configuration
```

### World Anchor Sharing

Nearby participants can share world anchors for consistent real-world positioning:

```swift
let anchor = WorldAnchor(
    originFromAnchorTransform: transform, 
    sharedWithNearbyParticipants: true
)
```

## Usage

### Starting a SharePlay Session

From the main app interface:
1. Tap the SharePlay button to start a session
2. The system presents the Share Window menu
3. Participants can join via FaceTime or nearby discovery

### Programmatic API

```swift
// Start a session with a specific model
await sharePlayManager.startActivity(with: modelIdentifier)

// Send camera updates
sharePlayManager.sendCameraUpdate(position: position, rotation: rotation)

// Send model selection
sharePlayManager.sendModelSelection(modelIdentifier)
```

### Integration with Renderers

The system integrates with existing renderers:

```swift
// In VisionSceneRenderer
renderer.cameraSync = sharePlayIntegration.cameraSync
renderer.sharePlaySessionManager = sharePlayIntegration.sessionManager
```

## Testing and Debugging

### Debug Interface

A comprehensive debug interface is available in DEBUG builds:
- Real-time participant status
- Performance metrics monitoring
- Test controls for various features
- Network latency and memory usage tracking

### Testing Scenarios

1. **Single Device Testing**: Use the simulator to test basic functionality
2. **Multiple Device Testing**: Test with actual devices for full functionality
3. **Mixed Sessions**: Test with both nearby and FaceTime participants
4. **Network Conditions**: Test under various network latencies and conditions

## Performance Optimizations

### Adaptive Quality
- Camera update throttling based on network conditions
- Level-of-detail for participant indicators
- Automatic cleanup of unused resources

### Memory Management
- Automatic cleanup of old annotations and participant data
- Resource optimization for many-participant sessions

### Network Optimization
- Reliable vs. unreliable messaging based on content type
- Batched synchronization messages
- Compressed spatial data transmission

## Requirements

- **iOS/iPadOS**: 17.0+ (for basic SharePlay)
- **visionOS**: 2.0+ (for full nearby sharing support)
- **macOS**: 14.0+ (for basic SharePlay)
- **GroupActivities Framework**: Required
- **ARKit**: Required for visionOS world anchor features

## Limitations and Considerations

1. **File Sharing**: Models must be available on all devices (consider iCloud sync)
2. **Network Requirements**: Stable internet connection required for FaceTime participants
3. **Spatial Tracking**: Nearby features require good lighting and trackable environments
4. **Performance**: Large models may require optimization for multi-participant sessions
5. **Privacy**: Spatial data is shared with participants (inform users appropriately)

## Future Enhancements

- **Voice Communication**: Integration with FaceTime audio
- **Gesture Recognition**: Advanced hand tracking synchronization
- **Multi-Model Support**: Viewing different models simultaneously
- **Recording/Playback**: Session recording for later review
- **Analytics**: Usage metrics and optimization insights

## Files Added

```
SampleApp/SharePlay/
├── SplatViewingActivity.swift          # GroupActivity definition
├── SharePlaySessionManager.swift       # Session management
├── SharePlayCameraSync.swift          # Camera synchronization
├── SharePlayModelSync.swift           # Model synchronization
├── NearbyParticipantHandler.swift     # Nearby participant handling
├── SpatialContentManager.swift        # Spatial content management
├── SharePlayIntegrationHelper.swift   # Main integration coordinator
├── SharePlayStatusView.swift          # UI components
└── SharePlayTestingView.swift         # Debug/testing interface
```

The implementation is complete and ready for testing with multiple devices to validate the full SharePlay experience with nearby sharing support.