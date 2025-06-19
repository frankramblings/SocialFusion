# Apple Documentation Context

This file contains Apple documentation that should be available in all chat sessions for SocialFusion development.

## App Intents - Making Onscreen Content Available to Siri and Apple Intelligence

### Entity Schemas for Different Domains

| Domain          | Schema                                                                              | Swift macro                                       | Example request                                                            |
| --------------- | ----------------------------------------------------------------------------------- | ------------------------------------------------- | -------------------------------------------------------------------------- |
| Browser         | [tab](/documentation/appintents/assistantschemas/browserentity/tab)                 | @AssistantEntity(schema: .browser.tab)            | A person might ask Siri questions about the web page.                      |
| Document reader | [document](/documentation/appintents/assistantschemas/readerentity/document)        | @AssistantEntity(schema: .reader.document)        | A person might ask Siri to explain the conclusion of a document.           |
| File management | [file](/documentation/appintents/assistantschemas/filesentity/file)                 | @AssistantEntity(schema: .files.file)             | A person might ask Siri to summarize file content.                         |
| Mail            | [message](/documentation/appintents/assistantschemas/mailentity/message)            | @AssistantEntity(schema: .mail.message)           | A person might ask Siri to provide a summary.                              |
| Photos          | [asset](/documentation/appintents/assistantschemas/photosentity/asset)              | @AssistantEntity(schema: .photos.asset)           | A person might ask Siri about things to do with an object in a photo.      |
| Presentations   | [document](/documentation/appintents/assistantschemas/presentationentity/document)  | @AssistantEntity(schema: .presentation.document)  | A person might ask Siri to suggest a creative title for a presentation.    |
| Spreadsheets    | [document](/documentation/appintents/assistantschemas/spreadsheetentity/document)   | @AssistantEntity(schema: .spreadsheet.document)   | A person might ask Siri to give an overview of the spreadsheet's data.     |
| Word processor  | [document](/documentation/appintents/assistantschemas/wordprocessorentity/document) | @AssistantEntity(schema: .wordProcessor.document) | A person might ask Siri to suggest additional content for a text document. |

## UIKit - Customizing Document-Based App Launch Experience

### Creating New Documents

The document viewer uses app intents to create new documents. It also uses the UIDocument.CreationIntent structure to specify the different ways your app can create documents. UIDocument already provides a default intent and the corresponding `.default` enumeration value.

To add your own intents, start by extending UIDocument.CreationIntent and adding values for your intents.

```swift
// Extend the creation intent enumeration to add custom options for document creation.
extension UIDocument.CreationIntent {
    static let template = UIDocument.CreationIntent("template")
}
```

Then call the UIDocument class's createDocumentAction(withIntent:) method to create the intent. Set the intent's title, and assign it to your UIDocumentViewController.LaunchOptions instance's primaryAction or secondaryAction properties. By default, the system automatically sets the document view controller's primaryAction to the default create document action.

```swift
// Provide an action for the secondary action.
let templateAction = LaunchOptions.createDocumentAction(withIntent: .template)

// Set the intent's title.
templateAction.title = "Choose a Template"

// Add the intent to an action.
launchOptions.secondaryAction = templateAction
```

Finally, implement the UIDocumentBrowserViewControllerDelegate protocol's documentBrowser(\_:didRequestDocumentCreationWithHandler:) method. The system calls this method when something triggers one of the create document intents. In your implementation, use the controller's activeDocumentCreationIntent to determine the intent. Create the document, and then pass the URL and the UIDocumentBrowserViewController.ImportMode to the `intentHandler`.

