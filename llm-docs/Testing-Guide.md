# SharePlay Testing Guide for MetalSplatter

## Phase 1: Single Device Validation

### Basic Functionality Tests
1. **App Launch & UI**
   ```
   ✓ App launches without crashes
   ✓ SharePlay button appears in ContentView
   ✓ ShareLink is hidden but present (for Share Window menu)
   ✓ Debug interface shows in DEBUG builds
   ```

2. **SharePlay Initialization**
   ```
   ✓ Tap "Start SharePlay" - should present Share Window menu
   ✓ Check debug interface shows "SharePlay Inactive" initially
   ✓ Session manager initializes without errors
   ✓ No memory leaks during initialization
   ```

3. **Model Loading**
   ```
   ✓ Load sample box - should work normally
   ✓ Load .ply/.splat file - should work normally
   ✓ Model selection triggers SharePlay message (if session active)
   ✓ Check console logs for SharePlay integration messages
   ```

### Code Validation Tests
Run these in Xcode:

```swift
// Test SharePlay component initialization
func testSharePlayInitialization() {
    let helper = SharePlayIntegrationHelper()
    XCTAssertTrue(helper.isInitialized)
    XCTAssertNotNil(helper.sessionManager)
    XCTAssertNotNil(helper.cameraSync)
}

// Test message encoding/decoding
func testMessageSerialization() {
    let message = SyncMessage.modelSelection(.sampleBox)
    let encoded = try! JSONEncoder().encode(message)
    let decoded = try! JSONDecoder().decode(SyncMessage.self, from: encoded)
    // Verify round-trip works
}
```

## Phase 2: Two-Device SharePlay Testing

### Setup Requirements
- Two devices with the app installed
- Both devices signed into iCloud
- FaceTime enabled and working between devices

### Basic SharePlay Flow
1. **Session Creation**
   ```
   Device A: Tap "Start SharePlay"
   Device A: Select "FaceTime" or invite specific contact
   Device B: Accept SharePlay invitation
   Both: Verify session shows as "Active" in UI
   ```

2. **Model Synchronization**
   ```
   Device A: Load sample box
   Device B: Should automatically load sample box
   Device B: Load different model
   Device A: Should automatically load that model
   
   Expected: Both devices show same model
   ```

3. **Camera Synchronization**
   ```
   Device A: Rotate/move camera in 3D space
   Device B: Should see synchronized camera movement
   
   Note: Test gradually - start with small movements
   Expected: Smooth, synchronized camera motion
   ```

### FaceTime SharePlay Testing
```
Prerequisites:
- Active FaceTime call between devices
- Both users have app installed
- SharePlay enabled in FaceTime settings

Test Steps:
1. Start FaceTime call
2. Device A: Open MetalSplatter during call
3. Device A: Tap SharePlay button
4. Device B: Accept SharePlay from FaceTime interface
5. Verify shared viewing experience
```

## Phase 3: Nearby Sharing Testing (visionOS 26+)

### Requirements
- 2+ Apple Vision Pro devices
- visionOS 26+ installed
- Same physical location (same room)
- Good lighting for spatial tracking

### Nearby Detection Tests
1. **Proximity Detection**
   ```
   Setup: Two Vision Pro users in same room
   Device A: Start SharePlay session
   Device B: Should auto-discover nearby session
   
   Expected: Debug interface shows:
   - Device A: "1 Nearby participant"
   - Device B: Connected to nearby session
   ```

2. **Spatial Positioning**
   ```
   Test: Users move around room while in session
   Expected: 
   - Participant indicators follow actual user positions
   - Content positioned relative to real user locations
   - No artificial repositioning of participants
   ```

3. **World Anchor Sharing**
   ```
   Device A: Place annotation/content at specific location
   Both devices: Should see content at same real-world position
   Users move: Content should stay anchored to real world
   ```

### Mixed Session Testing
```
Setup: 1 nearby user + 1 FaceTime user
Device A (Vision Pro): In room
Device B (Vision Pro): In room  
Device C (iPhone): Remote via FaceTime

Expected Behavior:
- A & B appear as "nearby" to each other
- C appears as "FaceTime" participant to A & B
- A & B appear as spatial Personas to C
- All see synchronized content
```

## Phase 4: Stress & Performance Testing

