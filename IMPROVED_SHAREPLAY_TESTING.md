# Improved SharePlay Testing Guide - visionOS 26 Enhanced

This guide provides a comprehensive approach to testing the SharePlay features in MetalSplatter, with a focus on ensuring a robust and intuitive shared experience. **Updated for visionOS 26 with nearby participants support and enhanced spatial features.**

## Core Concepts

- **Model Synchronization**: The SharePlay session identifies 3D models by their **filename**, not their full file path. For a shared experience to work, all participants must have a local copy of the `.ply` or `.splat` file with the **exact same filename** (e.g., `garden.ply`). The host does not transmit the model file itself.
- **Shared Spatial Experience**: The session is designed for all participants to explore the 3D model together. Camera movements (position and rotation) are synchronized across all devices in real-time, allowing you to "walk through" the space together.
- **Host & Participant**: The user who initiates the SharePlay session is the "Host." Others who join are "Participants." Some actions, like changing the model, can only be done by the Host.

## visionOS 26 New Features

- **Nearby Participants Support**: SharePlay now supports inviting nearby people wearing Apple Vision Pro to join group activities directly, without requiring FaceTime calls.
- **Mixed Participant Types**: Sessions can include both nearby participants (appear via passthrough) and remote participants (appear as spatial Personas).
- **Enhanced Spatial Positioning**: The system distinguishes between actual participant poses and assigned seat poses, with different handling for nearby vs remote participants.
- **Share Window Menu**: Activities are discoverable through the new Share Window menu in visionOS 26.
- **No FaceTime Requirement**: Activities can be started without requiring an active FaceTime call (presents Share Window menu instead).

## Prerequisites

- Two or more Vision Pro devices (or a mix of real devices and simulators).
- All devices signed into the same Apple ID for FaceTime.
- The MetalSplatter application installed on all devices.
- At least one `.ply` or `.splat` file with the **same filename** saved on all testing devices. To test model switching, have multiple files with the same filenames across devices.

---

## Test Plan

### Test Case 1: Session Initiation and Model Sync

**Objective**: Verify that a SharePlay session starts correctly and all participants load the correct, synchronized model.

1.  **Pre-Test Setup**:
    -   Ensure `model_A.ply` exists on all devices.
    -   Ensure `model_B.ply` exists on all devices.
    -   Ensure `model_C.ply` exists **only on the Host device**.

2.  **Steps**:
    1.  **Host**: Launch MetalSplatter.
    2.  **Host**: Load `model_A.ply`.
    3.  **Host**: Start a FaceTime call with the other participants.
    4.  **Host**: From the FaceTime controls, start SharePlay and select MetalSplatter.
    5.  **Participants**: Accept the SharePlay invitation.

3.  **Expected Results**:
    -   ✅ `model_A.ply` loads automatically on all Participant devices.
    -   ✅ The initial camera view of the model is identical for all users.

### Test Case 2: Shared Spatial Exploration

**Objective**: Confirm that camera movements are synchronized smoothly and intuitively for all users.

1.  **Steps**:
    1.  **Host**: Use the **Index+Thumb Pinch** gesture to move the camera view.
    2.  **All**: Observe the camera movement.
    3.  **A Participant**: Use the **Middle+Thumb Pinch** gesture to rotate the camera view.
    4.  **All**: Observe the camera rotation.
    5.  **Host**: Use the **Two-Hand Pinch** gesture to zoom in and out.
    6.  **All**: Observe the zoom change.
    7.  **Simultaneous Input**: Have two users attempt to control the camera at the same time with different gestures.

3.  **Expected Results**:
    -   ✅ All camera movements, rotations, and zooms are reflected on all devices in near real-time (<100ms latency).
    -   ✅ The experience should feel as if you are all looking through a single, shared camera.
    -   ✅ For simultaneous inputs, the system should gracefully handle the conflict, typically by responding to the last input received without jitter or erratic behavior.

### Test Case 3: Model Switching by Host

**Objective**: Ensure the Host can seamlessly switch the model for everyone in the session.

1.  **Steps**:
    1.  While in an active SharePlay session with `model_A.ply` loaded.
    2.  **Host**: Load `model_B.ply`.

3.  **Expected Results**:
    -   ✅ `model_B.ply` loads automatically on all Participant devices.
    -   ✅ The camera position resets to a default, appropriate view for the new model on all devices.
    -   ✅ Shared camera controls (move, rotate, zoom) continue to work correctly with the new model.

### Test Case 4: Participant Does Not Have the Model

**Objective**: Test the failure case where a participant is invited to a session for a model they do not have locally.

