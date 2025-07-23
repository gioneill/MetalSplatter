<!--
Downloaded via https://llm.codes by @steipete on June 30, 2025 at 03:42 PM
Source URL: https://developer.apple.com/documentation/groupactivities/configure-your-app-for-sharing-with-people-nearby?changes=_2
Total pages processed: 158
URLs filtered: Yes
Content de-duplicated: Yes
Availability strings filtered: Yes
Code blocks only: No
-->

# https://developer.apple.com/documentation/groupactivities/configure-your-app-for-sharing-with-people-nearby?changes=_2

- Group Activities
- Configure your visionOS app for sharing with people nearby

Article

# Configure your visionOS app for sharing with people nearby

Create shared experiences for people wearing Vision Pro in the same room and those on FaceTime.

## Overview

SharePlay in visionOS helps people share activities together — for example, viewing a movie, listening to music, playing a game, or sketching ideas on a whiteboard. Starting in visionOS 26, SharePlay supports inviting nearby people who are wearing Apple Vision Pro to join a group activity. The system presents participants differently based on how they join the activity:

- Nearby participants appear naturally via passthrough.

- FaceTime participants who are wearing Apple Vision Pro appear as spatial Personas.

- Participants on other devices appear in a standard FaceTime window.

Both nearby participants and spatial Personas can move spatially, make eye contact, and reference virtual content during an activity, enhancing the feeling of being together in the same room. Get your visionOS app ready for sharing with people nearby by reviewing the APIs below that help you create seamless connections among people — whether they’re in the same room or on FaceTime.

### Verify your app’s nearby-sharing behavior

SharePlay doesn’t require apps to distinguish between nearby and FaceTime participants. The `GroupActivities` APIs you use to manage group sessions, exchange messages, and position content treat all participants the same. Your app doesn’t need separate code to support nearby participants, so it typically already works when sharing with people nearby, but confirm the following during testing:

Spatial assumptions

Confirm that your app doesn’t rely on the system to position nearby participants in specific locations. SharePlay can dynamically reposition spatial Personas (FaceTime participants), but not physical people (nearby participants). If your app requires participants to be in specific locations, guide nearby participants to move to those locations using visual cues, like position markers.

Share Window menu

Confirm that your activity is listed in the new Share Window menu located next to the window bar. This is critical for the discovery of your app’s SharePlay activity. The easiest way to add your activity to the Share Window menu is to include a hidden `ShareLink` in your app.

ShareLink(item: BoardGameActivity(), preview: SharePreview("Play Together"))
.hidden()

For more information, see Presenting SharePlay activities from your app’s UI.

Activity activation

If your app implements a custom SharePlay button, confirm that your app supports initiating an activity when there isn’t an active FaceTime call. For visionOS, update the button’s action handler to always call `activate()`, which now presents the new Share Window menu, and remove any checks for `isEligibleForGroupSession` that guard activating the activity.

### Distinguish between nearby and FaceTime participants

To observe when participants join and leave an activity use `activeParticipants`. To determine if a `Participant` is nearby, use `isNearbyWithLocalParticipant`:

for await activeParticipants in session.$activeParticipants.values {
// The set of nearby participants, excluding the local participant.
let nearbyParticipants = activeParticipants.filter {
$0.isNearbyWithLocalParticipant && $0.id != session.localParticipant.id
}
}
}

### Position content relative to participants

Because nearby participants can join a group activity, you can no longer assume a spatial participant’s pose (position and orientation) matches their seat’s pose. When SharePlay applies a `SpatialTemplate`, it moves FaceTime participants using their spatial Persona to their assigned seats so their pose matches their seat’s pose. SharePlay can’t move a nearby participant, so the participant’s pose can be different from their seat’s pose.

- To observe the state of remote FaceTime and nearby participants use `remoteParticipantStates`.

- To observe the state of the local participant, who is wearing Vision Pro, use `localParticipantStates`.

- To position content relative to a participant, position the content relative to `ParticipantState.pose`.

- To position content relative to a participant’s seat, position the content relative to `ParticipantState.seat.pose`.

### Synchronize entity transforms across devices

To achieve consistent positioning of RealityKit entities across multiple devices in an immersive space during a SharePlay session, enable support for a group immersive space using `SystemCoordinator.Configuration.supportsGroupImmersiveSpace`. When enabled, visionOS automatically ensures entities with identical transforms appear in the same relative location for all participants, including both nearby and remote participants.

Group immersive spaces handle this spatial consistency for entities with identical transforms, but keep in mind that SharePlay doesn’t automatically synchronize changes to your app’s state. Your app needs to maintain visual consistency across participants’ devices and you have full control over what actions are synchronized. For example, if your app displays a cube with a position of `[0, 1, 0]` at launch, the shared coordinate system causes everyone to see that cube at the same position. However, if a participant creates a new cube, your app needs to use the `GroupSessionMessenger` to notify the other participants to reflect this change.

### Incorporate the real world in your app’s shared context

When you’re sharing with people who are nearby, you may want to anchor shared virtual content to objects in the real world. Unlike remote SharePlay with spatial Personas, when you’re sharing with someone nearby, the real world is part of your shared context. To enable this, ARKit has support for sharing world anchors that appear in the exact same place for all nearby participants.

To make a `WorldAnchor` shareable with nearby participants, initialize the anchor with the `isSharedWithNearbyParticipants` property set to `true` with the `init(originFromAnchorTransform:sharedWithNearbyParticipants:)` initializer. ARKit then shares that anchor with all nearby SharePlay participants via the `anchorUpdates` async sequence.

Your app can then attach an entity to that anchor to place it in the exact same world location for all nearby participants.

// Create a shared world anchor with ARKit.

func setUp(session: ARKitSession, provider: WorldTrackingProvider) async throws {
try await session.run([provider])
}

func createAnchor(
at transform: simd_float4x4,
provider: WorldTrackingProvider
) async throws {
// Create a world anchor with `sharedWithNearbyParticipants` set to `true`.
let anchor = WorldAnchor(
originFromAnchorTransform: transform,
sharedWithNearbyParticipants: true
)
try await provider.addAnchor(anchor)
}

func observeWorldTracking(provider: WorldTrackingProvider) async {
for await update in provider.anchorUpdates {
switch update.event {
case .added, .updated, .removed:
// Updates with shared anchors from others.
let anchorIdentifier = update.anchor.id
}
}
}

## See Also

### Spatial activities

Adding spatial Persona support to an activity

Update your SharePlay activities to support spatial Personas and the shared context when running in visionOS.

`class SystemCoordinator`

A type you use to coordinate your interface’s behavior when an active SharePlay session supports spatial placement of content.

`struct ParticipantState`

A structure that tells you whether a participant supports a shared simulation space for the current activity.