### Network Conditions
```bash
# Simulate poor network (use Network Link Conditioner)
# Test profiles:
- High latency (500ms+)
- Low bandwidth (1 Mbps)
- Packet loss (5-10%)
- Intermittent connectivity

Expected: Graceful degradation, not crashes
```

### Many Participants
```
Test with maximum participants (varies by platform)
Expected:
- Performance optimization kicks in
- UI remains responsive
- Memory usage stays reasonable
- Network traffic optimized
```

### Extended Sessions
```
Run 30+ minute sessions
Monitor:
- Memory usage over time
- Network stability
- Spatial tracking accuracy
- Battery usage on Vision Pro
```

## Phase 5: Error Condition Testing

### Network Failures
```
Test Scenarios:
1. Start session, then disconnect WiFi on one device
2. Rejoin session after network restored
3. Force-quit app during active session
4. Device goes to sleep during session

Expected: Graceful recovery when possible
```

### Model Loading Failures
```
Test Scenarios:
1. Device A loads model not available on Device B
2. Large model file that fails to sync
3. Corrupted model file
4. Model loading timeout

Expected: Error messages, fallback behavior
```

### Spatial Tracking Issues
```
Test Scenarios (visionOS):
1. Poor lighting conditions
2. Rapid movement/tracking loss
3. Occlusion of cameras
4. Moving to different room

Expected: Graceful handling, user feedback
```

## Debugging Tools

### Built-in Debug Interface
```swift
// Access debug info in app
#if DEBUG
// Shows real-time metrics:
// - Participant count & types
// - Network latency
// - Memory usage
// - Message throughput
// - Spatial object count
#endif
```

### Console Logging
```bash
# Monitor SharePlay logs
log stream --predicate 'subsystem == "com.metalsplatter"'

# Key log categories to watch:
# - SharePlay session state changes
# - Message send/receive
# - Spatial tracking events
# - Performance warnings
```

### Xcode Instruments
```
Recommended instruments:
- Network: Monitor SharePlay traffic
- Memory: Check for leaks
- Time Profiler: Find performance bottlenecks
- Core Location: Spatial tracking issues (visionOS)
```

## Test Validation Checklist

### Core SharePlay Functionality
- [ ] Session creation/joining works
- [ ] Model synchronization works
- [ ] Camera synchronization works  
- [ ] Participant detection accurate
- [ ] Session cleanup on exit
- [ ] Performance acceptable (>30 FPS)
- [ ] Memory usage stable
- [ ] Network usage reasonable

### Nearby Sharing (visionOS 26+)
- [ ] Nearby vs FaceTime detection works
- [ ] Spatial positioning accurate
- [ ] World anchors shared correctly
- [ ] Mixed sessions (nearby + remote) work
- [ ] Real-world content anchoring works
- [ ] Participant indicators positioned correctly

### Error Handling
- [ ] Network disconnection handled gracefully
- [ ] Model loading failures handled
- [ ] Spatial tracking loss handled
- [ ] Session recovery works
- [ ] User feedback provided for errors

### Performance
- [ ] Latency under 100ms for good networks
- [ ] Memory usage under 500MB base + models
- [ ] CPU usage reasonable
- [ ] Battery life acceptable on Vision Pro
- [ ] Adaptive quality working

## Automated Testing

Create unit tests for core components:

```swift
// Example test structure
class SharePlayTests: XCTestCase {
    func testSessionManagerInitialization() { }
    func testMessageSerialization() { }
    func testCameraSyncThrottling() { }
    func testParticipantDetection() { }
    func testSpatialPositioning() { }
    func testErrorRecovery() { }
}
```

## Known Limitations to Test Around

1. **Model Availability**: Both devices must have access to the same model files
2. **Network Requirements**: FaceTime participants need stable internet
3. **Spatial Tracking**: Requires good lighting and trackable environment
4. **Device Limitations**: Features vary by platform (iPhone vs Vision Pro)
5. **Participant Limits**: SharePlay has platform-specific participant limits

## Reporting Issues

When reporting bugs, include:
- Device models and OS versions
- Network conditions
- Session participant types (nearby vs FaceTime)
- Steps to reproduce
- Console logs from all devices
- Performance metrics from debug interface

This comprehensive testing approach will validate both basic SharePlay functionality and the advanced nearby sharing features specific to visionOS 26.