1.  **Steps**:
    1.  **Host**: Load `model_C.ply` (which only exists on the Host device).
    2.  **Host**: Start a SharePlay session and invite participants.

3.  **Expected Results**:
    -   ✅ The Participant's app should handle this gracefully. It should **not** crash.
    -   ✅ Ideally, the Participant's app displays a user-friendly error message, such as "Could not join session. Model file not found: `model_C.ply`."

### Test Case 5: Participant Lifecycle

**Objective**: Verify that participants joining or leaving does not disrupt the session for others.

1.  **Steps**:
    1.  Start a session with three users (1 Host, 2 Participants).
    2.  **Host**: Move the camera to a non-default position.
    3.  **Participant A**: Leaves the FaceTime call.
    4.  **Host & Participant B**: Continue to move the camera.
    5.  **Participant A**: Rejoins the FaceTime call and the SharePlay session.

3.  **Expected Results**:
    -   ✅ When Participant A leaves, the session continues uninterrupted for the Host and Participant B.
    -   ✅ When Participant A rejoins, their view syncs immediately to the current, shared camera position (the non-default one).

### Test Case 6: Network Interruption

**Objective**: Test the system's resilience to network instability.

1.  **Steps**:
    1.  Start a session and move the camera to a non-default position.
    2.  **On one device**: Turn off Wi-Fi for 15-20 seconds.
    3.  **On another device**: Continue to move and rotate the camera.
    4.  **On the disconnected device**: Turn Wi-Fi back on.

3.  **Expected Results**:
    -   ✅ When the device reconnects, its camera view should quickly sync to the current state of the shared session. There should be no lingering "desync."

### Test Case 7: Immersive Scene Synchronization

**Objective**: Verify that immersive scene state is synchronized across all participants with proper file validation.

1. **Pre-Test Setup**:
   - Ensure `garden.splat` exists on all devices.
   - Ensure `cafe.splat` exists on all devices.
   - Ensure `missing.splat` exists **only on the Host device**.

2. **Steps**:
   1. **Host**: Start a SharePlay session while in the main window view.
   2. **Participants**: Join the session.
   3. **Host**: Load `garden.splat` and enter immersive space.
   4. **All**: Observe the transition.
   5. **Host**: Exit immersive space using "Dismiss Immersive Space" button.
   6. **All**: Observe the transition back to window view.
   7. **Host**: Load `missing.splat` and attempt to enter immersive space.
   8. **Participants**: Observe the file picker behavior.

3. **Expected Results**:
   - ✅ When Host enters immersive space, Participants receive a file picker prompt immediately.
   - ✅ File picker validates that participants select the matching filename.
   - ✅ If wrong file is selected, a helpful alert appears: "Wrong File - Please pick the same file the host chose: `filename.splat`"
   - ✅ File picker re-shows after wrong file selection.
   - ✅ Once correct file is selected, all participants enter immersive space together automatically.
   - ✅ When Host exits immersive space, all participants exit together automatically.
   - ✅ Camera synchronization continues to work in both window and immersive modes.
   - ✅ For missing files, participants see clear error messaging.
   - ✅ Participants can cancel file picker to choose not to join immersive experience.

### Test Case 8: Origin Synchronization

**Objective**: Verify that origin changes are synchronized across all participants.

1. **Steps**:
   1. Start a session with `model_A.ply` loaded on all devices.
   2. **Host**: Move the camera to a specific non-default position.
   3. **Host**: Press "Set new origin" button.
   4. **All**: Observe the "New origin saved!" message appears.
   5. **Participant A**: Move the camera to a different position.
   6. **Host**: Load a different model `model_B.ply`.
   7. **All**: Verify all participants see the same model with Host's saved origin.
   8. **Host**: Return to `model_A.ply`.
   9. **All**: Verify the camera returns to the origin set in step 3.

3. **Expected Results**:
   - ✅ When Host sets new origin, all participants' camera positions update immediately to match.
   - ✅ All participants see the "New origin saved!" confirmation message.
   - ✅ The new origin is saved and persists when switching models and returning.
   - ✅ Origin synchronization works in both window and immersive viewing modes.

### Test Case 9: visionOS 26 Nearby Participants (NEW)

**Objective**: Test the new nearby participants functionality introduced in visionOS 26.

1. **Pre-Test Setup**:
   - Two Vision Pro devices in the same physical room.
   - Both devices have MetalSplatter installed.
   - Both devices have `garden.splat` with identical filenames.

