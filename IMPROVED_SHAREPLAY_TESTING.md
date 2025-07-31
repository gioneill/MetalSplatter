# Improved SharePlay Testing Guide

This guide provides a comprehensive approach to testing the SharePlay features in MetalSplatter, with a focus on ensuring a robust and intuitive shared experience.

## Core Concepts

- **Model Synchronization**: The SharePlay session identifies 3D models by their **filename**, not their full file path. For a shared experience to work, all participants must have a local copy of the `.ply` or `.splat` file with the **exact same filename** (e.g., `garden.ply`). The host does not transmit the model file itself.
- **Shared Spatial Experience**: The session is designed for all participants to explore the 3D model together. Camera movements (position and rotation) are synchronized across all devices in real-time, allowing you to "walk through" the space together.
- **Host & Participant**: The user who initiates the SharePlay session is the "Host." Others who join are "Participants." Some actions, like changing the model, can only be done by the Host.

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

---

## Summary of Key Verification Points

- **Filename is Key**: Confirm that model synchronization relies on matching filenames.
- **No File Transfer**: Understand that participants must have local copies of the files.
- **Truly Shared Space**: Verify that the camera is fully synchronized, enabling a collaborative exploration experience.
- **Graceful Failures**: Ensure the app handles missing models and other errors without crashing.
