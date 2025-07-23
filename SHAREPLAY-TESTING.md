# SharePlay Testing Instructions for MetalSplatter

## Quick Start Testing (Fastest Path)

### Prerequisites
- Xcode 15.0+ with visionOS SDK
- Apple Developer account with SharePlay entitlements
- Test devices enrolled in your developer program
- FaceTime enabled on test devices

### 1. Immediate Single-Device Validation

```bash
# 1. Build the project
open MetalSplatter.xcodeproj
# Build for your target device (iOS/visionOS)
# Deploy to device via Xcode

# 2. Launch app and verify basics
# ✓ App launches without crashes
# ✓ SharePlay button appears in main UI
# ✓ Debug interface visible in DEBUG builds
# ✓ Basic model loading still works (sample box)
```

**What to check:**
- Console logs for SharePlay initialization messages
- SharePlay button appears in ContentView
- Debug panel shows "SharePlay Inactive" initially
- No crash logs or memory warnings

### 2. Two-Device Basic SharePlay Test

**Minimum Setup:** Any two iOS devices (iPhone + iPad, two iPhones, etc.)

```
Step 1: Prepare devices
- Install MetalSplatter on both devices
- Ensure both can FaceTime each other
- Both devices on same WiFi (recommended)

Step 2: Start SharePlay session
Device A: Open MetalSplatter
Device A: Tap "Start SharePlay" button
Device A: Select contact or start FaceTime call
Device B: Accept SharePlay invitation from FaceTime

Step 3: Test synchronization
Device A: Load "Sample Box"
Device B: Should automatically load Sample Box
Device B: Load a .ply/.splat file (if available)
Device A: Should automatically load the same file

Step 4: Test camera sync
Device A: Rotate/move camera view
Device B: Should see synchronized camera movement
```

**Expected Results:**
- Both devices show "SharePlay Active" status
- Model selection syncs between devices
- Camera movements appear on both devices
- Participant count shows correctly

### 3. Vision Pro Nearby Sharing Test

**Requirements:** 2+ Apple Vision Pro devices with visionOS 26+

```
Step 1: Setup
- Both Vision Pro devices in same physical room
- Good lighting for spatial tracking
- MetalSplatter installed on both

Step 2: Test nearby detection
Device A: Open MetalSplatter
Device A: Tap "Start SharePlay"
Device A: Should see Share Window menu
Device B: Open MetalSplatter
Device B: Should auto-discover nearby session
Device B: Join nearby session

Step 3: Verify nearby features
- Debug interface shows participants as "Nearby"
- Blue participant indicators appear
- Spatial content positioning works
- World anchors sync between devices
```

**Expected Results:**
- Participants detected as "Nearby" (not FaceTime)
- Spatial indicators show real user positions
- Content anchored to real-world locations
- Both devices track spatial changes

### 4. Mixed Session Test (Advanced)

**Setup:** 1 Vision Pro nearby + 1 remote device via FaceTime

```
Device A (Vision Pro): In room
Device B (Vision Pro): In same room
Device C (iPhone/iPad): Remote location

Step 1: Start mixed session
Device A: Start SharePlay
Device B: Join as nearby participant
Device C: Join via FaceTime call

Step 2: Verify participant types
Debug interface should show:
- A & B as "Nearby" participants
- C as "FaceTime" participant
- Different colored indicators
```

## Debug Tools and Monitoring

### Built-in Debug Interface (DEBUG builds only)

The app includes a comprehensive debug panel:

```
Performance Metrics:
- Memory usage (MB)
- Network latency (ms)
- Active participants count
- Nearby vs FaceTime breakdown

Session Information:
- Session state (waiting/joined/invalidated)
- Participant IDs and types
- Camera sync status
- Spatial object counts

Test Controls:
- Send test messages
- Trigger camera sync test
- Test model loading
- Test spatial content placement
```

### Console Logging

Monitor SharePlay activity:

```bash
# View all MetalSplatter logs
log stream --predicate 'subsystem == "com.metalsplatter"'

# Filter for SharePlay specific logs
log stream --predicate 'subsystem == "com.metalsplatter" AND category == "SharePlay"'
```

**Key log messages to watch for:**
- `SharePlay activity activated successfully`
- `Session state changed to: joined`
- `Updated participants - Total: X, Nearby: Y, Remote: Z`
- `Sent/Received model selection`
- `Camera update sent/received`

### Performance Monitoring

Use Xcode Instruments:

```
Recommended instruments:
- Time Profiler: Check for performance bottlenecks
- Allocations: Monitor memory usage
- Network: Track SharePlay network traffic
- Core Location (visionOS): Spatial tracking performance
```

## Common Issues and Solutions