`](https://developer.apple.com/documentation/SwiftUI/View/groupActivityAssociation(_:)?changes=_2)

Specifies how a view should be associated with the current SharePlay group activity.

Beta

`class GroupActivityAssociationInteraction`

An interaction configures a view’s association with the current SharePlay group activity.

`struct GroupActivityAssociationKind`

An association a user-interface element can have with a SharePlay group activity.

---

# https://developer.apple.com/documentation/groupactivities/configure-your-app-for-sharing-with-people-nearby

- Group Activities
- Configure your visionOS app for sharing with people nearby

Article

# Configure your visionOS app for sharing with people nearby

Create shared experiences for people wearing Vision Pro in the same room and those on FaceTime.

## Overview

SharePlay in visionOS helps people share activities together — for example, viewing a movie, listening to music, playing a game, or sketching ideas on a whiteboard. Starting in visionOS 26, SharePlay supports inviting nearby people who are wearing Apple Vision Pro to join a group activity. The system presents participants differently based on how they join the activity:

- Nearby participants appear naturally via passthrough.

- FaceTime participants who are wearing Apple Vision Pro appear as spatial Personas.

- Participants on other devices appear in a standard FaceTime window.

Both nearby participants and spatial Personas can move spatially, make eye contact, and reference virtual content during an activity, enhancing the feeling of being together in the same room. Get your visionOS app ready for sharing with people nearby by reviewing the APIs below that help you create seamless connections among people — whether they’re in the same room or on FaceTime.

### Verify your app’s nearby-sharing behavior

SharePlay doesn’t require apps to distinguish between nearby and FaceTime participants. The `GroupActivities` APIs you use to manage group sessions, exchange messages, and position content treat all participants the same. Your app doesn’t need separate code to support nearby participants, so it typically already works when sharing with people nearby, but confirm the following during testing:

Spatial assumptions

Confirm that your app doesn’t rely on the system to position nearby participants in specific locations. SharePlay can dynamically reposition spatial Personas (FaceTime participants), but not physical people (nearby participants). If your app requires participants to be in specific locations, guide nearby participants to move to those locations using visual cues, like position markers.

Share Window menu

Confirm that your activity is listed in the new Share Window menu located next to the window bar. This is critical for the discovery of your app’s SharePlay activity. The easiest way to add your activity to the Share Window menu is to include a hidden `ShareLink` in your app.

ShareLink(item: BoardGameActivity(), preview: SharePreview("Play Together"))
.hidden()

For more information, see Presenting SharePlay activities from your app’s UI.

Activity activation

If your app implements a custom SharePlay button, confirm that your app supports initiating an activity when there isn’t an active FaceTime call. For visionOS, update the button’s action handler to always call `activate()`, which now presents the new Share Window menu, and remove any checks for `isEligibleForGroupSession` that guard activating the activity.

### Distinguish between nearby and FaceTime participants

To observe when participants join and leave an activity use `activeParticipants`. To determine if a `Participant` is nearby, use `isNearbyWithLocalParticipant`:

for await activeParticipants in session.$activeParticipants.values {
// The set of nearby participants, excluding the local participant.
let nearbyParticipants = activeParticipants.filter {
$0.isNearbyWithLocalParticipant && $0.id != session.localParticipant.id
}
}
}

### Position content relative to participants

Because nearby participants can join a group activity, you can no longer assume a spatial participant’s pose (position and orientation) matches their seat’s pose. When SharePlay applies a `SpatialTemplate`, it moves FaceTime participants using their spatial Persona to their assigned seats so their pose matches their seat’s pose. SharePlay can’t move a nearby participant, so the participant’s pose can be different from their seat’s pose.

- To observe the state of remote FaceTime and nearby participants use `remoteParticipantStates`.

- To observe the state of the local participant, who is wearing Vision Pro, use `localParticipantStates`.

- To position content relative to a participant, position the content relative to `ParticipantState.pose`.

- To position content relative to a participant’s seat, position the content relative to `ParticipantState.seat.pose`.

### Synchronize entity transforms across devices

To achieve consistent positioning of RealityKit entities across multiple devices in an immersive space during a SharePlay session, enable support for a group immersive space using `SystemCoordinator.Configuration.supportsGroupImmersiveSpace`. When enabled, visionOS automatically ensures entities with identical transforms appear in the same relative location for all participants, including both nearby and remote participants.

Group immersive spaces handle this spatial consistency for entities with identical transforms, but keep in mind that SharePlay doesn’t automatically synchronize changes to your app’s state. Your app needs to maintain visual consistency across participants’ devices and you have full control over what actions are synchronized. For example, if your app displays a cube with a position of `[0, 1, 0]` at launch, the shared coordinate system causes everyone to see that cube at the same position. However, if a participant creates a new cube, your app needs to use the `GroupSessionMessenger` to notify the other participants to reflect this change.

### Incorporate the real world in your app’s shared context

When you’re sharing with people who are nearby, you may want to anchor shared virtual content to objects in the real world. Unlike remote SharePlay with spatial Personas, when you’re sharing with someone nearby, the real world is part of your shared context. To enable this, ARKit has support for sharing world anchors that appear in the exact same place for all nearby participants.

To make a `WorldAnchor` shareable with nearby participants, initialize the anchor with the `isSharedWithNearbyParticipants` property set to `true` with the `init(originFromAnchorTransform:sharedWithNearbyParticipants:)` initializer. ARKit then shares that anchor with all nearby SharePlay participants via the `anchorUpdates` async sequence.

Your app can then attach an entity to that anchor to place it in the exact same world location for all nearby participants.

// Create a shared world anchor with ARKit.

func setUp(session: ARKitSession, provider: WorldTrackingProvider) async throws {
try await session.run([provider])
}

func createAnchor(
at transform: simd_float4x4,
provider: WorldTrackingProvider
) async throws {
// Create a world anchor with `sharedWithNearbyParticipants` set to `true`.
let anchor = WorldAnchor(
originFromAnchorTransform: transform,
sharedWithNearbyParticipants: true
)
try await provider.addAnchor(anchor)
}

func observeWorldTracking(provider: WorldTrackingProvider) async {
for await update in provider.anchorUpdates {
switch update.event {
case .added, .updated, .removed:
// Updates with shared anchors from others.
let anchorIdentifier = update.anchor.id
}
}
}

## See Also

### Spatial activities

Adding spatial Persona support to an activity

Update your SharePlay activities to support spatial Personas and the shared context when running in visionOS.

`class SystemCoordinator`

A type you use to coordinate your interface’s behavior when an active SharePlay session supports spatial placement of content.

`struct ParticipantState`

A structure that tells you whether a participant supports a shared simulation space for the current activity.

`](https://developer.apple.com/documentation/SwiftUI/View/groupActivityAssociation(_:)?changes=_2)

Specifies how a view should be associated with the current SharePlay group activity.

Beta

`class GroupActivityAssociationInteraction`

An interaction configures a view’s association with the current SharePlay group activity.

`struct GroupActivityAssociationKind`

An association a user-interface element can have with a SharePlay group activity.

---

# https://developer.apple.com/documentation/groupactivities

Framework

# Group Activities

Create app-specific activities your users can share and experience together.

## Overview

With the Group Activities framework, you can provide your app’s content in SharePlay experiences, which create a sense of connection and immediacy for your users. For example, a video-streaming app might offer the ability to attend movie-watching parties in which participants watch simultaneously from their personal devices. The app handles the playback on each device, but the Group Activities framework synchronizes that playback and facilitates communication between the devices.

This framework leverages the FaceTime infrastructure to synchronize your app’s activities and to invite other participants to join those activities. When your app’s UI contains shareable activities, adopt the `GroupActivity` protocol in the objects you use to represent those activities. When a group activity begins, use the `GroupSession` object to synchronize your app’s behavior with other participating devices.

## Topics

### Essentials

`com.apple.developer.group-session`

A Boolean value that indicates whether the app may implement shared group experiences.

### Activity definition

Defining your app’s SharePlay activities

Configure your app’s SharePlay support and define the activities that people can perform from your app.

Supporting Coordinated Media Playback

Create synchronized media experiences that enable users to watch and listen across devices.

`protocol GroupActivity`

A type that can advertise your app’s activities to other participants.

`struct GroupActivityMetadata`

Text and image content that describes an activity to potential participants.

`enum GroupActivityActivationResult`

The result of preparing to start a custom activity.

`struct GroupActivityTransferRepresentation`

A type that lets you start a group activity from a known context.

### Interface presentation

Presenting SharePlay activities from your app’s UI

Make it easy for people to start activities from your app’s UI, from the system share sheet, or using AirPlay over AirDrop.

`class GroupActivitySharingController`

A macOS view controller that displays the system interface for starting an activity, and optionally starts a FaceTime call for that activity.

An iOS view controller that displays the system interface for starting an activity, and optionally starts a FaceTime call for that activity.

### Session management

Joining and managing a shared activity

Configure the session when a SharePlay activity starts, and handle events that occur during the lifetime of the activity.

Drawing content in a group session

Invite your friends to draw on a shared canvas while on a FaceTime call.

`class GroupSession`

A session for an in-progress activity that synchronizes content among participant devices.

`protocol CustomMessageIdentifiable`

A type that assigns a custom ID string to messages you send to other devices.

`struct Participant`

An active participant in a group session.

### Spatial activities

Configure your visionOS app for sharing with people nearby

Create shared experiences for people wearing Vision Pro in the same room and those on FaceTime.

Adding spatial Persona support to an activity

Update your SharePlay activities to support spatial Personas and the shared context when running in visionOS.

`class SystemCoordinator`

A type you use to coordinate your interface’s behavior when an active SharePlay session supports spatial placement of content.

`struct ParticipantState`

A structure that tells you whether a participant supports a shared simulation space for the current activity.

`](https://developer.apple.com/documentation/SwiftUI/View/groupActivityAssociation(_:))

Specifies how a view should be associated with the current SharePlay group activity.

Beta

`class GroupActivityAssociationInteraction`

An interaction configures a view’s association with the current SharePlay group activity.

`struct GroupActivityAssociationKind`

An association a user-interface element can have with a SharePlay group activity.

### Custom spatial templates

Building a guessing game for visionOS

Create a team-based guessing game for visionOS using Group Activities.

`protocol SpatialTemplate`

An interface you use to create custom arrangements of spatial Personas in a scene.

`struct SpatialTemplatePreference`

A structure that specifies the preferred arrangement of participant spatial Personas in a shared simulation space.

`struct SpatialTemplateSeatElement`

A spatial template element that represents a seat for a participant in the activity.

`protocol SpatialTemplateElement`

An interface that defines an element in your spatial template.

`struct SpatialTemplateElementPosition`

A type that defines the position of an element in a spatial template.

`struct SpatialTemplateElementDirection`

The initial direction a participant faces when an activity starts.

`protocol SpatialTemplateRole`

An interface for defining roles that you assign to the participants of a group activity.

### File and data transfer

Synchronizing data during a SharePlay activity

Send custom messages and data between devices to synchronize content for your activity, and incorporate messages your app receives from other participants.

`class GroupSessionMessenger`

An object that transfers app-specific data between the devices joined in a group session.

`class GroupSessionJournal`

An object that manages file and data transfers between participants joined in a group session.

### System status

`class GroupStateObserver`

An object that contains information about the system’s ability to start SharePlay experiences.

---

# https://developer.apple.com/documentation/groupactivities/promoting-shareplay-activities-from-your-apps-ui

- Group Activities
- Presenting SharePlay activities from your app’s UI

Article

# Presenting SharePlay activities from your app’s UI

Make it easy for people to start activities from your app’s UI, from the system share sheet, or using AirPlay over AirDrop.

## Overview

After you define one or more SharePlay activities for your app, make them easy for people to discover in your UI. Include buttons, menus items, and other elements to start activities, present activities in system interfaces like the share sheet, and update your activities to take advantage of other system behaviors.

Starting an activity requires an active FaceTime call or Messages conversation. When a conversation is active, you can start an activity right away from your UI. If no conversation is active, the Group Activities framework facilitates starting a conversation as part of starting your activity. Some system features also help you start conversations.

### Add a SharePlay button to your UI

The most direct way to start activities is to provide controls in your UI. Because you control the placement of buttons and other controls in your UI, you can put them where people are most likely to find them. Provide a label or additional context to let someone know that your UI element starts an activity. For example, update your button’s label to include the `shareplay` symbol from the SF Symbols library.

The following example shows a SwiftUI button with both a text label and the SharePlay icon:

Button {
// Start the activity.
} label: {
Label("Start Activity", systemImage: "shareplay")
}
.buttonStyle(.borderedProminent)

In iOS, the preceding example creates a button with a prominent appearance as shown below. When creating buttons in your app, use a style that makes sense for the current platform and your app’s design.

When someone interacts with your app’s custom buttons, start the corresponding activity immediately if there is an active FaceTime call or Messages conversation. To determine if a conversation is active, check the `isEligibleForGroupSession` property of `GroupStateObserver`. If the value of that property is true, call the `prepareForActivation()` or `activate()` method of your `GroupActivity` type to start the activity. If the value of the property is `false`, present a `GroupActivitySharingController`, which prompts the person to invite friends to join the activity.

### Share activities in SwiftUI using a share link

To surface SharePlay activities using the system share sheet in SwiftUI, configure a `ShareLink` view with items that have an associated activity. A `ShareLink` view adds a standard share button to your UI, and you can customize the appearance of that button using the `buttonStyle(_:)` modifier. Tapping or clicking the button displays the system share sheet for the provided items. A person can then use the sheet to copy the items to the pasteboard or send them to a different process.

To surface your SharePlay activities from a `ShareLink` view, include a representation that contains your `GroupActivity` type. The share sheet in SwiftUI requires items to support the `Transferable` protocol. Adopt this protocol in your custom data types and implement the `transferRepresentation` property. Use that property to supply the representations of your data, and add a `GroupActivityTransferRepresentation` type to specify the `GroupActivity` for that data.

The following example shows the implementation of a movie data type and its `transferRepresentation` property. The property returns two representations: one for the movie’s URL and one for the movie-watching activity. The closure for the `GroupActivityTransferRepresentation` creates the `WatchMovieTogether` activity and initializes it with the selected movie.

struct Movie : Transferable {
var title : String
var url: URL

static var transferRepresentation: some TransferRepresentation {
// Export the movie as a URL.
ProxyRepresentation(exporting: \.url)

// Specify the associated SharePlay activity.
GroupActivityTransferRepresentation { movie in
WatchMovieTogether(from: movie)
}
}
}

The following example creates a `ShareLink` to share a movie associated with the current view. When someone displays the share sheet and clicks the SharePlay link, the system initializes the app’s `WatchMovieTogether` activity with the specified movie and starts the activity.

ShareLink(item: movie,
preview: .init("Play the movie together"))

### Add activities to the system share sheet in UIKit or AppKit

When displaying a share sheet using UIKit or AppKit, specify any SharePlay activities using `NSItemProvider` objects. When you configure the UIKit or AppKit share sheets, you specify one or more `NSItemProvider` objects with the data you want to share. If you have an activity you want to share for that item, create an instance of the appropriate `GroupActivity` type and pass it to the item provider’s `registerGroupActivity(_:)` method. When an item provider has a registered activity, the share sheet displays a SharePlay button to start the associated activity.

The following example creates a `WatchMovieTogether` activity to allow friends to watch a movie over SharePlay. After it creates an item provider for the movie, it registers the activity with that item provider and displays the share sheet. When someone clicks the SharePlay button in the share sheet, the system starts the movie-watching activity.

let activity = WatchMovieTogether(movie: movie)

// Create an item provider for the activity.
if let itemProvider = NSItemProvider(contentsOf: movie.url) {
itemProvider.registerGroupActivity(activity)

// Create and present the share sheet.
let shareSheet = UIActivityViewController(activityItems: [itemProvider], applicationActivities: nil)
shareSheet.allowsProminentActivity = true

present(shareSheet, animated: true)
}

In AppKit, display the share sheet using an `NSSharingServicePicker` object. When creating the picker object, specify your `NSItemProvider` objects as the items you want to share.

### Share activities using SharePlay over AirDrop

SharePlay over AirDrop lets one person initiate an activity on their iPhone and share that activity with people in close proximity. The initiator opens an app on their iPhone and navigates to a page with the activity they want to start. When their iPhone comes in close proximity to other people’s iPhone devices, the initiator’s phone prompts them to start the activity. After they start the activity, the system prompts the other people to join and creates a Messages conversation for the group. Anyone in the group can then invite others to join the conversation and activity, including people who aren’t nearby.

In a SwiftUI app, the system enables SharePlay over AirDrop when the UI contains a `ShareLink` with an appropriate activity. The activity you include in the link must adopt the `Transferable` protocol and provide a `GroupActivityTransferRepresentation` type in its set of representations.

To support SharePlay over AirDrop in a UIKit app, assign activities to objects in the responder chain of your app’s UI. Typically, you add activities to your app’s view controllers, but you can add activities to any responder. When devices are nearby, the system searches the responder chain for a responder that contains an activity in its `activityItemsConfiguration` property. If an activity is available, the system displays UI to start that activity on the initiator’s device. The `activityItemsConfiguration` property stores one or more `NSItemProvider` objects, which you configure with activities by calling the `registerGroupActivity(_:)` method.

### Display activities in the Share menu in visionOS

In a visionOS app, the system displays a Share menu above windows and volumes to indicate when sharing is active. The system populates this control with activities the current scene supports.

The Share menu is in the idle state, and sharing is not active for the window.

The person chooses an activity from the Share menu.

The Share menu is in the active state, and an activity is in progress.

Specify activities in any of the following ways:

- Include a `ShareLink` view with a properly configured activity, as described in Share activities using SharePlay over AirDrop.

- Configure the `activityItemsConfiguration` property of a UIKit responder object with an activity object.

- Associate an activity with the scene. See Adding spatial Persona support to an activity.

## See Also

### Interface presentation

`class GroupActivitySharingController`

A macOS view controller that displays the system interface for starting an activity, and optionally starts a FaceTime call for that activity.

An iOS view controller that displays the system interface for starting an activity, and optionally starts a FaceTime call for that activity.

---

# https://developer.apple.com/documentation/groupactivities/groupactivity/activate()

#app-main)

- Group Activities
- GroupActivity
- activate()

Instance Method

# activate()

Begins the activity immediately and creates a session for the app when a FaceTime call is active.

## Mentioned in

Configure your visionOS app for sharing with people nearby

Presenting SharePlay activities from your app’s UI

## Discussion

Typically, you call this method only when the `prepareForActivation()` method delivers the `GroupActivityActivationResult.activationPreferred` result. However, you may call it directly if your activity only makes sense in a group setting. For example, call it if the activity applies only to groups and can’t be performed without other participants.

If a FaceTime call is active, this method configures a session. The system also invites other participants to join the activity. If a session will be delivered to your app this function returns true, otherwise it returns false. A case where this function could return false is when a session is created and handed off to an Apple TV. If a call isn’t active or a session wasn’t created, this method throws an error

## See Also

### Starting an activity immediately

Returns the participant’s preferred option for how to start the activity.

`enum GroupActivityActivationResult`

The result of preparing to start a custom activity.

---

# https://developer.apple.com/documentation/groupactivities/groupstateobserver/iseligibleforgroupsession

- Group Activities
- GroupStateObserver
- isEligibleForGroupSession

Instance Property

# isEligibleForGroupSession

A Boolean value that indicates whether the system can start a group session.

@Published
final var isEligibleForGroupSession: Bool { get }

## Mentioned in

Presenting SharePlay activities from your app’s UI

Configure your visionOS app for sharing with people nearby

## Discussion

This property indicates whether a FaceTime call is active and the system can create group sessions. Configure a subscriber to this property to monitor changes to the system’s state. When the system can create group sessions, it sets the value of this property to `true`. When the creation of a group session isn’t possible, the system sets the value to `false`.

---

# https://developer.apple.com/documentation/groupactivities/groupsession/activeparticipants

- Group Activities
- GroupSession
- activeParticipants

Instance Property

# activeParticipants

The set of participants currently engaged in the activity.

@Published

## Mentioned in

Configure your visionOS app for sharing with people nearby

Joining and managing a shared activity

## Discussion

This property reflects the set of people invited to a group session and currently engaged in the shared activity on their device. Members who join the conversation over FaceTime but don’t join the shared activity aren’t active participants. As people join or leave the activity, the session object updates the set of active participants. To detect changes to this property, configure a subscriber.

Each `Participant` object corresponds to a joined session on a device. If a single person joins the activity from two devices simultaneously, the set contains a separate `Participant` object for each device.

## See Also

### Getting the participants

`var localParticipant: Participant`

The participant on the current device.

---

# https://developer.apple.com/documentation/groupactivities/participant

- Group Activities
- Participant

Structure

# Participant

An active participant in a group session.

struct Participant

## Mentioned in

Synchronizing data during a SharePlay activity

Configure your visionOS app for sharing with people nearby

## Overview

Use a `Participant` object to differentiate among users in a session. A participant object doesn’t contain any sensitive data about the user, but provides a unique identifier to distinguish the user while the session is active.

You don’t create participant objects directly. The system creates a participant object for each user that joins an activity. Access the current set of participants from the `activeParticipants` property of the `GroupSession` object associated with the activity.

## Topics

### Getting the unique identifier

`let id: UUID`

A globally unique identifier for the session participant.

### Comparing participants

Returns a Boolean value indicating whether two values are not equal.

Returns a Boolean value indicating whether two values are equal.

### Instance Properties

`var hashValue: Int`

The hash value.

`var isNearbyWithLocalParticipant: Bool`

A Boolean value that indicates whether the participant is physically nearby with the local participant.

Beta

### Instance Methods

`func hash(into: inout Hasher)`

Hashes the essential components of this value by feeding them into the given hasher.

### Type Aliases

`typealias ID`

A type representing the stable identity of the entity associated with an instance.

## Relationships

### Conforms To

- `Copyable`
- `CustomStringConvertible`
- `Equatable`
- `Hashable`
- `Identifiable`
- `Sendable`
- `SendableMetatype`

## See Also

### Session management

Joining and managing a shared activity

Configure the session when a SharePlay activity starts, and handle events that occur during the lifetime of the activity.

Drawing content in a group session

Invite your friends to draw on a shared canvas while on a FaceTime call.

`class GroupSession`

A session for an in-progress activity that synchronizes content among participant devices.

`protocol CustomMessageIdentifiable`

A type that assigns a custom ID string to messages you send to other devices.

---

# https://developer.apple.com/documentation/groupactivities/participant/isnearbywithlocalparticipant



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplate

- Group Activities
- SpatialTemplate

Protocol

# SpatialTemplate

An interface you use to create custom arrangements of spatial Personas in a scene.

protocol SpatialTemplate : Sendable

## Mentioned in

Configure your visionOS app for sharing with people nearby

## Overview

Use the `SpatialTemplate` protocol to specify an arrangement of participants for one of your app’s group activities in visionOS. A custom template can have any number of seats, with each seat occupying a precise location in the shared coordinate space. You can also assign roles to seats and use those roles to give participants a particular responsibility. For example, a game might divide participants into opposing teams using roles.

To specify the seat positions, implement the `elements` property and return an array with all of the possible seats you support. Specify the location of each seat relative to the app’s content, which is at the origin of the shared coordinate space. You specify locations as the number of meters from the origin along the x- and z-axes. For example, the following code specifies two seats one meter from the app window in different directions along the z-axis:

struct BasicTemplate: SpatialTemplate {
var elements: [any SpatialTemplateElement] = [\
.seat(position: .app.offsetBy(x: 0, z: 1)),\
.seat(position: .app.offsetBy(x: 0, z -1))\
]
}

If a seat doesn’t have an assigned role, any participant can occupy it. If you add a role to a seat, the participant must specifically acquire that role to occupy the seat. For example, a game might assign a team-specific role to players when they join that team. Choose the roles that make sense for your activity and implement them using the `SpatialTemplateRole` protocol.

The system orients each participant’s spatial Persona to face your app’s content by default. To change the direction someone faces, include that information when you specify the seat. For example, the following template has a presenter role and up to four audience members. The inclusion of direction parameters causes the presenter to look at the audience and the audience to look at the presenter by default.

struct SimplePresentation: SpatialTemplate {
enum Role: String, SpatialTemplateRole {
case presenter
}
let configuration = SpatialTemplateConfiguration(defaultInitiatorRole: Role.presenter)
var elements: [any SpatialTemplateElement] {
let audienceCenterPoint = SpatialTemplateElementPosition.app.offsetBy(x: 0, z: 4)
let presenter = SpatialTemplateSeatElement(
position: .app.offsetBy(x: -3, z: 1),
direction: .lookingAt(audienceCenterPoint),
role: Role.presenter
)
let audience: [any SpatialTemplateElement] = [\
.seat(position: audienceCenterPoint.offsetBy(x: -0.5, z: 0), direction: .lookingAt(presenter)),\
.seat(position: audienceCenterPoint.offsetBy(x: 0.5, z: 0), direction: .lookingAt(presenter)),\
.seat(position: audienceCenterPoint.offsetBy(x: -1.0, z: 0), direction: .lookingAt(presenter)),\
.seat(position: audienceCenterPoint.offsetBy(x: 1.0, z: 0), direction: .lookingAt(presenter)),\
]
return [presenter] + audience
}
}

## Topics

### Configuring the spatial template

`var configuration: SpatialTemplateConfiguration`

Information a spatial template uses to configure itself.

**Required** Default implementation provided.

`struct SpatialTemplateConfiguration`

A type that contains the configuration details for a spatial template.

### Placing the template seats

[`var elements: [any SpatialTemplateElement]`](https://developer.apple.com/documentation/groupactivities/spatialtemplate/elements)

The collection of spatial Persona seats this template contains.

**Required**

## Relationships

### Inherits From

- `Sendable`
- `SendableMetatype`

## See Also

### Custom spatial templates

Building a guessing game for visionOS

Create a team-based guessing game for visionOS using Group Activities.

`struct SpatialTemplatePreference`

A structure that specifies the preferred arrangement of participant spatial Personas in a shared simulation space.

`struct SpatialTemplateSeatElement`

A spatial template element that represents a seat for a participant in the activity.

`protocol SpatialTemplateElement`

An interface that defines an element in your spatial template.

`struct SpatialTemplateElementPosition`

A type that defines the position of an element in a spatial template.

`struct SpatialTemplateElementDirection`

The initial direction a participant faces when an activity starts.

`protocol SpatialTemplateRole`

An interface for defining roles that you assign to the participants of a group activity.

---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/remoteparticipantstates



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/localparticipantstates



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/participantstate/pose



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/participantstate/seat-swift.struct/pose



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/configuration-swift.struct/supportsgroupimmersivespace

- Group Activities
- SystemCoordinator
- SystemCoordinator.Configuration
- supportsGroupImmersiveSpace

Instance Property

# supportsGroupImmersiveSpace

A Boolean value that indicates whether your app supports a shared context when an immersive space is open.

var supportsGroupImmersiveSpace: Bool

## Discussion

If your app presents an immersive space, set this property to `true` if you want the system to display spatial Personas when that space is open. The default value of this property is `false`.

An immersive space places a person in their own private experience. To prevent the disruption of that experience, the system disables spatial Personas by default when any immersive space is open. Setting this property to `true` tells the system that it can once again display spatial Personas when an immersive space is open.

When displaying spatial Personas in an immersive space, the system establishes a shared coordinate space among the participants. Specifically, the system moves the origin of the coordinate space to a shared location, which it derives from the template in the `spatialTemplatePreference` property. Any content you place in the immersive space subsequently appears in the correct relative location from each participant’s perspective. To place content in front of a specific participant, use a `GeometryReader3D` object to read the geometry of your scene. The doc://com.apple.documentation/documentation/swiftui/geometryproxy3d/immersivespacedisplacement(in:) method of `GeometryProxy3D` provides you with the offset from the current participant to the shared origin, which you can use to position your content.

---

# https://developer.apple.com/documentation/groupactivities/groupsessionmessenger



---

# https://developer.apple.com/documentation/groupactivities/adding-spatial-persona-support-to-an-activity

- Group Activities
- Adding spatial Persona support to an activity

Article

# Adding spatial Persona support to an activity

Update your SharePlay activities to support spatial Personas and the shared context when running in visionOS.

## Overview

A person who participates in SharePlay activities on Apple Vision Pro has the option to participate using their spatial Persona. The system arranges spatial Personas around the activity content, giving each person a clear view of the content and each other. Each person sees the facial expressions of other participants, what they’re looking at, and where they’re pointing. This experience creates the feeling that they’re in the same physical space interacting with shared content and each other.

To maintain the experience when spatial Personas are visible, apps share additional information to maintain the _shared context_ for the activity. Because participants can see where others are looking, your app’s content must look the same for everyone. Share any additional information you need to keep everyone’s content in sync visually. For example, synchronize your window’s scroll position to ensure everyone sees the same portion of that window.

You don’t need to define new `GroupActivity` types specifically to support spatial Personas. The system automatically displays spatial Personas for existing activities that take place in a window or volume. However, if you support activities in a Full Space, you need to do additional work to support spatial Personas for your experience. For information about how to define activities in your app, see Defining your app’s SharePlay activities.

### Associate SharePlay activities with your app’s scenes

You use scenes to manage the content for your app’s windows, volumes, and immersive spaces. You also use scenes to display any activity-related content. When a participant joins an activity, the system selects or opens the scene that supports the activity. If your app has only one scene and one window, the system has only one choice. However, if your app has multiple scenes, you need to help the system choose the correct one.

For each of your app’s scenes, activation conditions tell the system how to handle your app’s SharePlay activities. You also use activation conditions to specify how to handle `NSUserActivity` objects, and other incoming events. To specify activation conditions for one of your scenes:

- For SwiftUI, add the `handlesExternalEvents(preferring:allowing:)` modifier to your scene type.

- For UIKit, configure the scene’s `activationConditions` property in the `scene(_:willConnectTo:options:)` method of your scene delegate.

When you add an activation condition to a scene, you specify a string that uniquely identifies your SharePlay activity. The string can be anything you want, as long as it creates a unique connection between the activity and the specific scene. When there is a one-to-one correspondence between an activity and scene, the string in the `activityIdentifier` property of your activity object is a good choice. When there isn’t a one-to-one correspondence between scene and activity, you must create a string that uniquely identifies the scene. For example, in a document-based app, you might specify the name of a document to direct the system to the scene that contains the document.

The following code defines a SwiftUI scene for a window, and associates two activities with that window. Because the app uses the same scene to display content for two different activities, the activation conditions contain the identifiers for the two `GroupActivity` types. When either activity starts, the system directs the activity to the window containing the scene. If no such window is open, the system launches the app and creates the window as needed.

let activationConditions : Set = ["com.mycompany.MySharePlayActivity",\
"com.mycompany.MyUserActivity"]
var body: some Scene {
WindowGroup {
ContentView()
.handlesExternalEvents(preferring: [], allowing: activationConditions)
}

In addition to configuring your scene, you need to update your activity object’s metadata with the appropriate string. Specify the string using the `sceneAssociationBehavior` property of your activity object’s `GroupActivityMetadata` structure. Assign the `default` value to this property if you use the activity identifier as the string. For any custom strings, assign the `content(_:)` value and specify your string. To disable scene association for the activity and handle the presentation of activity-related UI yourself, specify the `none` value.

### Configure your app’s support for spatial Personas

The system provides some default behaviors to make it easier for you to adopt spatial Personas in your app. For activities that take place in a window or volume, the system chooses a default arrangement of the spatial Personas around your scene. The system also adorns the scene with a Share menu, which provides a visual indication when sharing is active and contains controls to start activities. The system doesn’t display spatial Personas in a Full Space by default.

To change the default behavior of your app, update the `SystemCoordinator` of your `GroupSession` before you call the session’s `join()` method. Use the `SystemCoordinator` to:

- Specify a different arrangement for spatial Personas.

- Specify whether your app supports spatial Personas when a Full Space is visible.

The following example changes the arrangement of spatial Personas to be side by side facing the app’s content. The code also tells the system that the app supports spatial Personas when a Full Space is open.

if let coordinator = await newSession.systemCoordinator {
var config = SystemCoordinator.Configuration()
config.spatialTemplatePreference = .sideBySide.contentExtent(200)
config.supportsGroupImmersiveSpace = true
coordinator.configuration = config
}

// Join the session.
newSession.join()

Spatial template preferences tell the system whether to arrange participants side by side, in a circle, or in an arrangement that supports conversation. For each template, the system uses the size of your content to determine how far away to place spatial Personas. For example, the system moves them farther away when your content is larger, and brings them closer together when your content is small. To override this distance, add the `contentExtent(_:)` modifier to your template preference. That modifier tells the system to use the distance you specify, instead of the content size.

If you enable support for spatial Personas in a Full Space, you must do additional work to support that experience. When an activity moves to a Full Space, the system creates a shared coordinate system for all participants and the content. In this new coordinate system, participants are no longer at the center of the coordinate system, which might require you to update the position of your content. For more information, see Place content relative to a participant in an immersive space.

### Synchronize additional data when spatial Personas are visible

When spatial Personas are visible, it’s your responsibility to maintain the shared context for your activity. The shared context includes both the content you display and how that content appears to each participant. People can gesture or look at content using their spatial Persona, so it’s important that everyone sees the same thing when that happens. For example, Freeform synchronizes both the page content and the current scroll position to ensure everyone sees the same portion of the page.

When defining an activity, define additional data messages to synchronize any information you need to maintain the shared context. When the current participant shows their spatial Persona, send the extra messages when the participant makes relevant changes to the activity. For example, send them when the person scrolls the activity window. Similarly, receive those messages and incorporate the results into your app when the spatial Persona is visible.

To determine when someone’s spatial Persona is visible, monitor the `localParticipantStates` of your session’s `SystemCoordinator` object. The `AsyncSequence` in this property reports participant-related state changes, including changes to the visibility of their spatial Persona. Get the `isSpatial` property of the returned `SystemCoordinator.ParticipantState` structure and use it to configure your app’s behavior. The following example uses a task to update the game state to accommodate spatial Personas. When the current participant is spatial, the game sends additional messages to maintain the shared context.

Task.detached { @MainActor in
for await state in coordinator.localParticipantStates {
if state.isSpatial {
// Synchronize additional data for the shared context.
gameModel.isSpatial = true
} else {
// Don't synchronize additional data.
gameModel.isSpatial = false
}
}
}

### Update the immersion level automatically for a Full Space

If one participant opens an immersive space as part of an activity, the system doesn’t automatically open the same immersive space for other participants. Making a transition to an immersive space is a significant change, and some participants might not want to make the transition right away. For example, if a participant is on a phone call, they might not want another app to open an immersive space and hide their call. Instead, the system reports when transitions to immersive spaces occur, and lets you decide when to transition other participants automatically.

To determine when any participant transitions to an immersive space, monitor the `groupImmersionStyle` property of your `SystemCoordinator` object. This property contains an `AsyncSequence` that reports the most recent immersion style that a participant adopts. When a participant presents an immersive space, or when they change the immersion style of the current space, the system updates the sequence with the new value. The following example shows a task that opens the immersive space with the same style as the group immersion style.

Task.detached {
for await immersionStyle in systemCoordinator.groupImmersionStyle {
if let immersionStyle {
// Open an immersive space with the same style.
}
else {
// Dismiss the immersive space.
}
}
}

The system reports `nil` for the immersion style when a participant dismisses their open immersive space. Use that option to dismiss the space for other participants and

When an activity takes place in an immersive space, the system creates a shared coordinate system for the participants and content. In this new coordinate space, the origin of the coordinate space is not the same as the origin of any of the participants. If an activity-related window or volume is visible, the system places the window or volume at the new origin. If the activity doesn’t use a window or volume, the system arranges the participants in a circle and sets the origin of the coordinate space to the circle’s center. The following figure shows the origin of the shared coordinate system for a window, volume, and immersive space relative to several spatial Personas.

In a side-by-side arrangement with a window, the origin is under the window.

In a surround arrangement with a volume, the origin is under the volume.

When no window or volume is present, the system uses the surround presentation style and places the origin at the center of the group.

If you place content directly into your immersive space, you must adjust the position of that content to account for the modified coordinate space. To do that, you first determine the person’s location in the new coordinate system. Read the person’s location in the scene using a `GeometryProxy3D`. The proxy for this reader contains a doc://com.apple.documentation/documentation/swiftui/geometryproxy3d/immersivespacedisplacement(in:) method, which you can use to locate the origin of the shared coordinate space. Call the method using the `global` value as a parameter to get the displacement of the coordinate space’s origin, relative to the person’s location. Invert that displacement value to get the location of the participant relative in the new coordinate space. The following example shows how to use a `GeometryProxy3D` to get the offset to the current participant and use that information to place a custom view:

var body: some Scene {
ImmersiveSpace(id:"earth") {
GeometryReader3D { proxy in
let displacement =
proxy.immersiveSpaceDisplacement(in: .global).inverse

CustomView()
.offset(displacement.position)
.rotation3DEffect(displacement.rotation)
}
}
}

The displacement between a person and the origin of the scene doesn’t change during the course of your activity even when the participant moves. The system sets the origin of an immersive space when you first present it, and updates it only once when changing it to a shared coordinate space.

## See Also

### Spatial activities

Configure your visionOS app for sharing with people nearby

Create shared experiences for people wearing Vision Pro in the same room and those on FaceTime.

`class SystemCoordinator`

A type you use to coordinate your interface’s behavior when an active SharePlay session supports spatial placement of content.

`struct ParticipantState`

A structure that tells you whether a participant supports a shared simulation space for the current activity.

`](https://developer.apple.com/documentation/SwiftUI/View/groupActivityAssociation(_:))

Specifies how a view should be associated with the current SharePlay group activity.

Beta

`class GroupActivityAssociationInteraction`

An interaction configures a view’s association with the current SharePlay group activity.

`struct GroupActivityAssociationKind`

An association a user-interface element can have with a SharePlay group activity.

---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator

- Group Activities
- SystemCoordinator

Class

# SystemCoordinator

A type you use to coordinate your interface’s behavior when an active SharePlay session supports spatial placement of content.

final class SystemCoordinator

## Mentioned in

Adding spatial Persona support to an activity

## Overview

A `SystemCoordinator` object helps you coordinate the presentation of your app’s content when spatial placement is active. In visionOS, the system can present a SharePlay activity as if the participants were together in the same room with the content. Each participant views the content from a particular vantage point, and sees the changes that others make. The system handles the placement of each participant’s spatial Persona relative to the content, but you handle any changes to the content itself with the help of the `SystemCoordinator` object.

You don’t create a `SystemCoordinator` object directly. After you receive a `GroupSession` object for an activity, retrieve the system coordinator from the session’s `systemCoordinator` property. When you first retrieve the object, update its `configuration` property to tell the system how you want to arrange participants in the scene. After that, use the information in the system coordinator’s properties to keep your app’s interface up to date. When participants support spatial placement, send additional data to synchronize your content for those participants. For example, when one person scrolls the contents of a window, update the scroll position in the window of other spatially aware participants to preserve the shared context for everyone.

You choose what information to share among participants, and you choose how to manage the corresponding updates. A system coordinator object only helps you know when to make those changes. Observe the object’s published properties to receive automatic updates when the values change.

## Topics

### Configuring the system coordinator

`var configuration: SystemCoordinator.Configuration`

The current configuration of the system coordinator.

`struct Configuration`

A structure that specifies your app’s support for activities that take place in a shared simulation space.

### Getting the participant state

[`var remoteParticipantStates: [Participant : SystemCoordinator.ParticipantState]`](https://developer.apple.com/documentation/groupactivities/systemcoordinator/remoteparticipantstates) Beta

`var localParticipantState: SystemCoordinator.ParticipantState`

The current participant’s level of support for an activity that takes place in a shared simulation space.

`var localParticipantStates: SystemCoordinator.ParticipantStates`

An asynchronous sequence that reports changes to the local participant’s state.

`struct ParticipantStates`

An asynchronous sequence that reports the current person’s ability to participate in a shared context.

### Getting the current immersion level

`var groupImmersionStyle: SystemCoordinator.GroupImmersionStyles`

The presentation style to apply to an immersive space for the current activity.

`struct GroupImmersionStyles`

An asynchronous sequence that contains one or more incoming immersion styles for you to process.

### Assigning the local participant role

`func assignRole(some SpatialTemplateRole)`

Assigns the given spatial template role to the local participant.

`func resignRole()`

Resigns the local participant from their current spatial template role.

### Structures

`struct ParticipantState`

A structure that tells you whether a participant supports a shared simulation space for the current activity.

## Relationships

### Conforms To

- `Observable`
- `Sendable`
- `SendableMetatype`

## See Also

### Spatial activities

Configure your visionOS app for sharing with people nearby

Create shared experiences for people wearing Vision Pro in the same room and those on FaceTime.

Update your SharePlay activities to support spatial Personas and the shared context when running in visionOS.

`](https://developer.apple.com/documentation/SwiftUI/View/groupActivityAssociation(_:))

Specifies how a view should be associated with the current SharePlay group activity.

Beta

`class GroupActivityAssociationInteraction`

An interaction configures a view’s association with the current SharePlay group activity.

`struct GroupActivityAssociationKind`

An association a user-interface element can have with a SharePlay group activity.

---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/participantstate



---

# https://developer.apple.com/documentation/groupactivities/groupactivityassociationinteraction

- Group Activities
- GroupActivityAssociationInteraction Beta

Class

# GroupActivityAssociationInteraction

An interaction configures a view’s association with the current SharePlay group activity.

GroupActivitiesUIKit

@MainActor @objc
class GroupActivityAssociationInteraction

## Overview

When a group of people join a SharePlay activity with their spatial Personas, the system selects a common, primary scene to arrange their spatial Personas around. This association between the group activity and a scene in your app creates a shared space for the spatial Personas to interact in; enabling participants to gesture at the associated scene and understand each other. For more information about spatial Personas and SharePlay on visionOS, see Adding spatial Persona support to an activity.

By default, the system uses your scene’s activation conditions in concert with your activity’s `SceneAssociationBehavior` to select a primary scene to associate with the activity. You can specify a different scene or dynamically change the primary associated scene by adding this interaction to a view and specifying that view as the `GroupActivityAssociationKind/primary` group activity association.

To add the interaction to a view, use `addInteraction(_:)`.

// Create and store the scene association interaction
private let groupActivityAssociationInteraction = GroupActivityAssociationInteraction(
associationKind: .primary("content-view")
)

override func viewDidLoad() {
super.viewDidLoad()

// Add the interaction to the view
view.addInteraction(groupActivityAssociationInteraction)
}

If there are multiple scenes that are simultaneously configured with the primary group activity association, the most recently associated scene will be used. For example, if your app defines two windows and both contain views with the primary association kind, the most recently opened one will be used as the primary scene. If that second window is subsequently closed, the original window will be used again.

You can dynamically disable the group activity association of a view by setting the optional `associationKind` property to `nil`. You can later re-associate it by setting the `associationKind` to `.primary`.

func removeGroupActivityAssociation() {
groupActivityAssociationInteraction.associationKind = nil
}

## Topics

### Initializers

`init(associationKind: GroupActivityAssociationKind?)`

Creates a group activity association interaction.

### Instance Properties

`var associationKind: GroupActivityAssociationKind?`

An optional value that indicates the kind of group activity association, if any.

`var view: UIView?`

### Instance Methods

`func didMove(to: UIView?)`

`func willMove(to: UIView?)`

## Relationships

### Inherits From

- `NSObject`

### Conforms To

- `CVarArg`
- `CustomDebugStringConvertible`
- `CustomStringConvertible`
- `Equatable`
- `Hashable`
- `NSObjectProtocol`
- `Sendable`
- `SendableMetatype`
- `UIInteraction`

## See Also

### Spatial activities

Configure your visionOS app for sharing with people nearby

Create shared experiences for people wearing Vision Pro in the same room and those on FaceTime.

Adding spatial Persona support to an activity

Update your SharePlay activities to support spatial Personas and the shared context when running in visionOS.

`class SystemCoordinator`

A type you use to coordinate your interface’s behavior when an active SharePlay session supports spatial placement of content.

`struct ParticipantState`

A structure that tells you whether a participant supports a shared simulation space for the current activity.

`](https://developer.apple.com/documentation/SwiftUI/View/groupActivityAssociation(_:))

Specifies how a view should be associated with the current SharePlay group activity.

Beta

`struct GroupActivityAssociationKind`

An association a user-interface element can have with a SharePlay group activity.

Beta Software

This documentation contains preliminary information about an API or technology in development. This information is subject to change, and software implemented according to this documentation should be tested with final operating system software.

Learn more about using Apple's beta software

---

# https://developer.apple.com/documentation/groupactivities/groupactivityassociationkind



---

# https://developer.apple.com/documentation/groupactivities/groupstateobserver

- Group Activities
- GroupStateObserver

Class

# GroupStateObserver

An object that contains information about the system’s ability to start SharePlay experiences.

final class GroupStateObserver

## Mentioned in

Presenting SharePlay activities from your app’s UI

## Overview

Starting a SharePlay experience with the Group Activities framework requires an active FaceTime call. Use a `GroupStateObserver` object to determine whether it’s possible to start such an experience. When no call is active, you might adjust your app’s user interface. For example, you might hide or remove controls that start a shared activity.

To get the current system state, create a `GroupStateObserver` object and check the value of its `isEligibleForGroupSession` property. To respond right away when the value of the property changes, configure a subscriber for that property.

## Topics

### Creating a group state observer

`convenience init()`

Creates a new group state observer object for determining the availability of group sessions.

### Determining the eligibility for shared activities

`var isEligibleForGroupSession: Bool`

A Boolean value that indicates whether the system can start a group session.

### Type Aliases

`typealias ObjectWillChangePublisher`

The type of publisher that emits before the object has changed.

## Relationships

### Conforms To

- `ObservableObject`

---

# https://developer.apple.com/documentation/groupactivities/groupstateobserver)



---

# https://developer.apple.com/documentation/groupactivities/promoting-shareplay-activities-from-your-apps-ui)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/configure-your-app-for-sharing-with-people-nearby)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/groupactivity

- Group Activities
- GroupActivity

Protocol

# GroupActivity

A type that can advertise your app’s activities to other participants.

protocol GroupActivity : Decodable, Encodable

## Mentioned in

Defining your app’s SharePlay activities

Presenting SharePlay activities from your app’s UI

Adding spatial Persona support to an activity

Joining and managing a shared activity

## Overview

Adopt the `GroupActivity` protocol in custom app data structures that represent your app’s shareable experiences. The protocol provides the system with the context and metadata to start an activity-related session. For example, the protocol defines the unique identity of the activity, and returns information about the activity.

In addition to the protocol’s methods and properties, make sure your type includes the information you need to start the activity. When a participant accepts an activity, the system provides a copy of your activity type. You must use that type to begin the activity. For example, use it to present the appropriate UI for the activity and to load any required content.

To initiate an activity, create an instance of your custom type and call its `prepareForActivation()` or `activate()` method. You might call one of these methods from a button in your app’s UI, or in response to other user actions. If activation succeeds, the system advertises the activity on the current FaceTime call.

When an activity begins, the system creates a `GroupSession` instance for the activity and delivers it asynchronously to your app. Use the `sessions()` method to get the session and configure your app’s UI.

## Topics

### Specifying the activity details

`static var activityIdentifier: String`

An app-defined string that uniquely identifies the activity.

**Required** Default implementation provided.

`var metadata: GroupActivityMetadata`

A description of the activity, and optional image to display to the user.

**Required**

### Starting an activity immediately

Returns the participant’s preferred option for how to start the activity.

`enum GroupActivityActivationResult`

The result of preparing to start a custom activity.

Begins the activity immediately and creates a session for the app when a FaceTime call is active.

### Receiving an activity-related session

Returns the sessions for this activity as an asynchronous sequence.

`typealias Sessions`

A type that provides asynchronous, sequential, iterated access to the sessions for the activity.

### Transferring data types

`static var transferRepresentation: some TransferRepresentation`

A default type that lets the system share your activity.

## Relationships

### Inherits From

- `Decodable`
- `Encodable`

## See Also

### Activity definition

Configure your app’s SharePlay support and define the activities that people can perform from your app.

Supporting Coordinated Media Playback

Create synchronized media experiences that enable users to watch and listen across devices.

`struct GroupActivityMetadata`

Text and image content that describes an activity to potential participants.

`struct GroupActivityTransferRepresentation`

A type that lets you start a group activity from a known context.

---

# https://developer.apple.com/documentation/groupactivities/groupsession

- Group Activities
- GroupSession

Class

# GroupSession

A session for an in-progress activity that synchronizes content among participant devices.

## Mentioned in

Joining and managing a shared activity

Adding spatial Persona support to an activity

Synchronizing data during a SharePlay activity

## Overview

A `GroupSession` object contains details about the user’s currently selected activity, its status, and its participants. When a participant engages in an activity, the system binds a session to that activity for you. You use the session object to synchronize your app’s activity-related content, including your app’s UI.

You don’t create `GroupSession` objects directly. Instead, the system creates sessions and makes them available to your app asynchronously. Use the `AsyncSequence` type returned by the `sessions()` method of your activity to retrieve new sessions when they become available.

Before the system can create a session object, your app must create a `GroupActivity` object and activate it. For information about how to configure group activities, see `GroupActivity`.

### Start and Stop the Session

When you receive a new session object, it’s initially in the `GroupSession.State.waiting` state. As soon as your app is ready to begin the associated activity, call the session’s `join()` method. Joining a session validates the connection and starts the synchronization process between the current device and other participants’ devices. If your app successfully joins the session, the session transitions to the `GroupSession.State.joined` state.

When the user quits your app, or navigates away from the shared activity, call the session’s `leave()` method. Leaving a session gracefully transitions it to the `GroupSession.State.invalidated(reason:)` state, and informs the system that the user isn’t currently engaged in the activity.

## Topics

### Getting the current session

`struct Sessions`

An asynchronous sequence of sessions you use to manage a specific activity.

### Joining and leaving the session

`func join()`

Starts the shared activity on the current device.

`func leave()`

Leaves the current activity and stops receiving synchronized data.

`func end()`

Ends the activity for the entire group and stops the transfer of synchronized data.

### Accessing the shared activity

`var activity: ActivityType`

The current activity associated with the session.

### Getting the session details

The current state of the session.

`enum State`

The possible states of a session.

`let id: UUID`

The unique identifier of the current session.

`var description: String`

A textual representation of this instance.

### Getting the participants

`var localParticipant: Participant`

The participant on the current device.

The set of participants currently engaged in the activity.

### Getting the scene-association identifier

`var sceneSessionIdentifier: String?`

The persistent identifier of the session’s associated scene.

### Getting the participant’s attention

`func requestForegroundPresentation()`

Tells the system that your app needs to be in the foreground to continue an activity.

### Notifying participants of playback changes

`func showNotice(GroupSessionEvent)`

Posts an event to the system, which displays the information in the system UI.

`struct GroupSessionEvent`

A session-related event that appears in the system UI.

### Publishing changes

`var objectWillChange: ObservableObjectPublisher`

### Structures

`struct Event`

A session-related event to display in the system UI.

Deprecated

### Instance Properties

`var $activeParticipants: Published<Set<Participant>>.Publisher`

`let isLocallyInitiated: Bool`

A Boolean value that is true if the current session was created by the local participant.

`var systemCoordinator: SystemCoordinator?`

The system coordinator associated with an active session.

### Instance Methods

### Type Aliases

`typealias ObjectWillChangePublisher`

The type of publisher that emits before the object has changed.

## Relationships

### Conforms To

- `Copyable`
- `CustomStringConvertible`
- `ObservableObject`

## See Also

### Session management

Configure the session when a SharePlay activity starts, and handle events that occur during the lifetime of the activity.

Drawing content in a group session

Invite your friends to draw on a shared canvas while on a FaceTime call.

`protocol CustomMessageIdentifiable`

A type that assigns a custom ID string to messages you send to other devices.

`struct Participant`

An active participant in a group session.

---

# https://developer.apple.com/documentation/groupactivities/defining-your-apps-shareplay-activities

- Group Activities
- Defining your app’s SharePlay activities

Article

# Defining your app’s SharePlay activities

Configure your app’s SharePlay support and define the activities that people can perform from your app.

## Overview

SharePlay activities are an organic way to create experiences that people can enjoy together. When you add the Group Activities framework to your app, you gain the ability to share your app’s features over FaceTime, Messages, and AirDrop. Some examples of experiences people can share together include:

- Watching or listening to content

- Participating in an online fitness class

- Creating content on a shared whiteboard or painter’s canvas

- Shopping for food, clothes, or other online products

- Planning a trip or browsing the web

- Reading a book or taking an online class

Consider the preceding list of activities, and any other activities your app supports, and build SharePlay support for them. Think about how people might enjoy those activities if they were together in the same physical space. Consider the types of interactions that can occur in the real world, and build support for those interactions into your activities. For example, a movie-watching app needs to pause playback for all participants when one person hits the pause button. A shared whiteboard app needs to transmit newly drawn content to other participants, and send all of the content to someone who arrives late.

### Configure the SharePlay entitlements

Before you start adding SharePlay support to your app, add the `com.apple.developer.group-session` entitlement to your Xcode project. Because SharePlay involves communication with other devices, you need this entitlement to support activities. To add the entitlement to your app:

1. Open your Xcode project.

2. Select your app target.

3. Go to the Signing & Capabilities pane.

4. Add the Group Activities capability to the target.

Configure this entitlement only for app targets. When you add the Group Activities capability, Xcode adds the necessary entitlements to your app and updates its provisioning profile.

### Turn an existing app feature into an activity

Turn one of your app’s features into a SharePlay experience by adopting the `GroupActivity` protocol in the appropriate place in your code. This protocol provides the basic definition of a SharePlay activity. When you adopt it in one of your app’s existing types, that type provides the information that SharePlay needs to promote that activity to participants. If you prefer to keep the activity separate from your app data structures, define a new type and add any app-specific data you need to manage the activity.

Most of the content in a `GroupActivity` type is the data you use to support the activity itself. Include data that is critical for performing the activity, such as the URL of the movie in a movie-watching activity. Also, include information to support the overall experience, such as the name of the movie and an image to display in the SharePlay UI. Store as little data as possible to support the activity, and share state information instead of detailed changes wherever possible. For example, store a link to the movie instead of the movie file itself. The following example defines a `Movie` type that stores information about a movie to watch, and a group activity to share the experience:

struct Movie: Codable{
var title : String
var movieURL : URL

// Codable support...
}

struct WatchTogether: GroupActivity {
// The movie to watch together.
var movie: Movie

init(movie: Movie) {
self.movie = movie
}
}

### Customize the unique identifier for your activity

To differentiate one activity from another, each `GroupActivity` type must have a unique string in its `activityIdentifier` property. The default implementation of this property combines your app’s bundle identifier with the name of your custom `GroupActivity` type. This string is sufficient for most activity types, but you can also specify a custom value if you prefer.

If you specify a custom string, include your company name in reverse-DNS format along with any other information you need to distinguish the activity from others in your app. The following code adds a custom identifier for the `WatchTogether` activity:

struct WatchTogether: GroupActivity {
// Specify the activity type to the system.
static let activityIdentifier = "com.example.myapp.watch-movie-together"

// The movie to watch together.
var movie: Movie

Make activity identifiers as granular as needed to differentiate the activities within your app. Don’t create one activity type that serves multiple purposes. Instead, define separate types and give them unique activity identifiers. For example, if your video player supports playing both movies and television shows, create separate activities for each.

### Provide descriptive information about the activity

Each activity contains a `GroupActivityMetadata` type that stores descriptive information about the activity. When inviting people to join the activity, the system incorporates this metadata into the system UI. A concise title, a short description of the activity, and an image help people understand which activity they’re joining. You can also provide additional details, such as a fallback URL that someone can use to join the activity from a web browser.

Create a `GroupActivityMetadata` type dynamically from your activity, and populate it with activity-related details. Fill in as much of the information as possible, and make your descriptions concise and clear. People need to quickly identify the purpose of the activity and whether it’s one they want to join, so make sure your descriptions are clear enough for someone to make a decision. The following example creates the metadata for the `WatchTogether` activity and populates it with the movie details. Use the `fallbackURL` property to provide a URL to the content in case a participant doesn’t have the app.

extension WatchTogether {
// Provide information about the activity.
var metadata: GroupActivityMetadata {
var metadata = GroupActivityMetadata()
metadata.type = .watchTogether
metadata.title = "\(movie.title)"
metadata.fallbackURL = movie.movieURL
metadata.supportsContinuationOnTV = true

return metadata
}
}

Classify your app’s activities by specifying an appropriate value for the `type` property of `GroupActivityMetadata`. In the SharePlay banner, the system displays an icon that matches the type of the activity. The icon provides an additional visual cue about what people can expect from the activity.

### Include a transferable representation of your activity

The Core Transferable framework helps you build data types that you can easily transfer between different processes or devices. In particular, the `Transferable` protocol makes it easy to support pasteboard operations and drag and drop. The Group Activities framework supports this protocol by letting you associate a `GroupActivity` with one of your transferable types. SwiftUI and SharePlay via AirDrop also take advantage of this association to present possible activities from your UI.

If you initialize an activity using one of your app’s data types, adopt the `Transferable` protocol in that data type and include a transfer representation for the activity. Implement the `transferRepresentation` property of the protocol, and include a `GroupActivityTransferRepresentation` structure in addition to any representations you use to support the pasteboard. Use the `GroupActivityTransferRepresentation` structure to initialize an activity using the current data type. For example, the following code creates an activity to watch a movie for a custom `Movie` type:

struct Movie: Transferable, Codable{
var title : String
var movieURL : URL

/// A transferable version of the movie URL and group activity.
static var transferRepresentation: some TransferRepresentation {
ProxyRepresentation(exporting: \.movieURL)

GroupActivityTransferRepresentation { movie in
WatchTogether(movie: movie)
}
}

When you include a `ShareLink` view in your SwiftUI interface, you can specify your transferable data type as the shareable item from that view. When someone taps or clicks the link, the system displays a share sheet with options for sharing the data. If you include a `GroupActivityTransferRepresentation` type, the sheet includes an option to start the associated activity. The following example creates a `ShareLink` view using the `Movie` data type:

struct MovieDetailView: View {
let movie: Movie

var body: some View {
ShareLink(
item: movie,
preview: SharePreview(
movie.title))
}
}

For more information on displaying a share sheet or supporting SharePlay via AirDrop, see Presenting SharePlay activities from your app’s UI.

## See Also

### Activity definition

Supporting Coordinated Media Playback

Create synchronized media experiences that enable users to watch and listen across devices.

`protocol GroupActivity`

A type that can advertise your app’s activities to other participants.

`struct GroupActivityMetadata`

Text and image content that describes an activity to potential participants.

`enum GroupActivityActivationResult`

The result of preparing to start a custom activity.

`struct GroupActivityTransferRepresentation`

A type that lets you start a group activity from a known context.

---

# https://developer.apple.com/documentation/groupactivities/groupactivitymetadata



---

# https://developer.apple.com/documentation/groupactivities/groupactivityactivationresult

- Group Activities
- GroupActivityActivationResult

Enumeration

# GroupActivityActivationResult

The result of preparing to start a custom activity.

enum GroupActivityActivationResult

## Overview

When you call `prepareForActivation()`, the system determines whether you share the activity with other participants in a FaceTime call, or perform it locally. After making the determination, it passes a `GroupActivityActivationResult` value to the method’s completion handler. Use that value to start the activity in the selected setting.

## Topics

### Getting the activation results

`case activationPreferred`

A result that indicates the user wants to share the activity with the group.

`case activationDisabled`

A result that indicates the user disabled the automatic sharing of activities, or prefers to perform the activity locally.

`case cancelled`

A result that indicates the user canceled the activation request.

### Comparing reliability options

Returns a Boolean value indicating whether two values are not equal.

Returns a Boolean value indicating whether two values are equal.

### Instance Properties

`var hashValue: Int`

The hash value.

### Instance Methods

`func hash(into: inout Hasher)`

Hashes the essential components of this value by feeding them into the given hasher.

## Relationships

### Conforms To

- `Copyable`
- `Equatable`
- `Hashable`
- `Sendable`
- `SendableMetatype`

## See Also

### Activity definition

Defining your app’s SharePlay activities

Configure your app’s SharePlay support and define the activities that people can perform from your app.

Supporting Coordinated Media Playback

Create synchronized media experiences that enable users to watch and listen across devices.

`protocol GroupActivity`

A type that can advertise your app’s activities to other participants.

`struct GroupActivityMetadata`

Text and image content that describes an activity to potential participants.

`struct GroupActivityTransferRepresentation`

A type that lets you start a group activity from a known context.

---

# https://developer.apple.com/documentation/groupactivities/groupactivitytransferrepresentation

- Group Activities
- GroupActivityTransferRepresentation

Structure

# GroupActivityTransferRepresentation

A type that lets you start a group activity from a known context.

## Mentioned in

Presenting SharePlay activities from your app’s UI

Defining your app’s SharePlay activities

## Topics

### Initializers

Creates a type that exports a group activity for the specified item.

### Instance Properties

`var body: some TransferRepresentation`

A builder expression that describes the process of importing and exporting an item.

### Type Aliases

`typealias Body`

The transfer representation for the item.

## Relationships

### Conforms To

- `Sendable`
- `SendableMetatype`
- `TransferRepresentation`

## See Also

### Activity definition

Configure your app’s SharePlay support and define the activities that people can perform from your app.

Supporting Coordinated Media Playback

Create synchronized media experiences that enable users to watch and listen across devices.

`protocol GroupActivity`

A type that can advertise your app’s activities to other participants.

`struct GroupActivityMetadata`

Text and image content that describes an activity to potential participants.

`enum GroupActivityActivationResult`

The result of preparing to start a custom activity.

---

# https://developer.apple.com/documentation/groupactivities/groupactivitysharingcontroller-4gtfk

- Group Activities
- GroupActivitySharingController

Class

# GroupActivitySharingController

A macOS view controller that displays the system interface for starting an activity, and optionally starts a FaceTime call for that activity.

GroupActivitiesAppKit

@MainActor @objc
class GroupActivitySharingController

## Overview

A `GroupActivitySharingController` helps you start a SharePlay activity, even when a FaceTime call isn’t currently active. When presented, the view controller prompts the person to start the activity you provided. If no FaceTime call is active, the view controller also displays a people picker to let the person select the participants for the activity. When they choose to start the activity, the view controller automatically starts the FaceTime call as needed and joins your app to the activity.

If your app’s interface includes controls to start SharePlay activities, present this view controller in response to interactions with those controls. Initialize the `GroupActivitySharingController` object with the activity you want to start. After you present it, the view controller handles all further interactions. It manages the interface that appears onscreen and responds when someone chooses to start or cancel the activity. It starts the FaceTime call if one isn’t currently active. It also dismisses itself and returns control property to let you know what happened.

## Topics

### Creating the group activity sharing controller

Initializes the sharing controller with the specified activity and type information.

Initializes the SharePlay sharing controller with a closure that creates the activity object.

### Getting the result

`var result: GroupActivitySharingResult`

The result of a request to share a group activity.

`enum GroupActivitySharingResult`

The result of a request to share a group activity in macOS.

### Responding to view-related events

`func viewDidLoad()`

Notifies the view controller that the system added a view to a view hierarchy.

### Instance Methods

`func loadView()`

`func viewWillAppear()`

Notifies the view controller that the system is going to add a view to a view hierarchy.

## Relationships

### Inherits From

- `NSViewController`

### Conforms To

- `CVarArg`
- `CustomDebugStringConvertible`
- `CustomStringConvertible`
- `Equatable`
- `Hashable`
- `NSCoding`
- `NSEditor`
- `NSExtensionRequestHandling`
- `NSObjectProtocol`
- `NSSeguePerforming`
- `NSStandardKeyBindingResponding`
- `NSTouchBarProvider`
- `NSUserActivityRestoring`
- `NSUserInterfaceItemIdentification`

## See Also

### Interface presentation

Presenting SharePlay activities from your app’s UI

Make it easy for people to start activities from your app’s UI, from the system share sheet, or using AirPlay over AirDrop.

`class GroupActivitySharingController`

An iOS view controller that displays the system interface for starting an activity, and optionally starts a FaceTime call for that activity.

---

# https://developer.apple.com/documentation/groupactivities/groupactivitysharingcontroller-ybcy



---

# https://developer.apple.com/documentation/groupactivities/joining-and-managing-a-shared-activity

- Group Activities
- Joining and managing a shared activity

Article

# Joining and managing a shared activity

Configure the session when a SharePlay activity starts, and handle events that occur during the lifetime of the activity.

## Overview

When one person in a group starts an activity, other people’s devices display system UI to prompt them to join that activity. When each person joins, the system prepares a `GroupSession` object for the activity and delivers it to their app. Your app uses that session object to:

- Prepare any required UI.

- Start the activity, monitor its state, and respond to changes.

- Synchronize activity-related information.

For information about how to define activities, see Defining your app’s SharePlay activities. For information about how to start activities, see Presenting SharePlay activities from your app’s UI.

### Join an activity from a background task

Activities can start at any time, so you need to set up an asynchronous handler in your app to listen for when they start. After a participant joins an activity, the system creates a `GroupSession` object and delivers it to the sessions property of the `GroupActivity` type you defined. Monitor the sessions property from an asynchronous handler, and process new session objects when they become available.

Configure separate asynchronous handlers for each of your app’s activity types, and use each one to receive new sessions for their activity. In SwiftUI, create your handler by adding the `task(priority:_:)` modifier to the view containing the UI for the activity, as shown in the example below. Inside the block for the task modifier, wait on the activity’s sessions property using a `for..in` loop. The sessions property contains an `AsyncSequence` type, which wakes up the task and executes your code when a new session arrives. Use your code to begin the activity in your app.

struct ContentView: View {

var body: some View {
VStack {
MyCustomView()
MyOtherCustomView()
}
.task {
for await session in MyActivity.sessions() {
// Perform any app-specific tasks...

// Join the session.
session.join
}
}
}
}

If you’re not using SwiftUI, handle the arrival of sessions using a `Task` block, as shown in the following example. This block offers the same behavior as the SwiftUI task modifier, and you use it in similar ways. When a new session arrives, update your app’s UI to reflect the current activity, or perform any other tasks you need to prepare for the activity.

// Process an asynchronously delivered session.
var task = Task {
for await session in DrawTogether.sessions() {

// Perform any app-specific tasks...

// Join the session.
session.join()
}
}

Save a reference to any sessions you receive asynchronously and remove those references when the session state changes to `GroupSession.State.invalidated(reason:)`. The system delivers one new session for each joined activity. When the state of the session changes, or when other properties change, the system updates the already delivered session. To detect updates while the session is active, add subscribers to the properties of the `GroupSession` object.

### Prepare your app’s interface

When your app receives a `GroupSession` object, start preparing your app’s UI immediately. The activity doesn’t start until you call the join method of the session object you received. However, don’t call that method until you’re ready to display the UI for the activity itself. If your app needs to collect login credentials or download content before starting the activity, present the UI for those tasks and wait for them to complete before you call the join method.

After you join an activity, update your UI as needed to reflect relevant information. In particular:

- Provide a way for people to see who joined the activity, and who hasn’t joined. Some people might not join an activity right away, because they don’t have the app or are doing something else. Keeping everyone informed lets them know who’s aware of the activity details.

- Provide visual cues when someone makes a change, and optionally display information about who made the change. For example, annotate the change temporarily with the person’s identity, or add app-specific messages to the conversation.

- Support people navigating away from an activity but staying on the group FaceTime call or Messages conversation. For activities that involve video playback, support Picture in Picture to continue playback even when someone changes apps.

- Make sure app-specific controls are easy to access.

### Join the session to start the activity

When your app has everything it needs and is ready to start the activity, call the `join()` method of the `GroupSession` object. The `join()` method asks the system to start the activity in your app.

Even after you call this method, the session remains in the `GroupSession.State.waiting` state until the system establishes a connection to the activity.

If your call to `join()` is successful, the system changes the state of the session to `GroupSession.State.joined` and begins sending information to and from the current device. If you tried to synchronize data after calling `join()`, but before the system completed the request, those requests remain queued until your session enters the `GroupSession.State.joined` state. After successfully joining the session, the system expects you to handle session-related changes and messages. For information about how to send messages between participants, see Synchronizing data during a SharePlay activity.

### Accommodate people who arrive late to the session

Participants join activities separately, and people can join immediately or after a delay. If participants need to download your app, or don’t see the invitation to join the activity, they might arrive several minutes after others. If your activity manages state information that all participants require, devise a way to deliver that information to someone who arrives late. For example, a whiteboard app needs to deliver the current whiteboard content to any late joiners.

Consider the experience for people who arrive late to an activity, and plan for it when implementing your activity support. You might create a lobby interface where participants wait until everyone is present, or you might define custom messages to let people catch up with the rest of the group. Choose an experience that makes sense for your app, and remember that every participant is equal in a SharePlay activity. There’s no single activity owner who controls the experience.

To determine when new participants join the session, monitor the `activeParticipants` property of the session using a separate task. When the list of participants changes, compare the new list with a saved copy your app maintains. When you detect new participants, update them with the current state of the activity.

Task {
for try await updatedParticipants in session.$activeParticipants.values {
for participant in updatedParticipants {
// Compare the current list to a saved version you maintain.
}
}
}

### End the activity for one or more participants

The `GroupSession` object contains methods to end the session for the current participant or the entire group. When designing your UI, make it clear which option someone is choosing, and call the correct method in response.

When a participant quits your app, switches to a different app, or navigates away from your app’s activity-related UI, call `leave()` to end the activity for that participant. Other participants remain engaged in the activity until they leave or until someone ends the activity for everyone.

When a participant leaves an activity, the system moves their session to the `GroupSession.State.invalidated(reason:)` state and stops the flow of information between their device and the rest of the group. When the session moves to this state, it’s safe to discard the session object itself and perform any activity-related cleanup. If the person is still active on the FaceTime call or Messages conversation and rejoins the activity later, the system delivers a new session object to your app.

When you want to end the activity for everyone, call the `end()` method. This method invalidates the sessions for all participants. Make sure any buttons or UI that calls this method makes it clear that the activity ends for everyone. The session also ends when everyone leaves the activity.

## See Also

### Session management

Drawing content in a group session

Invite your friends to draw on a shared canvas while on a FaceTime call.

`class GroupSession`

A session for an in-progress activity that synchronizes content among participant devices.

`protocol CustomMessageIdentifiable`

A type that assigns a custom ID string to messages you send to other devices.

`struct Participant`

An active participant in a group session.

---

# https://developer.apple.com/documentation/groupactivities/drawing_content_in_a_group_session



---

# https://developer.apple.com/documentation/groupactivities/custommessageidentifiable

- Group Activities
- CustomMessageIdentifiable

Protocol

# CustomMessageIdentifiable

A type that assigns a custom ID string to messages you send to other devices.

protocol CustomMessageIdentifiable

## Overview

Adopt this protocol in the custom types you use to send and receive messages during a group activity. You use a `GroupSessionMessenger` object to send custom messages between the same app on different devices. In addition to the message data, `GroupSessionMessenger` encodes your custom type name so that it can construct the correct type on those other devices. Use this protocol to identify your custom message types using an app-specific string instead of the type name.

Providing an app-specific string makes it possible to use different types to support messages. When the message data contains a custom message ID, `GroupSessionMessenger` looks for a type that conforms to the protocol with a `messageIdentifier` property that contains the matching string. It then creates that type and decodes the message data into it.

## Topics

### Type Properties

`static var messageIdentifier: String`

A custom identification string for the current type.

**Required**

## See Also

### Session management

Joining and managing a shared activity

Configure the session when a SharePlay activity starts, and handle events that occur during the lifetime of the activity.

Drawing content in a group session

Invite your friends to draw on a shared canvas while on a FaceTime call.

`class GroupSession`

A session for an in-progress activity that synchronizes content among participant devices.

`struct Participant`

An active participant in a group session.

---

# https://developer.apple.com/documentation/groupactivities/building-a-guessing-game-for-visionos

- Group Activities
- Building a guessing game for visionOS

Sample Code

# Building a guessing game for visionOS

Create a team-based guessing game for visionOS using Group Activities.

Download

Xcode 16.0+

## Overview

This sample shows how to build a guessing game for two competing teams. Participants, using an Apple Vision Pro during a FaceTime call, can play as members of the red or blue team or watch from the audience. At each stage of the game, the sample positions participants according to their role as a team member or spectator.

After the initial welcome screen for the game, the participants select categories and divide into two teams. During the team-selection process, all participants start in the audience section. If a participant chooses to join a team, they move to the appropriate team area. During the game itself, the teams take turns guessing a word or phrase in a window that only one team member can see. The team member that sees the word or phrase can use any gestures or phrases to elicit a correct guess, but can’t say the word or phrase itself. If the team correctly guesses the word or phrase, the team scores a point. The team with the most points at the end of the game wins.

### Define the group activity

The `GroupActivity` protocol provides the system with the context and metadata to start an activity-related session. The sample defines a single `GroupActivity` to represent the game:

struct GuessTogetherActivity: GroupActivity, Transferable, Sendable {
var metadata: GroupActivityMetadata = {
var metadata = GroupActivityMetadata()
metadata.title = "Guess Together"
return metadata
}()
}

For more information, see Defining your app’s SharePlay activities.

### Encourage people to start a game

The welcome screen displays a custom `SharePlayButton`; tapping it starts the game. If the player is already in a FaceTime call, the `GuessTogetherActivity` activates. Otherwise, a `GroupActivitySharingController` displays a sheet inviting the player to start the FaceTime call. When a recipient accepts the FaceTime call, the system prompts them to join the `GuessTogetherActivity`:

@ObservedObject
private var groupStateObserver = GroupStateObserver()

@State
private var isActivitySharingViewPresented = false

@State
private var isActivationErrorViewPresented = false

let activity: ActivityType

init(_ text: any StringProtocol, activity: ActivityType) {
self.text = text
self.activity = activity
self.activitySharingView = ActivitySharingView {
activity
}
}

var body: some View {
ZStack {
ShareLink(item: activity, preview: SharePreview(text)).hidden()

Button(text, systemImage: "shareplay") {
if groupStateObserver.isEligibleForGroupSession {
Task.detached {
do {
_ = try await activity.activate()
} catch {
print("Error activating activity: \(error)")

Task { @MainActor in
isActivationErrorViewPresented = true
}
}
}
} else {
isActivitySharingViewPresented = true
}
}
.tint(.green)
.sheet(isPresented: $isActivitySharingViewPresented) {
activitySharingView
}
.alert("Unable to start game", isPresented: $isActivationErrorViewPresented) {
Button("Ok", role: .cancel) { }
} message: {
Text("Please try again later.")
}
}
}
}

GroupActivitySharingController(preparationHandler: preparationHandler)
}

func updateUIViewController(_: GroupActivitySharingController, context: Context) {}
}

For more information, see Presenting SharePlay activities from your app’s UI.

### Join and manage the activity

The system creates a `GroupSession` when a player activates an activity. Players can activate an activity in several ways, at any time. This sample uses an asynchronous task in `MainView` to monitor the creation of new `GroupSession` instances for `GuessTogetherActivity`. This task calls the `observeGroupSessions` method, which receives new sessions and creates a `SessionController` to manage gameplay. A separate task detects when the session ends and cleans up the `SessionController`.

// MainView

struct MainView: View {
...

var body: some View {
Group {
...
}
.task(observeGroupSessions)
}

/// Monitor for new Guess Together group activity sessions.
@Sendable
func observeGroupSessions() async {
for await session in GuessTogetherActivity.sessions() {
let sessionController = await SessionController(session, appModel: appModel)
guard let sessionController else {
continue
}
appModel.sessionController = sessionController

// Create a task to observe the group session state and clear the
// session controller when the group session invalidates.
Task {
for await state in session.$state.values {
guard appModel.sessionController?.session.id == session.id else {
return
}

if case .invalidated = state {
appModel.sessionController = nil
return
}
}
}
}
}
}

For more information, see Joining and managing a shared activity.

### Synchronize game state by sending and receiving messages

When a player’s action changes the game state, `SessionController` uses `GroupSessionMessenger` to send an update to the other players. For example, when player X joins the red team, `TeamSelectionView` calls `SessionController.joinTeam`. This sets `SessionController.localPlayer.team`, sending a call to `SessionController.shareLocalPlayerState`.

// SessionController

func joinTeam(_ team: PlayerModel.Team?) {
localPlayer.team = team
}

...

var localPlayer: PlayerModel {
get {
players[session.localParticipant]!
}
set {
if newValue != players[session.localParticipant] {
players[session.localParticipant] = newValue
shareLocalPlayerState(newValue)
}
}
}

`SessionController.shareLocalPlayerState` uses `GroupSessionMessenger` to send player X’s new state to other players.

// SessionController+RemoteParticipantSynchronization

func shareLocalPlayerState(_ newValue: PlayerModel) {
Task {
do {
try await messenger.send(newValue)
} catch {
// Failed to send the message.
}
}
}

At the same time, `SessionController.observeRemotePlayerModelUpdates` receives and processes player state updates. Each update modifies `SessionController.players` to reflect the synchronized player state. For example, when player X joins the red team, other players are notified and update their local representation of player X’s state accordingly.

private func observeRemotePlayerModelUpdates() {
Task {
for await (player, context) in messenger.messages(of: PlayerModel.self) {
players[context.source] = player
}
}
}

For more information, see Synchronizing data during a SharePlay activity.

### Enable spatial personas in an immersive space

To display spatial Personas when an immersive space is open, set the `supportsGroupImmersiveSpace` property on `SystemCoordinator.Configuration` to `true`:

func configureSystemCoordinator() {
systemCoordinator.configuration.supportsGroupImmersiveSpace = true

...
}

In an immersive space, the system provides a shared coordinate system for participants and content. This allows you to position entities consistently across all participants’ perspectives. For example, an entity positioned 0.5 meters in front of player X appears 0.5 meters in front of player X from player Y’s perspective.

For more information, see Adding spatial Persona support to an activity.

### Specify custom positions for participants

The game has three distinct stages:

- Category-selection stage, where players choose the words and phrases they want to try to elicit from their teammates.

- Team-selection stage, where players join one of the teams.

- Game stage, where the teams take turns playing the game.

Each time the current stage changes, the `SessionController` object updates the position of the participants in the space. When selecting a category, the participants appear side by side in front of the game window. During team selection and gameplay, the game arranges players using custom spatial templates. The game specifies each arrangement of participants by changing the configuration of the `SystemCoordinator` object.

func updateSpatialTemplatePreference() {
switch game.stage {
case .categorySelection:
systemCoordinator.configuration.spatialTemplatePreference = .sideBySide
case .teamSelection:
systemCoordinator.configuration.spatialTemplatePreference = .custom(TeamSelectionTemplate())
case .inGame:
systemCoordinator.configuration.spatialTemplatePreference = .custom(GameTemplate())
}
}

When the game moves to the team-selection stage, the session rearranges the participants according to which team they choose. All participants start in the audience initially facing the app window, which displays buttons to join either the red team or blue team.

The `TeamSelectionTemplate` specifies the positions of seats during the team-selection process. Participants don’t have an assigned role initially, so the system places them in the audience seats. As participants join a team, the system moves them to the assigned seating area for their chosen team.

The spatial template specifies all seat positions up front, including seats for the blue and red teams, and the audience. Seat positions reflect the distance in meters from the app’s main window along the x and z axes. Seat roles reflect the role that a participant must have to occupy that seat. When a participant asks to join a team, the sample app assigns them the corresponding role. If a seat with that role is available, the participant receives the role and their spatial Persona moves to the next available seat.

struct TeamSelectionTemplate: SpatialTemplate {
enum Role: String, SpatialTemplateRole {
case blueTeam
case redTeam
}

/// An array of seating positions the game uses to position spatial Personas during the team-selection stage.
///
/// The game fills the seats with participants based on the order of the array's elements.
let elements: [any SpatialTemplateElement] = [\
// Blue team:\
.seat(position: .app.offsetBy(x: -2.5, z: 3.5), role: Role.blueTeam),\
.seat(position: .app.offsetBy(x: -3.0, z: 3.0), role: Role.blueTeam),\
.seat(position: .app.offsetBy(x: -3.5, z: 2.5), role: Role.blueTeam),\
\
// Starting positions:\
.seat(position: .app.offsetBy(x: 0, z: 4)),\
.seat(position: .app.offsetBy(x: 1, z: 4)),\
.seat(position: .app.offsetBy(x: -1, z: 4)),\
.seat(position: .app.offsetBy(x: 2, z: 4)),\
.seat(position: .app.offsetBy(x: -2, z: 4)),\
\
// Red team:\
.seat(position: .app.offsetBy(x: 2.5, z: 3.5), role: Role.redTeam),\
.seat(position: .app.offsetBy(x: 3.0, z: 3.0), role: Role.redTeam),\
.seat(position: .app.offsetBy(x: 3.5, z: 2.5), role: Role.redTeam)\
]
}

During gameplay, teams take turns playing the game while the audience watches. Audience members face the main window while the active team sits on either side of that window. The team member giving clues sits on one side of the window, while their teammates sit opposite. The template orients the active team members so that they face each other at the start of the game, with audience members facing the main window.

The `GameTemplate` structure defines separate roles for the current player and the active team members. Members of the opposing team don’t receive a role until it’s their turn to play, so they initially sit in the audience positions. Because the active team members face each other, and not the app window, their seat positions include a `direction` parameter to specify where they look initially.

struct GameTemplate: SpatialTemplate {
enum Role: String, SpatialTemplateRole {
case player
case activeTeam
}

static let playerPosition = Point3D(x: -2, z: 3)

/// An array that represents the order in which the game adds participants to spatial template positions.
var elements: [any SpatialTemplateElement] {
let activeTeamCenterPosition = SpatialTemplateElementPosition.app.offsetBy(x: 2, z: 3)

let playerSeat = SpatialTemplateSeatElement(
position: .app.offsetBy(x: Self.playerPosition.x, z: Self.playerPosition.z),
direction: .lookingAt(activeTeamCenterPosition),
role: Role.player
)

let activeTeamSeats: [any SpatialTemplateElement] = [\
.seat(\
position: activeTeamCenterPosition.offsetBy(x: 0, z: -0.5),\
direction: .lookingAt(playerSeat),\
role: Role.activeTeam\
),\
.seat(\
position: activeTeamCenterPosition.offsetBy(x: 0, z: 0.5),\
direction: .lookingAt(playerSeat),\
role: Role.activeTeam\
)\
]

let audienceSeats: [any SpatialTemplateElement] = [\
.seat(position: .app.offsetBy(x: 0, z: 5)),\
.seat(position: .app.offsetBy(x: 1, z: 5)),\
.seat(position: .app.offsetBy(x: -1, z: 5)),\
.seat(position: .app.offsetBy(x: 2, z: 5)),\
.seat(position: .app.offsetBy(x: -2, z: 5))\
]

return audienceSeats + [playerSeat] + activeTeamSeats
}
}

For more information about building custom spatial templates, see `SpatialTemplate`.

## See Also

### Custom spatial templates

`protocol SpatialTemplate`

An interface you use to create custom arrangements of spatial Personas in a scene.

`struct SpatialTemplatePreference`

A structure that specifies the preferred arrangement of participant spatial Personas in a shared simulation space.

`struct SpatialTemplateSeatElement`

A spatial template element that represents a seat for a participant in the activity.

`protocol SpatialTemplateElement`

An interface that defines an element in your spatial template.

`struct SpatialTemplateElementPosition`

A type that defines the position of an element in a spatial template.

`struct SpatialTemplateElementDirection`

The initial direction a participant faces when an activity starts.

`protocol SpatialTemplateRole`

An interface for defining roles that you assign to the participants of a group activity.

---

# https://developer.apple.com/documentation/groupactivities/spatialtemplatepreference

- Group Activities
- SpatialTemplatePreference

Structure

# SpatialTemplatePreference

A structure that specifies the preferred arrangement of participant spatial Personas in a shared simulation space.

struct SpatialTemplatePreference

## Overview

Use the static members of this structure to specify your preferred arrangement of participants around your app’s content. The system applies your preference only when displaying spatial Personas in the scene.

## Topics

### Getting the spatial position preferences

`static let none: SpatialTemplatePreference`

An arrangement where the system places spatial Personas based on your app’s content.

`static let sideBySide: SpatialTemplatePreference`

An arrangement where the participants sit in a line with the content in front of them.

`static let conversational: SpatialTemplatePreference`

An arrangement where the participants can see one another and the app’s content.

Creates a template preference with the given custom spatial template.

### Specifying the distance between content and participants

Sets the distance between the app’s content and any participants.

### Getting the template description

`var description: String`

A textual representation of this instance.

### Type Properties

`static let surround: SpatialTemplatePreference`

An arrangement where the participants sit around the content.

## Relationships

### Conforms To

- `CustomStringConvertible`
- `Sendable`
- `SendableMetatype`

## See Also

### Custom spatial templates

Building a guessing game for visionOS

Create a team-based guessing game for visionOS using Group Activities.

`protocol SpatialTemplate`

An interface you use to create custom arrangements of spatial Personas in a scene.

`struct SpatialTemplateSeatElement`

A spatial template element that represents a seat for a participant in the activity.

`protocol SpatialTemplateElement`

An interface that defines an element in your spatial template.

`struct SpatialTemplateElementPosition`

A type that defines the position of an element in a spatial template.

`struct SpatialTemplateElementDirection`

The initial direction a participant faces when an activity starts.

`protocol SpatialTemplateRole`

An interface for defining roles that you assign to the participants of a group activity.

---

# https://developer.apple.com/documentation/groupactivities/spatialtemplateseatelement

- Group Activities
- SpatialTemplateSeatElement

Structure

# SpatialTemplateSeatElement

A spatial template element that represents a seat for a participant in the activity.

struct SpatialTemplateSeatElement

## Overview

Add `SpatialTemplateSeatElement` types to a custom `SpatialTemplate` to specify the placement and orientation of participants in a group activity. When an activity starts, the system places participants into the shared coordinate space and orients them according to the seat information you provide. If you associate roles with one or more seats, participants must acquire the associated role before they can occupy the corresponding seat.

Create seat elements directly from this type and add them to the `elements` property of your custom template. Alternatively, use the inherited `seat(position:direction:role:)` function to create seats, as shown in the following example, which creates two seats on either side of the app’s content along the z-axis:

struct BasicTemplate: SpatialTemplate {
var elements: [any SpatialTemplateElement] = [\
.seat(position: .app.offsetBy(x: 0, z: 1)),\
.seat(position: .app.offsetBy(x: 0, z: -1)),\
]
}

## Topics

### Getting the element details

`let position: SpatialTemplateElementPosition`

The location of the element in the shared coordinate space.

`let direction: SpatialTemplateElementDirection`

The initial orientation of the element in the shared coordinate space.

`let role: (any SpatialTemplateRole)?`

An optional role you associate with this element.

### Operators

Returns a Boolean value that indicates whether two values are equal.

### Initializers

`init(position: SpatialTemplateElementPosition, direction: SpatialTemplateElementDirection, role: (any SpatialTemplateRole)?)`

Creates a seat element with the specified position, direction, and role information.

### Instance Properties

`var hashValue: Int`

The hash value.

### Instance Methods

`func hash(into: inout Hasher)`

Hashes the essential components of this value by feeding them into the given hasher.

## Relationships

### Conforms To

- `Equatable`
- `Hashable`
- `Sendable`
- `SendableMetatype`
- `SpatialTemplateElement`

## See Also

### Custom spatial templates

Building a guessing game for visionOS

Create a team-based guessing game for visionOS using Group Activities.

`protocol SpatialTemplate`

An interface you use to create custom arrangements of spatial Personas in a scene.

`struct SpatialTemplatePreference`

A structure that specifies the preferred arrangement of participant spatial Personas in a shared simulation space.

`protocol SpatialTemplateElement`

An interface that defines an element in your spatial template.

`struct SpatialTemplateElementPosition`

A type that defines the position of an element in a spatial template.

`struct SpatialTemplateElementDirection`

The initial direction a participant faces when an activity starts.

`protocol SpatialTemplateRole`

An interface for defining roles that you assign to the participants of a group activity.

---

# https://developer.apple.com/documentation/groupactivities/spatialtemplateelement

- Group Activities
- SpatialTemplateElement

Protocol

# SpatialTemplateElement

An interface that defines an element in your spatial template.

protocol SpatialTemplateElement : Hashable, Sendable

## Overview

A type that adopts the `SpatialTemplateElement` protocol defines the location and orientation of a participant in a group activity. You don’t adopt this protocol directly in your custom types. Instead, you use types that adopt this protocol to retrieve the corresponding details.

## Topics

### Creating a seat position

Creates a seat element with the specified position, direction, and role information.

### Getting the element details

`var position: SpatialTemplateElementPosition`

The location of the element in the shared coordinate space.

**Required**

`var direction: SpatialTemplateElementDirection`

The initial orientation of the element in the shared coordinate space.

`var role: (any SpatialTemplateRole)?`

An optional role you associate with this element.

## Relationships

### Inherits From

- `Equatable`
- `Hashable`
- `Sendable`
- `SendableMetatype`

### Conforming Types

- `SpatialTemplateSeatElement`

## See Also

### Custom spatial templates

Building a guessing game for visionOS

Create a team-based guessing game for visionOS using Group Activities.

`protocol SpatialTemplate`

An interface you use to create custom arrangements of spatial Personas in a scene.

`struct SpatialTemplatePreference`

A structure that specifies the preferred arrangement of participant spatial Personas in a shared simulation space.

`struct SpatialTemplateSeatElement`

A spatial template element that represents a seat for a participant in the activity.

`struct SpatialTemplateElementPosition`

A type that defines the position of an element in a spatial template.

`struct SpatialTemplateElementDirection`

The initial direction a participant faces when an activity starts.

`protocol SpatialTemplateRole`

An interface for defining roles that you assign to the participants of a group activity.

---

# https://developer.apple.com/documentation/groupactivities/spatialtemplateelementposition



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplateelementdirection



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplaterole

- Group Activities
- SpatialTemplateRole

Protocol

# SpatialTemplateRole

An interface for defining roles that you assign to the participants of a group activity.

protocol SpatialTemplateRole : Hashable, Sendable

## Overview

Adopt the `SpatialTemplateRole` interface in a custom `enum` and use it with your custom spatial template. Roles are an optional way for you to assign a purpose to participants with a spatial Persona. For example, a spatial template for a game might define roles for the opposing teams. When a participant joins an activity, assign one of your custom roles to place them in a specific seat of your template. Seats in the template are available only to participants with spatial Personas.

The following example shows a spatial template for a table tennis game with two teams. The first four seats are for the players of the team, and the last seat is for a spectator. When participants request a role for the red or blue team, the template assigns them to the first available seat in the array with that role.

struct SimpleTableTennis: SpatialTemplate {
enum Role: String, SpatialTemplateRole {
case blueTeam
case redTeam
}

var elements: [any SpatialTemplateElement] = [\
.seat(position: .app.offsetBy(x: -1, z: -3), role: Role.blueTeam),\
.seat(position: .app.offsetBy(x: -1, z: 3), role: Role.redTeam),\
\
.seat(position: .app.offsetBy(x: 1, z: -3), role: Role.blueTeam),\
.seat(position: .app.offsetBy(x: 1, z: 3), role: Role.redTeam),\
\
.seat(position: .app.offsetBy(x: -2, z: 0)),\
]
}

## Topics

### Getting the role identifier

`var roleIdentifier: String`

The unique identifier string for the role.

**Required** Default implementation provided.

## Relationships

### Inherits From

- `Equatable`
- `Hashable`
- `Sendable`
- `SendableMetatype`

## See Also

### Custom spatial templates

Building a guessing game for visionOS

Create a team-based guessing game for visionOS using Group Activities.

`protocol SpatialTemplate`

An interface you use to create custom arrangements of spatial Personas in a scene.

`struct SpatialTemplatePreference`

A structure that specifies the preferred arrangement of participant spatial Personas in a shared simulation space.

`struct SpatialTemplateSeatElement`

A spatial template element that represents a seat for a participant in the activity.

`protocol SpatialTemplateElement`

An interface that defines an element in your spatial template.

`struct SpatialTemplateElementPosition`

A type that defines the position of an element in a spatial template.

`struct SpatialTemplateElementDirection`

The initial direction a participant faces when an activity starts.

---

# https://developer.apple.com/documentation/groupactivities/synchronizing-data-during-a-shareplay-activity

- Group Activities
- Synchronizing data during a SharePlay activity

Article

# Synchronizing data during a SharePlay activity

Send custom messages and data between devices to synchronize content for your activity, and incorporate messages your app receives from other participants.

## Overview

During a typical activity, you want the content one participant sees on their device to match the content other participants see. To make this happen, share data between devices to keep those devices in sync. For example, a drawing app might share the tool state and coordinate points for pen strokes. You then incorporate that shared data into your app, recreating the content that other participants created on their devices.

When an activity-related session is active, share data among participants using the objects of the Group Activities framework. You can share data with all participants or a subset of participants. For example, a quiz game might share different information with contestants and the people asking the questions. For time-sensitive messages, send small amounts of data using a `GroupSessionMessenger` object. When the amount of data is larger and the arrival time is less important, share that data using a `GroupSessionJournal` object.

### Define the messages to send

During the creation of an activity, think about what information you need to share among participants:

- A drawing app might share the state of the tools and the points for line segments.

- A movie-playback app might share commands to start and stop playback and synchronize the current frame.

- A shopping app might share the ID of the current product page and synchronize items in the shared shopping cart.

- A workout app might share workout stats for each participant and which track to play.

After you identify the information you want to send, design data types to encapsulate the relevant details. You can send the details using a `Data` object, or design your own custom types that adopt the `Codable` protocol. The following example shows a message structure for a drawing activity. Each message incorporates the next point in the line segment and the color of the segment. When someone draws, the app sends one message for each new point it receives. Small messages can include up to 256 kilobytes of data, but keep the total size as small as possible to minimize the time it takes to send and process the data.

struct PenStrokeMessage: Codable {
let id: UUID
let color: Stroke.Color
let point: CGPoint
}

When you need to send photos, videos, audio, or other large data types, encode that information into a type that adopts the `Transferable` protocol. The `GroupSessionJournal` object requires this protocol when sending types.

### Send a message to one or more participants

When the person running your app on their device makes activity-related changes, send those changes to other affected participants using a `GroupSessionMessenger` object. When you send data, you’re actually sending it from one instance of your app to another instance of your app on a different device. The `GroupSessionMessenger` object delivers the data over the network to the part of your app configured to receive that data.

When creating the `GroupSessionMessenger` object, determine whether you need reliable or unreliable delivery for messages. Choose `GroupSessionMessenger.DeliveryMode.reliable` messaging for crucial data that all participants must have. With reliable messaging, the system performs additional checks to verify the delivery of messages, and resends them as needed. By contrast, `GroupSessionMessenger.DeliveryMode.unreliable` messaging is generally faster, and is appropriate when the delivery time is more important than the guarantee of delivery. For example, for a movie-watching activity, you might send the name of the movie using reliable messaging, but send the emoji reactions of participants during the movie using unreliable messaging. All participants need to know which movie to watch, but the emoji reactions are time-critical and less important.

After creating your `GroupSessionMessenger` object, send your messages using one of the available methods. The following example sends a custom data type to all members of the group:

Task {
try? await messenger.send(PenStrokeMessage(id: stroke.id,
color: stroke.color, point: point))
}

To send a message to a subset of participants, include the list of participants when calling the send method. The `GroupSession` object maintains a set of `Participant` structures, each of which identifies a member taking part in the activity. Use the `UUID` of each participant to differentiate them within your app. For example, a quiz game app randomly chooses a subset of participants to take the quiz and share their unique IDs with the group. The person giving the quiz then sends only the questions to the people taking the quiz, and sends the questions and answers to everyone else. The following example subtracts the current participant from the set of all participants and sends a ready message to that subset of people:

let everyoneElse = session.activeParticipants.subtracting([session.localParticipant])

messenger.send(ReadyStateMessage(ready: true), to: .only(everyoneElse)) { error in
if let error = error { print("Message failure:", error) }
}

### Receive messages from other participants

Messages targeting the current participant can arrive at any time, so it’s best to use a separate task to listen for them. The `GroupSessionMessenger` object delivers messages using an `AsyncSequence`, which makes it easy to receive those messages asynchronously. Respond to incoming messages as quickly as possible by updating your app’s data structures to include the new information.

When configuring your session, define a task to receive incoming messages for your activity. Inside the task, use a `for..in` loop to wait on the messages property of your `GroupSessionMessenger` object. Specify which message you want to receive as a parameter to the messages method. For example, the code below shows how to process incoming pen stroke messages. The function returns a tuple for each element, with each tuple containing the incoming message and any related contextual information. The message is the data structure you defined previously. The contextual information is a `GroupSessionMessenger.MessageContext` structure with additional details, such as the participant who sent the message.

var task = Task {
for await (message, context) in messenger.messages(of: PenStrokeMessage.self) {
print("Participant ID: \(context.source.id)")
handle(message)
}

Create separate tasks to monitor each distinct message type your activity supports. If you have multiple activities, and each one has multiple messages, this results in multiple separate tasks. However, each task runs only when messages are available.

### Share files among participants

To share files and other large data objects with participants of an activity, use a `GroupSessionJournal` object instead of a `GroupSessionMessenger`. A `GroupSessionJournal` object lets you associate multiple data objects or files with the activity as attachments to the session. The size limit for attachments is 100 megabytes, and the system provides end-to-end encryption for your data.

Attachments are ideal when you need to send more than just a few kilobytes of information to other participants, and want to do so as efficiently as possible. Use them to send images or large data objects that the group creates or adds to the activity. The Group Activities framework efficiently manages the transfer of attachments among devices, avoiding multiple downloads of the same data to each device.

The `GroupSessionJournal` object delivers attachments to your app using an `AsyncSequence` type. To receive attachments, configure a task and use a `for..in` loop and wait on the attachments property of your journal object, as shown in the following example. When attachments are available for your device, the system wakes up your task and delivers an array of `GroupSessionJournal.Attachment` structures for you to process.

task = Task {
for await images in journal.attachments {
await handleImages(images)
}
}

Use the `GroupSessionJournal.Attachment` structures your app receives to download the attachment data and fetch any related metadata. You can then use that data to create any local data structures you need to update the state of your activity. The following example shows how to iterate over the attachments you receive and fetch the data for each one. The `ImageMetadataMessage` type is a custom structure the activity uses to store extra information about the image data.

func handleImages(_ attachments: GroupSessionJournal.Attachments.Element) async {
attachments.forEach { attachment in
let metadata = try await attachment.loadMetadata(of:
ImageMetadataMessage.self)
let imageData = try await attachment.load(Data.self)

// Use the data to create app-specific structures and
// update the activity.
}
}

For more information about storing files and data attachments, see `GroupSessionJournal`.

## See Also

### File and data transfer

`class GroupSessionMessenger`

An object that transfers app-specific data between the devices joined in a group session.

`class GroupSessionJournal`

An object that manages file and data transfers between participants joined in a group session.

---

# https://developer.apple.com/documentation/groupactivities/groupsessionjournal

- Group Activities
- GroupSessionJournal

Class

# GroupSessionJournal

An object that manages file and data transfers between participants joined in a group session.

final class GroupSessionJournal

## Mentioned in

Synchronizing data during a SharePlay activity

## Overview

A `GroupSessionJournal` object lets you transfer files and other data objects between participants of a shared activity. A journal object isn’t a replacement for a `GroupSessionMessenger` object, which you use to transfer time-sensitive messages and commands between participants. Instead, use it to associate files and other data objects with the activity. For example, you might share images that people drag into your app as part of the activity. The journal makes these data objects available to all participants, regardless of when they joined the session.

After your app joins an activity and receives a session object, create a `GroupSessionJournal` object and store a strong reference to it. To add a file or data object to the group’s journal, call the `add(_:)` or `add(_:metadata:)` method with the data you want to share. The types you specify must adopt the `Transferable` protocol from the Core Transferable framework. The journal object uses that protocol to package a version of your data suitable for sending to other devices.

To receive data that a participant added to the journal, configure a task to listen for asynchronous updates to the `attachments` property of your `GroupSessionJournal` object. When someone adds or removes an attachment, the journal updates the array and executes your task. Load the contents of an attachment using the `load(_:)` method of that type. You can also retrieve any attachment-specific metadata, such as a shared ID or display name, that you included with the attached file. The following example creates a task that waits on a custom image type. The `journal` variable contains a previously configured `GroupSessionJournal` object.

let attachmentListener = Task {
for await attachments in journal.attachments {
for attachment in attachments {
let receivedItem = try await attachment.load(MyImageItem.self)
// Do something with the item you receive.
}
}
}

## Topics

### Creating an attachment manager

Creates a journal and associates it with the specified session of a group activity.

### Uploading content to the session

Adds the specified item to the journal and begins transferring the item’s data to the other participants’ devices so they can access it.

Adds the specified item and metadata to the journal and begins transferring the data to the other participants’ devices so they can access it.

### Downloading content from the session

`var attachments: GroupSessionJournal.Attachments`

The currently available attachments for you to download and incorporate into your app.

`struct Attachments`

An asynchronous sequence that contains one or more incoming attachment containers for you to process.

`struct Attachment`

A container for the data you download.

### Removing content from the session

`func remove(attachment: GroupSessionJournal.Attachment) async throws`

Removes the specified attachment from the journal on all sessions.

## Relationships

### Conforms To

- `Sendable`
- `SendableMetatype`

## See Also

### File and data transfer

Send custom messages and data between devices to synchronize content for your activity, and incorporate messages your app receives from other participants.

`class GroupSessionMessenger`

An object that transfers app-specific data between the devices joined in a group session.

---

# https://developer.apple.com/documentation/groupactivities/groupactivity)



---

# https://developer.apple.com/documentation/groupactivities/groupsession)



---

# https://developer.apple.com/documentation/groupactivities/defining-your-apps-shareplay-activities)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/groupactivitymetadata)



---

# https://developer.apple.com/documentation/groupactivities/groupactivityactivationresult)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/groupactivitytransferrepresentation)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/groupactivitysharingcontroller-4gtfk)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/groupactivitysharingcontroller-ybcy)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/joining-and-managing-a-shared-activity)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/drawing_content_in_a_group_session)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/custommessageidentifiable)



---

# https://developer.apple.com/documentation/groupactivities/participant)



---

# https://developer.apple.com/documentation/groupactivities/adding-spatial-persona-support-to-an-activity)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator)



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/participantstate)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/groupactivityassociationinteraction)