```swift
override func documentBrowser(_ controller: UIDocumentBrowserViewController, didRequestDocumentCreationWithHandler importHandler: @escaping (URL?, UIDocumentBrowserViewController.ImportMode) -> Void) {

    switch controller.activeDocumentCreationIntent {
    case .template:
        
        // Let someone select a template, and return
        // a URL to that template.
        let templateURL = myPresentTemplateSelection()
        
        // Pass the URL to the import handler.
        importHandler(templateURL, .copy)
        
    default:
        
        // Create the default document.
        let newDocumentURL = myCreateEmptyDocument()
        
        // Pass the URL to the import handler.
        importHandler(newDocumentURL, .move )
    }
}
```

## GroupActivities - Customizing Spatial Persona Templates

### Configuring Session to Manage Gameplay

Activities can start at any time, so the sample creates an asynchronous task in its main content view to monitor the creation of sessions for game activity. This task runs the `observeGroupSessions` method, which receives new sessions and creates a custom `SessionController` object to manage gameplay. The method also creates a separate task to detect when the session ends and to clean up the session controller object:

```swift
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
```

The custom `SessionController` object handles most of the interactions between participants. After a person joins the activity, the game has three distinct stages:

* Category-selection stage, where players choose the words and phrases they want to try to elicit from their teammates.
* Team-selection stage, where players join one of the teams.
* Game stage, where the teams take turns playing the game.

Each time the current stage changes, the `SessionController` object updates the position of the participants in the space. When selecting a category, the participants appear side by side in front of the game window. During team selection and gameplay, the game arranges players using custom spatial templates. The game specifies each arrangement of participants by changing the configuration of the SystemCoordinator object.

```swift
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
```

## GroupActivities - Drawing Content in Group Session

### Configuring Session for Sending and Receiving Custom Data

The sample uses GroupSessionMessenger to configure the session for sending and receiving its custom drawing data. The app creates a `GroupSessionMessenger` from the `GroupSession`. It also adds the `messenger` property to its `Canvas` to hold the `messenger` object.

```swift
func configureGroupSession(_ groupSession: GroupSession<DrawTogether>) {
    strokes = []

    self.groupSession = groupSession
    let messenger = GroupSessionMessenger(session: groupSession)
    self.messenger = messenger
```

When using GroupSessionMessenger, the sample code defines the type of data to exchange between participants. The app shares the strokes themselves. The sample defines the `UpsertStrokeMessage` structure to represent a stroke with three properties: an identifier, a color, and a coordinate point. The sample also specifies that the `UpsertStrokeMessage` structure conforms to the Codable protocol. `GroupSessionMessenger` automatically handles the serialization and deserialization of the message data if the messages are `Codable`.

```swift
struct UpsertStrokeMessage: Codable {
    let id: UUID
    let color: Stroke.Color
    let point: CGPoint
}
```

The second step in configuring the session is to call the GroupSessionMessenger messages(of:) method to receive the `UpsertStrokeMessages` data. The sample specifies the `UpsertStrokeMessage` type when calling the `messages` method. This method returns an async sequence that provides a tuple containing messages of that type and the context surrounding the message, such as which participant sends the message.

```swift
for await (message, _) in messenger.messages(of: UpsertStrokeMessage.self) {
    handle(message)
}
```

The third step for configuring the session is to send data using the GroupSessionMessenger send(\_:to:) method. The app sends an `UpsertStrokeMessage` to all participants within the group.

```swift
try? await messenger.send(UpsertStrokeMessage(id: stroke.id, color: stroke.color, point: point))
```

## GroupActivities - Joining and Managing Shared Activity

### Accommodating People Who Arrive Late to the Session

Participants join activities separately, and people can join immediately or after a delay. If participants need to download your app, or don't see the invitation to join the activity, they might arrive several minutes after others. If your activity manages state information that all participants require, devise a way to deliver that information to someone who arrives late. For example, a whiteboard app needs to deliver the current whiteboard content to any late joiners.

Consider the experience for people who arrive late to an activity, and plan for it when implementing your activity support. You might create a lobby interface where participants wait until everyone is present, or you might define custom messages to let people catch up with the rest of the group. Choose an experience that makes sense for your app, and remember that every participant is equal in a SharePlay activity. There's no single activity owner who controls the experience.

