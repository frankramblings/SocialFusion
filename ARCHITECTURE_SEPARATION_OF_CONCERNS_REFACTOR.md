# Architecture Separation of Concerns Refactor

## 🎯 **Current Problems**

### 1. **UI Components Contain Business Logic**
- `Post+ContentView.swift` contains complex link categorization logic
- View components are making service calls and data processing decisions
- Link preview logic is scattered across multiple UI files

### 2. **Service Layer Doing UI Work**
- `BlueskyService.swift` manipulates content for display purposes
- Services are making decisions about what to show/hide in UI
- Content processing mixed with API data conversion

### 3. **Inconsistent Responsibility Distribution**
- Link detection logic in utilities but also duplicated in views
- URL handling spread across multiple layers
- No clear data flow for content processing

## 🏗️ **Proposed New Architecture**

### **Layer 1: Service Layer (API & Data)**
**Responsibility**: Pure API communication and raw data conversion
**Should NOT**: Make UI decisions, manipulate content for display

```
Services/
├── BlueskyAPIClient.swift       # Pure API calls
├── MastodonAPIClient.swift      # Pure API calls
├── BlueskyService.swift         # Data conversion only
└── MastodonService.swift        # Data conversion only
```

### **Layer 2: Domain Layer (Business Logic)**
**Responsibility**: Content processing, link categorization, business rules
**Should**: Process raw data into display-ready models

```
Domain/
├── ContentProcessor.swift       # Content processing & URL handling
├── LinkCategorizer.swift        # Categorize links (social, youtube, regular)
├── PostContentAnalyzer.swift    # Analyze post content for display decisions
└── AttachmentExtractor.swift    # Extract media from platform-specific data
```

### **Layer 3: Presentation Layer (ViewModels)**
**Responsibility**: Prepare data for UI, handle UI state
**Should**: Bridge between domain and UI layers

```
ViewModels/
├── PostDisplayModel.swift       # UI-ready post data
├── PostContentViewModel.swift   # Content display logic
└── LinkPreviewViewModel.swift   # Link preview state management
```

### **Layer 4: UI Layer (Views)**
**Responsibility**: Pure UI rendering and user interaction
**Should NOT**: Contain business logic or make data processing decisions

```
Views/
├── PostCardView.swift           # Pure UI rendering
├── PostContentView.swift        # Display formatted content
└── LinkPreviewView.swift        # Display link previews
```

## 🔧 **Specific Refactoring Steps**

### **Step 1: Create ContentProcessor**

Move content processing logic from `BlueskyService` to a dedicated processor:

```swift
// Domain/ContentProcessor.swift
class ContentProcessor {
    static let shared = ContentProcessor()
    
    func processBlueskyContent(_ post: BlueskyPost) -> ProcessedContent {
        // Move URL extraction and content manipulation here
        // Return structured data, not UI-ready strings
    }
    
    func processMastodonContent(_ post: MastodonPost) -> ProcessedContent {
        // Handle Mastodon-specific content processing
    }
}

struct ProcessedContent {
    let displayText: String
    let extractedLinks: [URL]
    let externalEmbeds: [ExternalEmbed]
    let attachments: [ProcessedAttachment]
    let contentType: ContentType
}
```

### **Step 2: Create LinkCategorizer**

Move link categorization from UI to domain layer:

```swift
// Domain/LinkCategorizer.swift
class LinkCategorizer {
    static let shared = LinkCategorizer()
    
    func categorizeLinks(_ links: [URL]) -> CategorizedLinks {
        return CategorizedLinks(
            socialMediaLinks: links.filter { URLService.shared.isSocialMediaPostURL($0) },
            youtubeLinks: links.filter { URLService.shared.isYouTubeURL($0) },
            regularLinks: links.filter { /* regular link logic */ }
        )
    }
}

struct CategorizedLinks {
    let socialMediaLinks: [URL]
    let youtubeLinks: [URL] 
    let regularLinks: [URL]
    
    var primaryYouTubeLink: URL? { youtubeLinks.first }
    var previewableLinks: [URL] { Array(regularLinks.prefix(2)) }
}
```