---

# https://developer.apple.com/documentation/groupactivities/groupactivityassociationkind)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/building-a-guessing-game-for-visionos)



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplate)



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplatepreference)



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplateseatelement)



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplateelement)



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplateelementposition)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/spatialtemplateelementdirection)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/spatialtemplaterole)



---

# https://developer.apple.com/documentation/groupactivities/synchronizing-data-during-a-shareplay-activity)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/groupsessionmessenger)



---

# https://developer.apple.com/documentation/groupactivities/groupsessionjournal)



---

# https://developer.apple.com/documentation/groupactivities/groupsession/localparticipant



---

# https://developer.apple.com/documentation/groupactivities/groupsession/localparticipant)



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplate/elements



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplate/configuration



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplateconfiguration



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplate/elements)



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplate/configuration)



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplateconfiguration)



---

# https://developer.apple.com/documentation/groupactivities/participant/id-swift.property

- Group Activities
- Participant
- id

Instance Property

# id

A globally unique identifier for the session participant.

let id: UUID

## Discussion

Use this property to differentiate among the devices active in a session.

---

# https://developer.apple.com/documentation/groupactivities/participant/!=(_:_:)

#app-main)

- Group Activities
- Participant
- !=(\_:\_:)

Operator

# !=(\_:\_:)

Returns a Boolean value indicating whether two values are not equal.