To determine when new participants join the session, monitor the activeParticipants property of the session using a separate task. When the list of participants changes, compare the new list with a saved copy your app maintains. When you detect new participants, update them with the current state of the activity.

```swift
Task {
    for try await updatedParticipants in session.$activeParticipants.values {
        for participant in updatedParticipants {
            // Compare the current list to a saved version you maintain.
        }
    }
}
```

## SiriKit - Improving Siri Media Interactions and App Selection

### Defining Relevant Vocabulary

Define vocabulary for Siri, both specific to the individual user and relevant for all users but exclusive to your app. Providing vocabulary helps Siri match a user's request to media items you've added to the Spotlight database or included in donated intents and interactions. Take care to include terms that include numbers or have other unusual spellings. There are two ways to provide vocabulary, and each one helps Siri interpret and route user requests:

* Global vocabulary relevant to all users of your app.
* User-specific vocabulary that you update as the user interacts with your app.

Define general terms in the Global Vocabulary Reference. Add an `AppIntentVocabulary.plist` file to your project and provide any vocabulary that's unique to your app but relevant for all users in the Parameter Vocabularies section. For more details, see Registering Custom Vocabulary with SiriKit.

Provide additional vocabulary programmatically with INVocabulary, like names that are unique or particularly important to the user, such as playlist titles. Put terms that are most important for this user or that Siri most often misunderstands first. You should update the vocabulary as needed, such as when the user renames or deletes a playlist, or begins listening to a particular artist more frequently.

## visionOS - Building Local Experiences with Room Tracking

### Configuring Room Tracking

Set up room tracking by first configuring an ARKitSession instance, then add a WorldTrackingProvider and a RoomTrackingProvider to the session as shown in the following example:

```swift
private let session = ARKitSession()
private let worldTracking = WorldTrackingProvider()
private let roomTracking = RoomTrackingProvider()
```

In addition to instantiating the world and room tracking providers in the `AppState`, you need to create storage for the in-room anchors the app tracks:

```swift
/// A dictionary that contains `RoomAnchor` structures.
private var roomAnchors = [UUID: RoomAnchor]()
/// A dictionary that contains `WorldAnchor` structures.
private var worldAnchors = [UUID: WorldAnchor]()
/// A dictionary that contains `ModelEntity` structures for spheres.
private var sphereEntities = [UUID: ModelEntity]()
/// A dictionary that contains `ModelEntity` structures for room anchors.
private var roomEntities = [UUID: ModelEntity]()
```

You also need to create the materials the framework uses to render the in-room anchors:

```swift
// Material for spheres in the current room.
private let inRoomSphereMaterial = SimpleMaterial(color: .green, roughness: 0.2, isMetallic: true)
// Material for spheres not in the current room.
private let outOfRoomSphereMaterial = SimpleMaterial(color: .red, roughness: 0.2, isMetallic: true)
// Material the app applies to room entities to show occlusion effects.
private let occlusionMaterial = OcclusionMaterial()
// Material for current room walls.
private var wallMaterial = UnlitMaterial(color: .blue)
```

## visionOS 2 Release Notes

### App Placement - New Features

* Maximum placement distance for apps has been increased. Users will now be able to reposition apps in a more flexible layout, without having to move closer to the desired placement position. (124564336)
* Volumetric window applications updated with visionOS 2 SDK now automatically tilt to face the user when user repositions a volume upwards. This will allow users to interact with the volumetric window content while in a reclined position. Developers can opt out of this new default behavior for volumetric windows whose content is meant to be aligned with gravity. `volumeWorldAlignment` scene modifier can be used to control this behavior. Volumetric window applications not updated with visionOS 2 SDK will continue to get the existing default gravity alignment behavior from visionOS 1. (124620395)

### App Store - New Features

* On-demand resources limits were increased for iOS 18, iPadOS 18, tvOS 18 and visionOS 2. See On-demand resources size limits for more information. (122163236)

