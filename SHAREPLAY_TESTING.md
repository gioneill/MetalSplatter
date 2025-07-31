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

---

## Comprehensive SharePlay Validation Plan (v1)

This section augments the steps above with a **repeatable, confidence‑building plan** that covers: model identity, camera sync, nearby vs FaceTime participants, and full immersive “walk together” behavior on visionOS.

### Key concepts you should know first

**How does the app know we’re looking at the *same* splat?**

- The app uses a `ModelIdentifier` to describe what to load and it includes information that’s sent to other devices in two ways:
  1) In the SharePlay activity itself (`SplatViewingActivity(modelIdentifier: …)`), and
  2) In real‑time via messages (`SyncMessage.modelSelection(modelIdentifier)`).
- **Current behavior** (as implemented in this repo): when `ModelIdentifier` is `.gaussianSplat(URL)`, the receiver checks **whether that exact file URL path exists locally** (`fileExists(atPath:)`). If it doesn’t, we currently log *“needs download”* but don’t automatically transfer or fetch it yet.
- **Implication for testing *today***: if you want to exercise custom `.ply`/`.splat` files across devices, make sure **each device has a local copy of the file**. The paths don’t have to be byte‑for‑byte identical if you add a local resolver (see below), but with the current code the simplest way is to put the file in a shared, predictable location (e.g. iCloud Drive › `Shared/Splats/foo.splat`) on **each device** and then pick it from there.

> **Recommended future improvement** (not required for this test pass): switch the load logic to resolve by a stable **content ID** (e.g. file hash + filename) and/or attach the asset via `GroupSessionJournal` when small enough. That way different local paths won’t matter. Until then, follow the steps below.

### Quick test matrix

| Scenario | What to use | Expectation |
|---|---|---|
| Sanity check of session, menus, and messaging | **Sample Box** model | Everything should work without any file prep. |
| Camera sync over FaceTime | **Sample Box** | Movement/rotation/zoom reflect on all devices within ~100 ms. |
| Camera sync with nearby Vision Pro devices | **Sample Box** | Same as above; nearby badge shows for in‑room participants. |
| Custom `.ply`/`.splat` across devices (current code) | **Place the same file on each device and pick locally** | Receiver auto‑loads if the sent URL path exists locally; otherwise you’ll see the “needs download” logs. |
| Immersive “walk together” (visionOS) | **Sample Box** (or small `.splat`) | With `supportsGroupImmersiveSpace = true`, both can physically move and see the same spatial arrangement. |

---

## Phase A — Baseline with the built‑in Sample Box

Use this first to validate wiring before involving custom files.

1. **Host**: Launch the app and load **Sample Box**.
2. Start a FaceTime call with the participant.
3. From the Share menu (or the hidden `ShareLink` path), start **MetalSplatter**. Accept on the other device.
4. Verify status:
   - Status pill shows **SharePlay Active**.
   - Participants list shows both devices (Nearby vs FaceTime labels as appropriate).
5. **Camera sync**:
   - Host: perform index+thumb **pan**; participant should see identical pan within ~100 ms.
   - Participant: perform middle+thumb **rotate**; host should mirror it.
   - Either side: two‑hand **zoom**; both should match.
6. **Conflict handling**: briefly control at the same time. Last writer wins; motion should settle smoothly.

**Pass criteria**
- Both devices report identical movement/zoom.
- No more than a split‑second divergence during hand‑offs.

**If it fails**
- Confirm both devices show “SharePlay Active”.
- Look for logs containing `Camera sync` / `sendCameraUpdate` / `Received camera update`.

---

## Phase B — Custom `.ply` / `.splat` models across devices (current behavior)

Because the repo currently validates **by URL existence**, take one of these approaches:

### Option 1 — Easiest: Use **Sample Box** to test SharePlay features; use custom files only for **single‑device** performance tests.
This gives high confidence that SharePlay is correct independent of asset distribution.

### Option 2 — Both devices prepare the same file in a **predictable location**
1. Put your file in **iCloud Drive** (e.g., `iCloud Drive/Shared/Splats/foo.splat`) on **each** device.
2. On **each** device, use *Read Scene File* and select that same file.
3. Start SharePlay and **then** have the host load that file again (so the app broadcasts the `modelSelection`).
4. The receiver should pass `fileExists(atPath:)` and load it automatically.

> If the receiver logs **“needs download”**, the path didn’t resolve locally. Re‑pick the file on that device so the sandbox has a valid URL, then repeat step 3.

### Option 3 — (Future improvement you can add later) Resolve by **content ID** or transfer the asset
- Map the incoming `ModelIdentifier` to a **local match** using filename + size or a **hash** of the file in your Documents/Splats folder.
- Or, for smaller assets, use `GroupSessionJournal` to attach the file once and have receivers download from the session.

**Pass criteria**
- When the host switches models, the receiver loads the same model without manual picking.
- The HUD subtitle (if you show `modelIdentifier.displayName`) matches on both devices.

---

## Phase C — Immersive “walk together” (visionOS)

This verifies you’re not limited to the initial window and that the group shared context is active.

**Pre‑check**
- In code, the session sets `supportsGroupImmersiveSpace = true` on `SystemCoordinator.Configuration` (already present in this repo).

**Steps**
1. On Vision Pro, open your **Immersive Space** (e.g., via *Show Sample Box* in visionOS which triggers `openImmersiveSpace`).
2. Start/Join SharePlay if not already active.
3. Both users **physically move** a few steps in different directions.
4. Verify:
   - You both see the **same content placement** relative to yourselves.
   - Participant indicators and annotations remain anchored in the same *world* locations from both perspectives.
5. (Optional) Tap **Set new origin** in the UI while the space is open.
   - Verify both devices keep a coherent alignment after the origin change.

**Pass criteria**
- Spatial alignment is consistent as participants walk.
- No drifting or re‑anchoring artifacts during normal motion.

**If it fails**
- Ensure both devices are in the immersive space (not just a window).
- Confirm you’re testing in a well‑lit room to help tracking.

---

## Troubleshooting & what the logs mean

Look for these markers in Xcode/Console:
- **Session**: `Configuring group session…`, `Session state changed`, `Joining session…`.
- **Participants**: `Nearby participants updated`, `Remote participants updated`.
- **Camera**: `sendCameraUpdate`, `Received camera update from participant…`.
- **Models**: `Received model selection`, `Model available / needs download`.
- **Anchors** (visionOS): `Shared world anchor added/updated/removed`.

If you consistently see *“needs download”* on the receiver when switching to a custom file, you’re hitting the current URL‑existence check. Use **Sample Box** for cross‑device tests, or apply **Option 2** above.

---

## FAQ

**Do both devices need the same `.ply` file?**  
For **now**, yes—each device needs a local copy for automatic loading. The path can differ if you add a content‑ID resolver; with the current code, put the file in a shared, predictable location on both devices and pick it locally once.

**If the file paths are different, will the session be confused?**  
The session isn’t confused—the **identifier** is shared. But the receiver currently validates the **local URL path**. Without a resolver/transfer step, a different local path means it won’t auto‑load (you’ll see *needs download*).

**Can we explore together as if walking around?**  
Yes. With `supportsGroupImmersiveSpace = true` the system establishes a **shared coordinate space** in the immersive experience. Nearby and FaceTime participants can move and point while seeing the same content alignment. The tests in **Phase C** confirm this behavior.