Group ActivitiesSwift

## Parameters

`lhs`

A Value to compare.

`rhs`

Another value to compare.

## Discussion

Inequality is the inverse of equality. For any values `a` and `b`, `a != b` implies that `a == b` is `false`.

This is the default implementation of the not-equal-to operator ( `!=`) for any type that conforms to `Equatable`.

## See Also

### Comparing participants

Returns a Boolean value indicating whether two values are equal.

---

# https://developer.apple.com/documentation/groupactivities/participant/==(_:_:)

#app-main)

- Group Activities
- Participant
- ==(\_:\_:)

Operator

# ==(\_:\_:)

Returns a Boolean value indicating whether two values are equal.

## Parameters

`lhs`

A value to compare.

`rhs`

Another value to compare.

## Discussion

Equality is the inverse of inequality. For any values `a` and `b`, `a == b` implies that `a != b` is `false`.

## See Also

### Comparing participants

Returns a Boolean value indicating whether two values are not equal.

---

# https://developer.apple.com/documentation/groupactivities/participant/hashvalue

- Group Activities
- Participant
- hashValue

Instance Property

# hashValue

The hash value.

var hashValue: Int { get }

## Discussion

Hash values are not guaranteed to be equal across different executions of your program. Do not save hash values to use during a future execution.