### Home View - New Features

* Application icons can now be re-arranged by long-pinching on any icon to enter an "edit" mode. (81856035)
* Environment icons are now rendered in stereo when expanded. (100035298)
* Environments can now be offloaded from the Home View by long pressing an environment icon to enter editing mode and tapping the remove button for an environment. Offloaded environments remain visible in the Home View, and users can tap them to re-download them later. (119642769)

### Resolved Issues

* **iCloud Drive**: Fixed: Frequently changed files syncing over iCloud Drive. In beta 3, when a user signs into an iCloud account, iCloud Drive might seem to be enabled in the Settings UI but is not enabled on Files, and therefore cannot be used. (130783277)
* **ImmersiveSpace**: Fixed: immersionStyle can now transition directly from .mixed to .progressive if the app disables animations on the surrounding transaction. (118408995)
* **Keyboard**: Fixed: Keyboard does not automatically switch back to the default non-English language in a new input session if it was previously used in an English-only text field. (126062098)

## SwiftUI - Toolbar Content

The SwiftUI toolbar(content:) modifier allows you to add toolbar items to views. This is particularly useful for navigation bars, tab bars, and other UI chrome elements. The toolbar content can be customized based on the platform and context where it's displayed.

## Liquid Glass Design System

### Introduction to Liquid Glass

Apple's Liquid Glass represents the most significant evolution in Apple's software design language. It introduces a flexible, dynamic layer to apps and system experiences across Apple's ecosystem of products. Liquid Glass is a new digital meta-material that dynamically bends and shapes light, behaving organically like a lightweight liquid while responding to both touch interactions and the dynamism of modern apps.

### Core Design Principles

**"At Apple, we've always believed in the deep integration of hardware and software that makes interacting with technology intuitive, beautiful, and delightful. This is our broadest software design update ever. Meticulously crafted by rethinking the fundamental elements that make up our software, the new design features an entirely new material called Liquid Glass. It combines the optical qualities of glass with a fluidity only Apple can achieve, as it transforms depending on your content or context."** - Alan Dye, VP of Human Interface Design

#### Material Properties

- **Translucent**: Behaves like glass in the real world
- **Adaptive**: Color informed by surrounding content and intelligently adapts between light and dark environments
- **Dynamic**: Uses real-time rendering and dynamically reacts to movement with specular highlights
- **Fluid**: Responds to interaction by instantly flexing and energizing with light

### Visual and Interactive Properties

#### Lensing Effects
Liquid Glass uses lensing to provide visual separation and communicate layering while letting content shine through. Unlike previous materials that scattered light, Liquid Glass dynamically bends, shapes, and concentrates light in real-time. This provides definition against background content while maintaining visual grounding in natural world experiences.

#### Motion and Fluidity
The motion and visual appearance of Liquid Glass were designed as one unified system. It references the smooth, responsive, and effortless motion of liquids that we intuitively understand. Key characteristics include:

- **Instant responsiveness**: Responds to interaction by flexing and energizing with light
- **Gel-like flexibility**: Communicates transient and malleable nature
- **Dynamic morphing**: Shapes shift fluidly between app contexts
- **Temporary elevation**: Elements can lift into Liquid Glass on interaction

#### Multi-Layer Structure
Liquid Glass is composed of sophisticated layers working together:

1. **Highlights Layer**: Responds to environmental lighting and device motion
2. **Shadows Layer**: Adapts opacity based on content behind for optimal separation
3. **Interactive Glow**: Material illuminates from within as feedback to touch
4. **Adaptive Layers**: Multiple layers adapt together to maintain UI hierarchy

### Adaptive Behavior

#### Size-Based Adaptation
- **Small elements** (nav bars, tab bars): Constantly adapt appearance and flip between light/dark
- **Large elements** (menus, sidebars): Adapt based on context but don't flip light/dark to avoid distraction
- **Material thickness**: Larger glass elements simulate thicker, more substantial material with deeper shadows and more pronounced lensing