### **Step 3: Create PostDisplayModel**

Replace direct Post usage in UI with a presentation model:

```swift
// ViewModels/PostDisplayModel.swift
struct PostDisplayModel {
    let post: Post
    let processedContent: ProcessedContent
    let categorizedLinks: CategorizedLinks
    let displayConfiguration: PostDisplayConfiguration
    
    // UI-ready computed properties
    var shouldShowLinkPreviews: Bool {
        !categorizedLinks.previewableLinks.isEmpty
    }
    
    var shouldShowYouTubePlayer: Bool {
        categorizedLinks.primaryYouTubeLink != nil
    }
    
    var shouldShowQuotePost: Bool {
        !categorizedLinks.socialMediaLinks.isEmpty || post.quotedPost != nil
    }
}
```

### **Step 4: Refactor PostCardView**

Make PostCardView purely presentational:

```swift
// Views/Components/PostCardView.swift
struct PostCardView: View {
    let displayModel: PostDisplayModel
    let actions: PostActions
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Author info
            PostAuthorView(displayModel: displayModel)
            
            // Content (no business logic here)
            PostContentView(displayModel: displayModel)
            
            // Media/Links based on display model decisions
            if displayModel.shouldShowYouTubePlayer {
                YouTubePlayerView(url: displayModel.categorizedLinks.primaryYouTubeLink!)
            }
            
            if displayModel.shouldShowLinkPreviews {
                LinkPreviewsView(links: displayModel.categorizedLinks.previewableLinks)
            }
            
            if displayModel.shouldShowQuotePost {
                QuotePostView(displayModel: displayModel)
            }
            
            // Actions
            PostActionBar(actions: actions)
        }
    }
}
```

### **Step 5: Clean Up Service Layer**

Make services purely focused on API communication:

```swift
// Services/BlueskyService.swift
class BlueskyService {
    func fetchTimeline(account: SocialAccount) async throws -> [BlueskyPost] {
        // Pure API call - return raw BlueskyPost objects
    }
    
    func convertToPost(_ blueskyPost: BlueskyPost) -> Post {
        // Simple conversion - no content manipulation
        // Delegate to ContentProcessor for complex processing
        let processedContent = ContentProcessor.shared.processBlueskyContent(blueskyPost)
        return Post(/* basic data only */)
    }
}
```

## 📊 **Benefits of This Architecture**

### **1. Clear Separation**
- **Services**: Only handle API communication
- **Domain**: All business logic and content processing  
- **ViewModels**: Bridge data for UI consumption
- **Views**: Pure UI rendering

### **2. Testability**
- Each layer can be unit tested independently
- Business logic separated from UI makes testing easier
- Mock services don't need to handle UI concerns

### **3. Maintainability**
- Changes to content processing logic in one place
- UI changes don't affect business logic
- Platform-specific logic clearly separated

### **4. Reusability**
- ContentProcessor can be used across different UI contexts
- LinkCategorizer logic shared between timeline and detail views
- Display models can be reused in different view types

## 🚀 **Implementation Priority**

### **Phase 1: Domain Layer**
1. Create `ContentProcessor` and move content manipulation from services
2. Create `LinkCategorizer` and move link logic from UI
3. Create `AttachmentExtractor` for media processing

### **Phase 2: Presentation Layer**  
1. Create `PostDisplayModel` and related view models
2. Update existing ViewModels to use domain layer

### **Phase 3: Refactor UI**
1. Update `PostCardView` to use display models
2. Simplify `Post+ContentView` to be purely presentational
3. Remove business logic from all UI components

### **Phase 4: Clean Services**
1. Remove content manipulation from `BlueskyService`
2. Remove UI-related logic from `MastodonService`
3. Make services purely focused on API communication

This refactoring will solve the duplication issues, missing images, and create a much more maintainable architecture where each layer has clear responsibilities. 