### Session Won't Start
```
Symptoms: SharePlay button does nothing or shows error
Solutions:
- Check GroupActivities entitlement in app
- Verify Apple ID signed in on device
- Ensure FaceTime is enabled
- Check network connectivity
```

### Models Don't Sync
```
Symptoms: One device loads model, other doesn't
Solutions:
- Ensure model file exists on both devices
- Check file permissions
- Verify SharePlay session is active
- Look for model loading errors in console
```

### Poor Performance
```
Symptoms: Lag, dropped frames, high memory usage
Solutions:
- Check network latency in debug interface
- Reduce model complexity
- Close other apps
- Check for memory leaks in Instruments
```

### Spatial Tracking Issues (visionOS)
```
Symptoms: Participants not positioned correctly
Solutions:
- Improve room lighting
- Ensure clear camera view
- Reset spatial tracking in Settings
- Check for occlusion of Vision Pro cameras
```

## Testing Checklist

### Basic Functionality
- [ ] App builds and runs without errors
- [ ] SharePlay UI elements appear
- [ ] Session creation works
- [ ] Model loading synchronizes
- [ ] Camera movement synchronizes
- [ ] Participant detection accurate
- [ ] Session cleanup on exit

### Performance
- [ ] Frame rate stays >30 FPS during SharePlay
- [ ] Memory usage reasonable (<500MB + models)
- [ ] Network latency <100ms on good connections
- [ ] No memory leaks after ending sessions
- [ ] Battery usage acceptable on Vision Pro

### Nearby Sharing (visionOS 26+)
- [ ] Nearby participants detected correctly
- [ ] FaceTime participants detected correctly
- [ ] Mixed sessions work properly
- [ ] Spatial positioning accurate
- [ ] World anchors sync correctly
- [ ] Participant indicators positioned correctly

### Error Handling
- [ ] Network disconnection handled gracefully
- [ ] App doesn't crash when participants leave
- [ ] Model loading failures show appropriate errors
- [ ] Spatial tracking loss handled properly
- [ ] Session recovery works after reconnection

## Advanced Testing Scenarios

### Network Stress Testing
```bash
# Use Network Link Conditioner (Xcode > Open Developer Tool)
Test profiles:
- Very Bad Network (1 Mbps, 1000ms latency, 10% loss)
- Lossy Network (10 Mbps, 200ms latency, 5% loss)
- Edge (240 Kbps, 400ms latency)

Expected: Graceful degradation, not crashes
```

### Load Testing
```
Multiple participants (test platform limits):
- iOS: Up to 32 participants
- visionOS: Check platform documentation

Large model files:
- Test with >100MB .ply files
- Monitor memory usage and loading times
- Verify sync still works with large files
```

### Extended Session Testing
```
Run continuous 1-hour sessions:
- Monitor memory usage over time
- Check for network connection stability
- Verify spatial tracking accuracy remains good
- Test battery usage on Vision Pro
```

## Reporting Issues

When filing bug reports, include:

### Device Information
- Device models (iPhone 15 Pro, Vision Pro, etc.)
- OS versions (iOS 17.1, visionOS 2.0, etc.)
- App version and build number
- Network type (WiFi, cellular, etc.)

### Session Details
- Number of participants
- Participant types (nearby vs FaceTime)
- Session duration before issue
- Specific actions that triggered the issue

### Debug Information
- Console logs from all affected devices
- Performance metrics from debug interface
- Screenshots/recordings of the issue
- Steps to reproduce consistently

### Log Collection
```bash
# Collect logs for bug reports
log collect --last 1h --output ~/Desktop/shareplay-logs.logarchive

# Include in bug report along with:
# - Device crash logs (Settings > Privacy & Security > Analytics)
# - Screenshots of debug interface
# - Network speed test results
```

## File Structure Reference

The SharePlay implementation consists of these key files:

```
SampleApp/SharePlay/
├── SplatViewingActivity.swift          # GroupActivity definition
├── SharePlaySessionManager.swift       # Core session management
├── SharePlayCameraSync.swift          # Camera synchronization
├── SharePlayModelSync.swift           # Model synchronization
├── NearbyParticipantHandler.swift     # Nearby participant features
├── SpatialContentManager.swift        # Spatial content management
├── SharePlayIntegrationHelper.swift   # Main coordinator
├── SharePlayStatusView.swift          # UI components
└── SharePlayTestingView.swift         # Debug interface

Modified Files:
├── SampleApp/App/SampleApp.swift      # App-level integration
└── SampleApp/Scene/ContentView.swift  # Main UI integration
```

For detailed technical documentation, see `README-SharePlay.md`.
For comprehensive testing scenarios, see `Testing-Guide.md`.