---

# https://developer.apple.com/documentation/groupactivities/participant/hash(into:)

#app-main)

- Group Activities
- Participant
- hash(into:)

Instance Method

# hash(into:)

Hashes the essential components of this value by feeding them into the given hasher.

func hash(into hasher: inout Hasher)

## Parameters

`hasher`

The hasher to use when combining the components of this instance.

## Discussion

Implement this method to conform to the `Hashable` protocol. The components used for hashing must be the same as the components compared in your type’s `==` operator implementation. Call `hasher.combine(_:)` with each of these components.

---

# https://developer.apple.com/documentation/groupactivities/participant/id-swift.typealias

- Group Activities
- Participant
- Participant.ID

Type Alias

# Participant.ID

A type representing the stable identity of the entity associated with an instance.

typealias ID = UUID

---

# https://developer.apple.com/documentation/groupactivities/participant/customstringconvertible-implementations

Collection

- Group Activities
- Participant
- CustomStringConvertible Implementations

API Collection

# CustomStringConvertible Implementations

## Topics

### Instance Properties

`var description: String`

A textual representation of this instance.

---

# https://developer.apple.com/documentation/groupactivities/participant/equatable-implementations

Collection

- Group Activities
- Participant
- Equatable Implementations

API Collection

# Equatable Implementations

