# SharePlay Testing Guide

This guide provides step-by-step instructions for testing the SharePlay hand gesture controls in MetalSplatter.

## Prerequisites

- Two or more Vision Pro devices (or Vision Pro + simulator)
- Same Apple ID signed in on all devices (for FaceTime)
- MetalSplatter app installed on all devices
- A .ply or .splat file to test with

## Basic Setup Testing

### 1. Load a Model Without SharePlay
1. Launch MetalSplatter
2. Tap "Read Scene File" and select a .ply file
3. Verify the model loads and is static (no rotation)
4. Test camera position by checking if model appears at expected distance

### 2. Test Gesture Controls (Single User)
1. With model loaded, test each gesture:
   - **Index+Thumb Pinch**: Drag to move camera in X/Y plane
   - **Middle+Thumb Pinch**: Drag to rotate view around model
   - **Two-Hand Pinch**: Pinch/spread to zoom in/out
2. Verify each gesture type works independently
3. Check that gestures don't interfere with each other

## SharePlay Testing

### 3. Start SharePlay Session
1. **Host Device**:
   - Load a model
   - Start a FaceTime call with other participant(s)
   - Tap the SharePlay button in the FaceTime interface
   - Select MetalSplatter when prompted
2. **Participant Device(s)**:
   - Accept the SharePlay invitation
   - Verify the same model loads automatically

### 4. Test Synchronized Camera Controls
1. **Host Controls**:
   - Use Index+Thumb pinch to move camera
   - Verify all participants see the same camera movement
   - Check movement is smooth (no jitter)
2. **Participant Controls**:
   - Have participant use Middle+Thumb pinch to rotate
   - Verify rotation appears on all devices
   - Confirm no conflicts when switching control
3. **Simultaneous Control**:
   - Both users try to control camera at same time
   - Verify last input takes precedence
   - Check for smooth transitions between controllers

### 5. Test Zoom Synchronization
1. Host uses two-hand pinch to zoom in
2. Verify zoom level syncs to all participants
3. Participant zooms out
4. Confirm all devices show same zoom level

## Edge Cases to Test

### 6. Network Interruption
1. Start SharePlay session with camera positioned away from origin
2. Temporarily disable WiFi on one device
3. Move camera on connected device
4. Re-enable WiFi
5. Verify camera position syncs when reconnected

### 7. Model Switching
1. During active SharePlay session
2. Host loads a different model
3. Verify:
   - New model loads on all devices
   - Camera resets to appropriate default position
   - Gesture controls continue working

### 8. Participant Join/Leave
1. Start session with 2 participants
2. Add third participant mid-session
3. Verify new participant receives current camera state
4. Have one participant leave
5. Confirm remaining participants maintain sync

### 9. Performance Testing
1. Load a large/complex .ply file (>1M points)
2. Rapidly move camera while monitoring:
   - Frame rate remains smooth
   - Sync latency stays under 100ms
   - No crashes or freezes

## Debugging Tips

### If Gestures Don't Work:
- Check hand tracking permissions in Settings
- Ensure hands are visible to cameras
- Try recalibrating hand tracking
- Restart the app

### If SharePlay Sync Fails:
- Verify all devices on same WiFi network
- Check SharePlay is enabled in Settings
- End and restart FaceTime call
- Check for any error messages in UI

### Performance Issues:
- Test with smaller model first
- Check available device memory
- Reduce number of participants
- Close other apps

## Expected Behaviors

✅ **Working Correctly**:
- Camera movements sync within 100ms
- Gestures feel responsive and natural
- All participants see identical view
- Smooth transitions between different controllers

❌ **Known Limitations**:
- Brief delay when switching between gesture types
- Slight lag with 5+ participants
- Hand tracking may lose precision at extreme angles

## Logging

For debugging, useful logs can be found:
- SharePlay events: Look for "SharePlay" category
- Camera updates: Search for "CameraUpdate"
- Gesture recognition: Filter by "HandGesture"

Use Console app or Xcode to view device logs during testing.