2. **Steps**:
   1. **Host**: Load `garden.splat` in MetalSplatter.
   2. **Host**: Start SharePlay activity (no FaceTime call required in visionOS 26).
   3. **Host**: Observe Share Window menu appears.
   4. **Host**: Use Share Window menu to invite nearby participants.
   5. **Nearby Participant**: Accept the nearby invitation.
   6. **Host**: Move around physically while controlling the camera.
   7. **Nearby Participant**: Move around physically.
   8. **Both**: Test camera synchronization with physical movement.

3. **Expected Results**:
   - ✅ Share Window menu appears when starting activity without active FaceTime call.
   - ✅ Nearby participant appears via passthrough (physical presence visible).
   - ✅ System logs show "nearby=true" for the nearby participant.
   - ✅ Content positioning adapts to nearby participant's actual physical location.
   - ✅ Camera synchronization works with mixed physical/virtual positioning.

### Test Case 10: visionOS 26 Mixed Participant Types (NEW)

**Objective**: Test sessions with both nearby and remote participants simultaneously.

1. **Pre-Test Setup**:
   - Two Vision Pro devices in the same room (nearby participants).
   - One Vision Pro device in a different location (remote participant).
   - All devices have `model_A.ply` with identical filenames.

2. **Steps**:
   1. **Host**: Start SharePlay session and invite both nearby and remote participants.
   2. **Remote Participant**: Join via FaceTime/spatial Persona.
   3. **Nearby Participant**: Join via nearby invitation.
   4. **All**: Observe participant representation differences.
   5. **Host**: Enter immersive space.
   6. **All**: Test positioning and spatial template application.
   7. **Each participant**: Take turns moving the camera.

3. **Expected Results**:
   - ✅ Nearby participants appear via passthrough.
   - ✅ Remote participants appear as spatial Personas.
   - ✅ System logs distinguish participant types correctly.
   - ✅ Spatial template positioning works for both participant types.
   - ✅ Camera synchronization works across mixed participant types.

### Test Case 11: visionOS 26 Enhanced Spatial Positioning (NEW)

**Objective**: Verify the new pose vs seat positioning logic for different participant types.

1. **Steps**:
   1. Start a mixed session (nearby + remote participants).
   2. **Host**: Enter immersive space to activate spatial templates.
   3. **All**: Observe initial positioning.
   4. **Nearby Participant**: Move to a different physical location.
   5. **Remote Participant**: Stay in their assigned spatial Persona seat.
   6. **Host**: Check console logs for positioning data.
   7. **All**: Test content interaction from different positions.

3. **Expected Results**:
   - ✅ Console logs show "Using actual pose for nearby participant".
   - ✅ Console logs show "Using seat pose for remote participant".
   - ✅ Nearby participants' content positioning follows their actual physical location.
   - ✅ Remote participants' content positioning uses their assigned seats.
   - ✅ No positioning conflicts or jitter between participant types.

---

## Summary of Key Verification Points

### Core SharePlay Features
- **Filename is Key**: Confirm that model synchronization relies on matching filenames.
- **No File Transfer**: Understand that participants must have local copies of the files.
- **Truly Shared Space**: Verify that the camera is fully synchronized, enabling a collaborative exploration experience.
- **Graceful Failures**: Ensure the app handles missing models and other errors without crashing.
- **Immersive Scene Sync**: Host can transition all participants between window and immersive modes.
- **File Validation**: Recipients must pick the exact same file to join immersive experiences.
- **Origin Synchronization**: Origin changes by any participant are immediately reflected for all participants.

### visionOS 26 Enhanced Features
- **Nearby Participants**: Verify support for nearby Vision Pro users joining without FaceTime calls.
- **Mixed Participant Types**: Test sessions with both nearby (passthrough) and remote (spatial Persona) participants.
- **Share Window Menu**: Confirm activities are discoverable through the new Share Window menu.
- **Enhanced Positioning**: Verify proper handling of actual poses vs assigned seats for different participant types.
- **No FaceTime Requirement**: Test that activities can start without active FaceTime calls.
- **Console Logging**: Monitor enhanced logging that distinguishes participant types and positioning logic.

## Implementation Status

✅ **Completed visionOS 26 Enhancements:**
- Nearby participants support with `isNearbyWithLocalParticipant` detection
- Enhanced SystemCoordinator monitoring with `remoteParticipantStates`
- Advanced spatial positioning logic with pose vs seat distinction
- Share Window menu integration with hidden ShareLink
- Activity activation without `isEligibleForGroupSession` checks
- Proper GroupActivity Transferable support
- Scene association configuration for proper activity routing