## Topics

### Operators

Returns a Boolean value indicating whether two values are not equal.

---

# https://developer.apple.com/documentation/groupactivities/groupsession/activeparticipants)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/participant/id-swift.property)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/participant/!=(_:_:))



---

# https://developer.apple.com/documentation/groupactivities/participant/==(_:_:))



---

# https://developer.apple.com/documentation/groupactivities/participant/hashvalue)



---

# https://developer.apple.com/documentation/groupactivities/participant/isnearbywithlocalparticipant)



---

# https://developer.apple.com/documentation/groupactivities/participant/hash(into:))



---

# https://developer.apple.com/documentation/groupactivities/participant/id-swift.typealias)



---

# https://developer.apple.com/documentation/groupactivities/participant/customstringconvertible-implementations)



---

# https://developer.apple.com/documentation/groupactivities/participant/equatable-implementations)



---

# https://developer.apple.com/documentation/groupactivities/groupactivity/prepareforactivation()



---

# https://developer.apple.com/documentation/groupactivities/groupstateobserver/iseligibleforgroupsession)



---

# https://developer.apple.com/documentation/groupactivities/groupstateobserver).



---

# https://developer.apple.com/documentation/groupactivities/groupactivity/prepareforactivation())



---

# https://developer.apple.com/documentation/groupactivities/groupactivity/activate())