#### Content-Aware Adaptation
- Dynamic range shifts to ensure legibility while maximizing content visibility
- Shadows become more prominent when text scrolls underneath
- Independent light/dark switching allows perfect integration in any context
- Ambient light from colorful content can subtly spill onto glass surfaces

#### Platform Consistency
Liquid Glass creates a unified design language across all Apple platforms:
- **iOS/iPadOS**: Tab bars shrink during scroll, expand when scrolling back up
- **macOS**: Updated sidebars with content refraction and reflection
- **Universal**: Controls nest perfectly into rounded corners maintaining concentricity

### Liquid Glass Variants

#### Regular Variant
- **Most versatile** - use for majority of cases
- **Adaptive behaviors**: Full visual and adaptive effects
- **Universal compatibility**: Works in any size, over any content
- **Automatic legibility**: Provides readability regardless of context

#### Clear Variant
- **Media-rich content**: Allows content richness to interact with glass
- **Permanently transparent**: More transparent than Regular variant
- **Requires dimming layer**: Needs content dimming for symbol/label legibility
- **Specific use cases**: Only when over media-rich content that won't be negatively affected by dimming

### Implementation Guidelines

#### When to Use Liquid Glass
- **Navigation layer**: Reserve for navigation that floats above content
- **Controls and toolbars**: Buttons, switches, sliders, media controls
- **System experiences**: Lock Screen, Home Screen, notifications, Control Center

#### When NOT to Use Liquid Glass
- **Content layer**: Avoid applying to main content (like table views)
- **Glass on glass**: Never stack Liquid Glass elements on top of each other
- **Over-application**: Don't tint every element - use selectively for primary actions

#### Legibility Considerations
- **Automatic adaptation**: Small elements flip light/dark based on background
- **Contrast optimization**: Symbols and glyphs mirror glass behavior for maximum contrast
- **Custom tinting**: Use selectively for distinct functional purposes
- **Content separation**: Maintain separation between content and glass in steady states

### Accessibility Features

Liquid Glass includes automatic accessibility modifiers:

- **Reduced Transparency**: Makes glass frostier, obscures more background content
- **Increased Contrast**: Elements become predominantly black/white with contrasting borders
- **Reduced Motion**: Decreases effect intensity and disables elastic properties

### Scroll Edge Effects

Work in concert with Liquid Glass to maintain separation between UI and content layers:
- **Adaptive fading**: Content gradually dissolves as it scrolls under glass elements
- **Smart switching**: Effect intelligently switches between fade and dim based on content
- **Hard style**: Uniform effect for pinned accessory views requiring extra separation

### Technical Implementation

#### SwiftUI Integration
```swift
// Basic Liquid Glass application
.glassEffect()

// Advanced usage with variants
.material(.ultraThin) // For Regular variant
.material(.clear) // For Clear variant with proper dimming
```

#### Design Resources
- **Icon Composer**: Creates Liquid Glass icons across platforms
- **Official templates**: Available for Figma, Sketch, and Keynote
- **SF Symbols**: Over 6,900 icons optimized for Liquid Glass
- **Typography**: San Francisco typeface with dynamic scaling for Liquid Glass integration

### Evolution and Context

Liquid Glass builds on Apple's design evolution:
- **2007**: Skeuomorphic Design (mimicking real-world objects)
- **2013**: Flat Design (minimalist, direct visual language)
- **2025**: Liquid Glass Design (translucency, blur, fluid motion with natural interface experience)

The system leverages learnings from Mac OS X Aqua, iOS 7 real-time blurs, iPhone X fluidity, Dynamic Island flexibility, and visionOS immersive interfaces to create this comprehensive new material system.

---

*This documentation is provided for reference during SocialFusion development and should be considered when implementing features that may benefit from these Apple technologies and APIs.* 