---

# https://developer.apple.com/documentation/groupactivities/adding-spatial-persona-support-to-an-activity).



---

# https://developer.apple.com/documentation/groupactivities/groupactivityactivationresult/activationpreferred



---

# https://developer.apple.com/documentation/groupactivities/groupactivityactivationresult/activationpreferred)



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/configuration-swift.struct



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/configuration-swift.struct/spatialtemplatepreference



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/configuration-swift.struct)



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/configuration-swift.struct/spatialtemplatepreference)



---

# https://developer.apple.com/documentation/groupactivities/groupactivity/activityidentifier

- Group Activities
- GroupActivity
- activityIdentifier

Type Property

# activityIdentifier

An app-defined string that uniquely identifies the activity.

static var activityIdentifier: String { get }

**Required** Default implementation provided.

## Mentioned in

Defining your app’s SharePlay activities

Adding spatial Persona support to an activity

## Discussion

Implement this property and return a value that uniquely identifies the activity within your app. An app may support multiple activities, and each activity requires a unique identifier string. Use reverse-DNS notation for your identifier strings. For example, supply a string like `"com.mycompany.myapp.watchmovie"` for a movie-watching activity.

If you don’t implement this property yourself, the default implementation composes an activity identifier using your app’s bundle identifier and the current class or struct name. For example, if the app’s bundle identifier is `"com.mycompany.myapp"` and your activity type name is `MovieActivity`, the resulting identifier string is `"com.mycompany.myapp.MovieActivity"`.

## Default Implementations

### GroupActivity Implementations

`static var activityIdentifier: String`

## See Also

### Specifying the activity details

`var metadata: GroupActivityMetadata`

A description of the activity, and optional image to display to the user.

**Required**

---

# https://developer.apple.com/documentation/groupactivities/groupactivitymetadata/sceneassociationbehavior

- Group Activities
- GroupActivityMetadata
- sceneAssociationBehavior

Instance Property

# sceneAssociationBehavior

Criteria the system uses to direct an activity to a specific scene of your app.

var sceneAssociationBehavior: SceneAssociationBehavior

## Mentioned in

Adding spatial Persona support to an activity

## Discussion

An app with multiple `Scene` types typically uses each scene for a different purpose. For example, you might use one scene type for your app’s documents, and a different scene type for tool palettes, information windows, and other content. When a group activity starts, the system uses the information in this property to deliver the activity to the appropriate scene. On some platforms, the system also adds a custom indicator to the scene to let people know that SharePlay is active.

Assign a value to this property to specify the scene-selection behavior for your app. If you don’t specify a value for this property, the system adopts the `default` scene association behavior.

## See Also

### Assigning an app-specific scene

`struct SceneAssociationBehavior`

A type that tells the system which scene to associate with an incoming group activity.

---

# https://developer.apple.com/documentation/groupactivities/sceneassociationbehavior/default



---

# https://developer.apple.com/documentation/groupactivities/sceneassociationbehavior/content(_:)

#app-main)

- Group Activities
- SceneAssociationBehavior
- content(\_:)

Type Method

# content(\_:)

A behavior that matches the activity to a scene using a custom string that you supply.

## Parameters

`contentIdentifier`

The string to compare against the scene’s defined activation conditions. This string has a similar purpose to the `targetContentIdentifier` of an `NSUserActivity` object.

## Return Value

A `SceneAssociationBehavior` type with the specified identifier.

## Mentioned in

Adding spatial Persona support to an activity

## Discussion

Use this option when you want more control over the scene-selection process for your `GroupActivity` object. You might use it to direct the activity to different scenes, or to direct the activity to a specific instance of a scene. For example, a drawing app might direct the activity to the specific canvas someone wants to share, and not to a new or unrelated canvas that uses the same scene type.

## See Also

### Getting the scene-association options

``static let `default`: SceneAssociationBehavior``

A behavior that matches the activity to a scene using the identifier of your activity object.

`static let none: SceneAssociationBehavior`

A behavior that doesn’t match any scenes to the activity.

---

# https://developer.apple.com/documentation/groupactivities/sceneassociationbehavior/none

- Group Activities
- SceneAssociationBehavior
- none

Type Property

# none

A behavior that doesn’t match any scenes to the activity.

static let none: SceneAssociationBehavior

## Mentioned in

Adding spatial Persona support to an activity

## Discussion

Choose this option when you don’t want the system to associate one of your scenes with the SharePlay activity. You might choose this option when you handle an activity separately from your app’s scenes.

## See Also

### Getting the scene-association options

``static let `default`: SceneAssociationBehavior``

A behavior that matches the activity to a scene using the identifier of your activity object.

A behavior that matches the activity to a scene using a custom string that you supply.

---

# https://developer.apple.com/documentation/groupactivities/groupsession/join()



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplatepreference/contentextent(_:)

#app-main)

- Group Activities
- SpatialTemplatePreference
- contentExtent(\_:)

Instance Method

# contentExtent(\_:)

Sets the distance between the app’s content and any participants.

## Mentioned in

Adding spatial Persona support to an activity

## Discussion

Use this modifier to set the distance between your app’s content and the participants in a shared context. You might use this modifier if the intrinsic size of your content doesn’t represent an optimal viewing distance. Specify the new size in points.

If you don’t apply this modifier, the system uses the intrinsic size of the scene’s content to determine the viewing distance for participants.

---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/participantstate/isspatial

- Group Activities
- SystemCoordinator
- SystemCoordinator.ParticipantState
- isSpatial

Instance Property

# isSpatial

A Boolean value that indicates whether the person supports being in a shared simulation space for an activity.

let isSpatial: Bool

## Mentioned in

Adding spatial Persona support to an activity

## Discussion

The value of this property is `true` when the current person supports activities that place participants relative to the activity itself. The person must use a device that supports spatial experiences, and must configure their spatial Persona to support inclusion in a shared simulation space.

---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/groupimmersionstyle

- Group Activities
- SystemCoordinator
- groupImmersionStyle

Instance Property

# groupImmersionStyle

The presentation style to apply to an immersive space for the current activity.

GroupActivitiesSwiftUI

final var groupImmersionStyle: SystemCoordinator.GroupImmersionStyles { get }

## Mentioned in

Adding spatial Persona support to an activity

## Discussion

During an activity, the system uses this property to communicate the style for a currently open immersive space. When no participants are displaying an immersive space, the value of this property is `nil`. When any participant displays a space, the system sets the value for all participants to the immersion style of the newly presented space. When a participant presents a space with a different presentation style, the system also updates the property to reflect the new style. For example, if the group is currently in a space with the `full` style, it updates the property when someone presents a space with the `full` style.

Use this property to synchronize the level of immersion for all participants. Keeping the participants at the same level of immersion preserves the shared context of your activity. When the value of the property changes, transition the current participant to the new immersion level only if doing so doesn’t disrupt any other ongoing tasks. For example, if the current person is editing content in an unrelated window, don’t transition them automatically. Instead, give them the choice of when to make the transition.

## See Also

### Getting the current immersion level

`struct GroupImmersionStyles`

An asynchronous sequence that contains one or more incoming immersion styles for you to process.

---

# https://developer.apple.com/documentation/groupactivities/defining-your-apps-shareplay-activities).



---

# https://developer.apple.com/documentation/groupactivities/groupactivity/activityidentifier)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/groupactivitymetadata/sceneassociationbehavior)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/sceneassociationbehavior/default)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/sceneassociationbehavior/content(_:))

)#app-main)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/sceneassociationbehavior/none)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/groupsession/join())



---

# https://developer.apple.com/documentation/groupactivities/spatialtemplatepreference/contentextent(_:))

)#app-main)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/localparticipantstates)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/participantstate/isspatial)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/groupimmersionstyle)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/GroupActivities/GroupSession/systemCoordinator



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/configuration-swift.property



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/localparticipantstate



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/participantstates



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/groupimmersionstyles



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/assignrole(_:)



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/resignrole()



---

# https://developer.apple.com/documentation/GroupActivities/GroupSession/systemCoordinator)



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/configuration-swift.property)



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/remoteparticipantstates)



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/localparticipantstate)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/participantstates)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/groupimmersionstyles)



---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/assignrole(_:))

)#app-main)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/systemcoordinator/resignrole())

)#app-main)

# The page you're looking for can't be found.

Search developer.apple.comSearch Icon

---

# https://developer.apple.com/documentation/groupactivities/sceneassociationbehavior

- Group Activities
- SceneAssociationBehavior

Structure

# SceneAssociationBehavior

A type that tells the system which scene to associate with an incoming group activity.

struct SceneAssociationBehavior

## Overview

Use a `SceneAssociationBehavior` type to match SharePlay activities to your app’s scenes. The static accessors of this type offer different scene-selection behaviors. For example, you can match each activity type to a specific scene, match scenes dynamically based on the contents of the activity, or prevent matching altogether. Select one of these behaviors and assign the related type to your `GroupActivity` object’s metadata. On some platforms, the system adds a custom indicator to a scene to let people know that SharePlay is active.

Add activation conditions to your SwiftUI or UIKit scenes to tell the system which activities they support. An activation condition is a custom string that identifies one of your app’s supported activities. You add these strings to your scenes to direct different types of external events to them. In SwiftUI, specify the activation conditions for a scene using the `handlesExternalEvents(matching:)` modifier. In the following example, the scene handles two app-related activities, including a group activity.

let activationConditions : Set = ["com.mycompany.MySharePlayActivity",\
"com.mycompany.MyUserActivity"]
var body: some Scene {
WindowGroup {
ContentView()
}
.handlesExternalEvents(matching: activationConditions)

To handle the same activation condition in a UIKit app, add rules to the `activationConditions` property of your `UIScene` object. Assign these rules in the `scene(_:willConnectTo:options:)` method when you first configure your scene for use. Use the `prefersToActivateForTargetContentIdentifierPredicate` property when the scene is the preferred choice for handling the action. The following example shows how to configure a scene to handle two app-related activities, including a group activity.

let activationConditions = ["com.example.MySharePlayActivity", "com.example.MyUserActivity"]
func scene(_ scene: UIScene,
willConnectTo session: UISceneSession,
options connectionOptions: UIScene.ConnectionOptions) {
// Specify the activities that this scene prefers to handle.
scene.activationConditions.prefersToActivateForTargetContentIdentifierPredicate
= NSPredicate(format: "self in %@", activationConditions)
}

## Topics

### Getting the scene-association options

``static let `default`: SceneAssociationBehavior``

A behavior that matches the activity to a scene using the identifier of your activity object.

A behavior that matches the activity to a scene using a custom string that you supply.

`static let none: SceneAssociationBehavior`

A behavior that doesn’t match any scenes to the activity.

### Operators

Returns a Boolean value indicating whether two values are equal.

## Relationships

### Conforms To

- `Equatable`
- `Sendable`
- `SendableMetatype`

## See Also

### Assigning an app-specific scene

`var sceneAssociationBehavior: SceneAssociationBehavior`

Criteria the system uses to direct an activity to a specific scene of your app.

---

# https://developer.apple.com/documentation/groupactivities/groupactivityassociationinteraction/init(associationkind:)

#app-main)

- Group Activities
- GroupActivityAssociationInteraction
- init(associationKind:) Beta

Initializer

# init(associationKind:)

Creates a group activity association interaction.

GroupActivitiesUIKit

@MainActor
init(associationKind: GroupActivityAssociationKind?)

## Parameters

`kind`

If provided, the kind of group activity association.

Beta Software

This documentation contains preliminary information about an API or technology in development. This information is subject to change, and software implemented according to this documentation should be tested with final operating system software.

Learn more about using Apple's beta software

---

# https://developer.apple.com/documentation/groupactivities/groupactivityassociationinteraction/associationkind



---

# https://developer.apple.com/documentation/groupactivities/groupactivityassociationinteraction/view

- Group Activities
- GroupActivityAssociationInteraction
- view Beta

Instance Property

# view

GroupActivitiesUIKit

@MainActor @preconcurrency
weak var view: UIView?

Beta Software

This documentation contains preliminary information about an API or technology in development. This information is subject to change, and software implemented according to this documentation should be tested with final operating system software.

Learn more about using Apple's beta software

---

# https://developer.apple.com/documentation/groupactivities/groupactivityassociationinteraction/didmove(to:)



---

# https://developer.apple.com/documentation/groupactivities/groupactivityassociationinteraction/willmove(to:)



---

# https://developer.apple.com/documentation/groupactivities/sceneassociationbehavior)



---

# https://developer.apple.com/documentation/groupactivities/groupactivityassociationinteraction/init(associationkind:))



---

# https://developer.apple.com/documentation/groupactivities/groupactivityassociationinteraction/associationkind)



---

# https://developer.apple.com/documentation/groupactivities/groupactivityassociationinteraction/view)



---

# https://developer.apple.com/documentation/groupactivities/groupactivityassociationinteraction/didmove(to:))



---

# https://developer.apple.com/documentation/groupactivities/groupactivityassociationinteraction/willmove(to:))



---

