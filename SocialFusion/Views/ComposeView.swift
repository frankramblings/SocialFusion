import Combine
import PhotosUI
import SwiftUI
import UIKit

/// A single post within a thread
public struct ThreadPost: Identifiable {
    public let id = UUID()
    public var text: String = ""
    public var images: [UIImage] = []
    public var imageAltTexts: [String] = []
    public var pollOptions: [String] = []
    public var showPoll: Bool = false
    public var cwEnabled: Bool = false
    public var cwText: String = ""
    public var attachmentSensitiveFlags: [Bool] = []

    /// Computed property for draft sensitive flag
    public var draftSensitive: Bool {
        return cwEnabled || attachmentSensitiveFlags.contains(true)
    }
}

/// A view that shows context for what post is being replied to
struct ReplyContextHeader: View {
    let post: Post
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var navigationEnvironment: PostNavigationEnvironment

    private var platformColor: Color {
        switch post.platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // "Replying to" indicator
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.up.left")
                    .font(.caption)
                    .foregroundColor(platformColor)

                Text("Replying to")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("@\(post.authorUsername)")
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(platformColor)

                Spacer()

                // Platform indicator
                Image(post.platform.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)
                    .foregroundColor(platformColor)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            // Original post preview
            VStack(alignment: .leading, spacing: 8) {
                // Author info
                HStack(spacing: 8) {
                    Button(action: {
                        navigationEnvironment.navigateToUser(from: post)
                    }) {
                        let stableImageURL = URL(string: post.authorProfilePictureURL)
                        CachedAsyncImage(url: stableImageURL) { image in
                            image
                                .resizable()
                                .scaledToFill()
                        } placeholder: {
                            Circle()
                                .fill(Color.gray.opacity(0.3))
                                .overlay(
                                    ProgressView()
                                        .scaleEffect(0.6)
                                )
                        }
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                    }
                    .buttonStyle(PlainButtonStyle())

                    VStack(alignment: .leading, spacing: 2) {
                        Button(action: {
                            navigationEnvironment.navigateToUser(from: post)
                        }) {
                            EmojiDisplayNameText(
                                post.authorName,
                                emojiMap: post.authorEmojiMap,
                                font: .subheadline,
                                fontWeight: .semibold,
                                foregroundColor: .primary,
                                lineLimit: 1
                            )
                        }
                        .buttonStyle(PlainButtonStyle())

                        Button(action: {
                            navigationEnvironment.navigateToUser(from: post)
                        }) {
                            Text("@\(post.authorUsername)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }

                    Spacer()
                }

                // Post content (truncated)
                Text(post.content)
                    .font(.subheadline)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(
                        colorScheme == .dark
                            ? Color(UIColor.tertiarySystemBackground)
                            : Color(UIColor.secondarySystemBackground)
                    )
            )
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
        .background(Color(UIColor.systemBackground))
        .overlay(
            Divider(),
            alignment: .bottom
        )
    }
}

/// A UIViewRepresentable wrapper for UITextView with better focus control and autocomplete support
struct FocusableTextEditor: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let shouldAutoFocus: Bool
    let onFocusChange: (Bool) -> Void
    var onAutocompleteToken: ((AutocompleteToken?) -> Void)? = nil  // Callback for autocomplete token detection
    var documentRevision: Int = 0  // Current document revision for stale-result rejection
    var activeDestinations: [String] = []  // Active destinations for autocomplete scope
    var onUndoRedo: ((String, [TextEntity]) -> Void)? = nil  // Callback for undo/redo to sync entity state
    var onTextEdit: ((NSRange, String) -> Void)? = nil  // Callback for text edits to apply to composerTextModel
    var onPasteDetected: ((String, NSRange) -> [TextEntity])? = nil  // Callback for paste detection to create entities

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
        context.coordinator.setTextView(textView)
        textView.font = UIFont.preferredFont(forTextStyle: .body)
        textView.backgroundColor = UIColor.systemBackground
        textView.textColor = UIColor.label
        textView.layer.cornerRadius = 8
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)

        // Set placeholder if text is empty
        if text.isEmpty {
            textView.text = placeholder
            textView.textColor = UIColor.placeholderText
        } else {
            textView.text = text
            textView.textColor = UIColor.label
        }

        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        // Thread-safe check to prevent crashes
        guard !Task.isCancelled else { return }

        // Update text if it's different and not showing placeholder
        // Only update if the text actually changed to avoid unnecessary updates
        guard uiView.text != text && uiView.textColor != UIColor.placeholderText else { return }

        // CRITICAL: Prevent updates during active user typing
        // When the text view is first responder, it is the source of truth for text content
        // Only allow programmatic updates (like autocomplete) when editing
        if uiView.isFirstResponder {
            let oldLength = (uiView.text ?? "").utf16.count
            let newLength = text.utf16.count
            let lengthDiff = abs(newLength - oldLength)

            // Skip small changes during active editing - these are user typing
            // Only allow larger changes (programmatic updates like autocomplete)
            if lengthDiff <= 2 {
                return
            }
        }

        // CRITICAL: Prevent re-entrant loops during user typing
        // Skip updates during IME composition (marked text) UNLESS it's a programmatic update
        // Programmatic updates (like autocomplete) typically change text significantly, so we allow them
        if uiView.markedTextRange != nil {
            // Check if this is a programmatic update (significant text change, like autocomplete)
            let oldLength = (uiView.text ?? "").utf16.count
            let newLength = text.utf16.count
            let lengthDiff = abs(newLength - oldLength)

            // If the change is small (1-2 characters), it's likely user typing - skip to prevent loop
            // If the change is larger, it's likely programmatic (autocomplete) - allow it
            if lengthDiff <= 2 {
                return
            }
            // For larger changes (autocomplete), clear marked text and proceed
            uiView.unmarkText()
        }

        // Preserve selection and marked text state BEFORE updating text
        let selectedRange = uiView.selectedRange
        let oldText = uiView.text ?? ""
        let oldLength = oldText.utf16.count
        let newLength = text.utf16.count

        uiView.text = text

        // Determine cursor position after update
        // For autocomplete (significant replacement), place cursor after inserted text
        // For regular updates, preserve selection if valid
        if abs(newLength - oldLength) > 2 {
            // Significant change (likely autocomplete) - place cursor at end of new text
            uiView.selectedRange = NSRange(location: text.utf16.count, length: 0)
        } else if selectedRange.location <= text.utf16.count {
            // Small change - preserve selection if still valid
            let clampedLocation = min(selectedRange.location, text.utf16.count)
            let clampedLength = min(selectedRange.length, text.utf16.count - clampedLocation)
            uiView.selectedRange = NSRange(location: clampedLocation, length: clampedLength)
        } else {
            // Selection out of bounds - place at end
            uiView.selectedRange = NSRange(location: text.utf16.count, length: 0)
        }

        // Handle auto-focus with proper safety checks
        if shouldAutoFocus && !uiView.isFirstResponder {
            // Check if the view is still in the view hierarchy
            guard uiView.window != nil else { return }

            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 300_000_000)  // 0.3 seconds
                // Double-check the view is still valid before focusing
                guard !Task.isCancelled,
                    uiView.window != nil,
                    !uiView.isFirstResponder
                else { return }
                uiView.becomeFirstResponder()
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, UITextViewDelegate {
        var parent: FocusableTextEditor?
        private var isUpdating = false
        private var lastToken: AutocompleteToken?
        weak var textView: UITextView?
        private var lastKnownText: String = ""
        private var lastKnownEntities: [TextEntity] = []
        private var previousText: String = ""  // Track previous text for edit range computation
        private var pendingPasteEntities: [TextEntity] = []  // Entities from paste detection
        private var pendingPasteRange: NSRange?  // Range where paste occurred

        init(_ parent: FocusableTextEditor) {
            self.parent = parent
            super.init()
        }

        deinit {
            parent = nil
        }

        func setTextView(_ textView: UITextView) {
            self.textView = textView
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard let parent = parent, !isUpdating else { return }
            isUpdating = true

            if textView.textColor == UIColor.placeholderText {
                textView.text = ""
                textView.textColor = UIColor.label
            }

            // Initialize previous text tracking
            previousText = textView.text ?? ""

            parent.onFocusChange(true)

            isUpdating = false
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            guard let parent = parent, !isUpdating else { return }
            isUpdating = true

            if textView.text.isEmpty {
                textView.text = parent.placeholder
                textView.textColor = UIColor.placeholderText
            }
            parent.onFocusChange(false)

            // Dismiss autocomplete when editing ends
            parent.onAutocompleteToken?(nil)

            isUpdating = false
        }

        func textView(
            _ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String
        ) -> Bool {
            // This is called BEFORE the text changes, giving us the exact edit range
            // We'll apply the edit to composerTextModel here via the parent callback
            guard let parent = parent, !isUpdating else { return true }

            // Detect paste events: large text replacement or check pasteboard
            let isPaste =
                text.count > 10
                || (range.length == 0 && text.count > 0 && UIPasteboard.general.hasStrings)

            if isPaste, let onPasteDetected = parent.onPasteDetected {
                // Parse pasted text for URLs and handles, create entities
                let entities = onPasteDetected(text, range)

                // Store entities to be inserted after text change
                // We'll handle this in textViewDidChange since we need the new text ranges
                pendingPasteEntities = entities
                pendingPasteRange = range
            } else {
                pendingPasteEntities = []
                pendingPasteRange = nil
            }

            // Notify parent to apply edit to composerTextModel
            // The parent will call applyEdit() on the model
            parent.onTextEdit?(range, text)

            // Schedule autocomplete check after text change is applied
            // This ensures we detect triggers like "@" or "#" immediately after typing
            // Note: textViewDidChange will also check, but this provides immediate feedback
            if text.count == 1 && ["@", "#", ":"].contains(text) {
                // Use async dispatch with a small delay to ensure UIKit has applied the change
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    [weak self, weak textView] in
                    guard let self = self, let textView = textView else { return }
                    self.checkForAutocompleteTrigger(textView: textView)
                }
            }

            // Allow the text change to proceed
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let parent = parent,
                !isUpdating
            else { return }

            // Clear placeholder if user starts typing
            if textView.textColor == UIColor.placeholderText && !(textView.text ?? "").isEmpty {
                textView.textColor = UIColor.label
            }

            isUpdating = true
            defer { isUpdating = false }

            let newText = textView.text ?? ""

            // Update previousText tracking
            // Note: We don't call onTextEdit here because shouldChangeTextIn already handled user input
            // This method is only for syncing the binding and handling undo/redo/programmatic changes
            if newText != previousText {
                previousText = newText
            }

            // Handle paste entities if we detected a paste
            if let pasteRange = pendingPasteRange, !pendingPasteEntities.isEmpty {
                // Adjust entity ranges to account for the paste location
                // The paste happened at pasteRange.location in the OLD text
                // Entities have ranges relative to the PASTED text (0-based)
                // We need to adjust them to be relative to the NEW text at pasteRange.location
                var adjustedEntities: [TextEntity] = []

                for var entity in pendingPasteEntities {
                    // Adjust range: paste location + entity's position in pasted text
                    entity.range = NSRange(
                        location: pasteRange.location + entity.range.location,
                        length: entity.range.length
                    )
                    adjustedEntities.append(entity)
                }

                // Notify parent to add these entities
                // Use onUndoRedo callback which will merge entities
                if let onUndoRedo = parent.onUndoRedo {
                    // Pass new text and entities to merge
                    onUndoRedo(newText, adjustedEntities)
                }

                // Clear pending paste
                pendingPasteEntities = []
                pendingPasteRange = nil
            }

            // Check if this change was from undo/redo (text changed but we didn't trigger it)
            // Sync entity state on any text change (including undo/redo)
            if newText != lastKnownText {
                // Notify parent to sync entity state (may be undo/redo)
                parent.onUndoRedo?(newText, [])
                lastKnownText = newText
            }

            // CRITICAL: Sync binding with text view's text (source of truth)
            // Only update if different to prevent re-entrant update loops
            // The model should already be updated via onTextEdit from shouldChangeTextIn,
            // but we sync the binding here after UIKit has applied the change
            if parent.text != newText {
                parent.text = newText
            }

            // Check for autocomplete triggers AFTER text is synced
            // This ensures the text view has the latest text and caret position is correct
            checkForAutocompleteTrigger(textView: textView)
        }

        /// Compute edit range by comparing old and new text
        private func computeEditRange(oldText: String, newText: String) -> NSRange {
            let oldNS = oldText as NSString
            let newNS = newText as NSString

            // Find common prefix
            var prefixLength = 0
            let minLength = min(oldNS.length, newNS.length)
            while prefixLength < minLength
                && oldNS.character(at: prefixLength) == newNS.character(at: prefixLength)
            {
                prefixLength += 1
            }

            // Find common suffix
            var suffixLength = 0
            while suffixLength < minLength - prefixLength
                && oldNS.character(at: oldNS.length - suffixLength - 1)
                    == newNS.character(at: newNS.length - suffixLength - 1)
            {
                suffixLength += 1
            }

            // Compute edit range in old text
            let editLocation = prefixLength
            let editLength = oldNS.length - prefixLength - suffixLength

            return NSRange(location: editLocation, length: editLength)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard let parent = parent, !isUpdating else { return }

            // Dismiss autocomplete if caret moved away from token
            if let lastToken = lastToken {
                let selectedRange = textView.selectedRange
                let tokenEnd = lastToken.replaceRange.location + lastToken.replaceRange.length
                if selectedRange.location != tokenEnd {
                    // Caret moved away from token end - dismiss
                    self.lastToken = nil
                    parent.onAutocompleteToken?(nil)
                }
            }

            // Check for autocomplete trigger after selection change (IME composition commit)
            checkForAutocompleteTrigger(textView: textView)
        }

        /// Check for autocomplete triggers (@/#/:)
        private func checkForAutocompleteTrigger(textView: UITextView) {
            guard let parent = parent else { return }

            let selectedRange = textView.selectedRange
            let text = textView.text ?? ""
            let caretLocation = selectedRange.location

            // Check if we just typed a trigger character (@, #, :)
            // For simple trigger characters, allow checking even with marked text
            // (some keyboards may have brief marked text even for ASCII)
            let hasMarkedText = textView.markedTextRange != nil
            if hasMarkedText {
                // Check if caret is at position 1+ and the character before caret is a trigger
                if caretLocation > 0 && caretLocation <= text.utf16.count {
                    let nsString = text as NSString
                    let charBeforeCaret = nsString.substring(
                        with: NSRange(location: caretLocation - 1, length: 1))
                    if !["@", "#", ":"].contains(charBeforeCaret) {
                        // Not a trigger character - dismiss overlay if marked text is active
                        lastToken = nil
                        parent.onAutocompleteToken?(nil)
                        return
                    }
                    // It's a trigger character - continue checking despite marked text
                } else {
                    // Can't determine trigger - dismiss overlay
                    lastToken = nil
                    parent.onAutocompleteToken?(nil)
                    return
                }
            }

            // Check for triggers before caret
            let triggers = ["@", "#", ":"]
            for prefix in triggers {
                let caretRect = getCaretRect(textView: textView, location: caretLocation)
                if let token = TokenExtractor.extractToken(
                    text: text,
                    caretLocation: caretLocation,
                    prefix: prefix,
                    scope: parent.activeDestinations,
                    documentRevision: parent.documentRevision,
                    caretRect: caretRect
                ) {
                    lastToken = token
                    parent.onAutocompleteToken?(token)
                    return
                }
            }

            // No valid token found - dismiss autocomplete
            if lastToken != nil {
                lastToken = nil
                parent.onAutocompleteToken?(nil)
            }
        }

        /// Get caret rectangle for overlay positioning
        private func getCaretRect(textView: UITextView, location: Int) -> CGRect {
            guard
                let position = textView.position(
                    from: textView.beginningOfDocument, offset: location)
            else {
                return .zero
            }
            return textView.caretRect(for: position)
        }
    }
}

/// A modifier to handle keyboard notifications and adjust the UI accordingly
struct KeyboardAdaptive: ViewModifier {
    @State private var keyboardHeight: CGFloat = 0
    @State private var isUpdating = false

    func body(content: Content) -> some View {
        content
            .padding(.bottom, keyboardHeight)
            .onReceive(Publishers.keyboardHeight) { newHeight in
                // Prevent AttributeGraph cycles by using proper async state updates
                guard !isUpdating else { return }
                isUpdating = true

                Task { @MainActor in
                    // Use Task to defer state update outside of view update cycle
                    try? await Task.sleep(nanoseconds: 1_000_000)  // 0.001 seconds
                    keyboardHeight = newHeight
                    isUpdating = false
                }
            }
    }
}

extension Publishers {
    static var keyboardHeight: AnyPublisher<CGFloat, Never> {
        let willShow = NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillShowNotification
        )
        .map { notification -> CGFloat in
            (notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect)?.height
                ?? 0
        }

        let willHide = NotificationCenter.default.publisher(
            for: UIResponder.keyboardWillHideNotification
        )
        .map { _ -> CGFloat in 0 }

        return willShow.merge(with: willHide)
            .eraseToAnyPublisher()
    }
}

extension View {
    func keyboardAdaptive() -> some View {
        modifier(KeyboardAdaptive())
    }
}

/// Represents partial success when posting to multiple platforms
struct PartialSuccessInfo {
    let successful: [SocialPlatform: Post]
    let failed: [SocialPlatform: String]

    var successMessage: String {
        "Posted to \(successful.keys.map { $0.rawValue }.joined(separator: " and "))"
    }
}

struct ComposeAutocompleteServiceKey: Equatable {
    let accountIDs: [String]
    let timelineScope: AutocompleteTimelineScope

    init(accountIDs: [String], timelineScope: AutocompleteTimelineScope) {
        self.accountIDs = accountIDs.sorted()
        self.timelineScope = timelineScope
    }

    static func make(
        accounts: [SocialAccount],
        timelineScope: AutocompleteTimelineScope
    ) -> ComposeAutocompleteServiceKey {
        ComposeAutocompleteServiceKey(
            accountIDs: accounts.map(\.id),
            timelineScope: timelineScope
        )
    }
}

struct ComposeView: View {
    @State private var threadPosts: [ThreadPost] = [ThreadPost()]
    @State private var activePostIndex: Int = 0
    @State private var showImagePicker = false

    @State private var selectedPlatforms: Set<SocialPlatform> = [.mastodon, .bluesky]
    @State private var isPosting = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    @State private var showDraftActionSheet = false
    @State private var showDraftsList = false
    @State private var showAltTextSheet = false
    @State private var postingStatus: String = "Posting..."
    @State private var selectedImageIndexForAltText: Int = 0
    @State private var currentAltText: String = ""
    @State private var selectedAccounts: [SocialPlatform: String] = [:]

    // Error recovery and retry state
    @State private var lastError: Error? = nil
    @State private var isRetrying = false
    @State private var partialSuccessInfo: PartialSuccessInfo? = nil

    @Environment(\.dismiss) private var dismiss

    // Reply and quote context
    let replyingTo: Post?
    let quotingTo: Post?
    @State private var isTextFieldFocused: Bool = false

    // Autocomplete state
    @State private var composerTextModel = ComposerTextModel()
    @State private var currentAutocompleteToken: AutocompleteToken?
    @State private var autocompleteSuggestions: [AutocompleteSuggestion] = []
    @State private var autocompleteService: AutocompleteService?
    @State private var autocompleteServiceKey: ComposeAutocompleteServiceKey?
    @State private var fallbackTimelineContextProvider: UnifiedTimelineContextProvider?
    @State private var isAutocompleteSearching: Bool = false
    @State private var timelineContextProvider: TimelineContextProvider?

    // Conflict detection
    @State private var platformConflicts: [PlatformConflict] = []

    // Link insertion state
    @State private var showLinkInput = false
    @State private var selectedRangeForLink: NSRange? = nil

    init(
        replyingTo: Post? = nil,
        quotingTo: Post? = nil,
        initialText: String? = nil,
        timelineContextProvider: TimelineContextProvider? = nil
    ) {
        self.replyingTo = replyingTo
        self.quotingTo = quotingTo
        // Initialize with the default visibility from user preferences
        _selectedVisibility = State(
            initialValue: UserDefaults.standard.integer(forKey: "defaultPostVisibility"))

        // For replies or quotes, filter platforms to match the original post
        if let post = replyingTo ?? quotingTo {
            _selectedPlatforms = State(initialValue: [post.platform])
        }

        // Pre-fill text from deep link or Shortcuts
        if let initialText = initialText, !initialText.isEmpty {
            var firstPost = ThreadPost()
            firstPost.text = initialText
            _threadPosts = State(initialValue: [firstPost])
        }

        // Store timeline context provider for autocomplete
        _timelineContextProvider = State(initialValue: timelineContextProvider)
    }

    // Add SocialServiceManager for actual posting
    @EnvironmentObject private var socialServiceManager: SocialServiceManager
    @EnvironmentObject private var draftStore: DraftStore
    @StateObject private var navigationEnvironment = PostNavigationEnvironment()

    @AppStorage("defaultPostVisibility") private var defaultPostVisibility = 0  // 0: Public, 1: Unlisted, 2: Followers Only

    private var postVisibilityOptions = ["Public", "Unlisted", "Followers Only", "Direct"]
    @State private var selectedVisibility: Int

    // Character limits
    private let mastodonCharLimit = 500
    private let blueskyCharLimit = 300

    private var currentCharLimit: Int {
        if selectedPlatforms.contains(.mastodon) && selectedPlatforms.contains(.bluesky) {
            return min(mastodonCharLimit, blueskyCharLimit)
        } else if selectedPlatforms.contains(.mastodon) {
            return mastodonCharLimit
        } else {
            return blueskyCharLimit
        }
    }

    private var remainingChars: Int {
        currentCharLimit - threadPosts[activePostIndex].text.count
    }

    private var isOverLimit: Bool {
        remainingChars < 0
    }

    private var overLimitPlatformsString: String {
        var overLimit: [String] = []
        let count = threadPosts[activePostIndex].text.count
        if selectedPlatforms.contains(.mastodon) && count > mastodonCharLimit {
            overLimit.append("Mastodon (\(mastodonCharLimit))")
        }
        if selectedPlatforms.contains(.bluesky) && count > blueskyCharLimit {
            overLimit.append("Bluesky (\(blueskyCharLimit))")
        }
        return overLimit.joined(separator: " and ")
    }

    private var canPost: Bool {
        !threadPosts[activePostIndex].text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isOverLimit
            && !selectedPlatforms.isEmpty && !isPosting && hasAccountsForSelectedPlatforms
    }

    // Check if we have accounts for the selected platforms
    private var hasAccountsForSelectedPlatforms: Bool {
        selectedPlatforms.allSatisfy { selectedAccount(for: $0) != nil }
    }

    // Helper for button text
    private var buttonText: String {
        if !hasAccountsForSelectedPlatforms {
            return "No Accounts"
        } else if isPosting {
            if quotingTo != nil {
                return "Quoting..."
            } else if replyingTo != nil {
                return "Replying..."
            } else {
                return "Posting..."
            }
        } else {
            if quotingTo != nil {
                return "Quote"
            } else if replyingTo != nil {
                return "Reply"
            } else {
                return "Post"
            }
        }
    }

    // Helper for button color
    private var buttonColor: Color {
        if !hasAccountsForSelectedPlatforms {
            return Color.orange
        } else if canPost {
            return replyingTo != nil ? platformColor : Color.blue
        } else {
            return Color.gray.opacity(0.5)
        }
    }

    // Platform color for reply context
    private var platformColor: Color {
        guard let replyingTo = replyingTo else { return .blue }
        switch replyingTo.platform {
        case .mastodon:
            return Color(red: 99 / 255, green: 100 / 255, blue: 255 / 255)  // #6364FF
        case .bluesky:
            return Color(red: 0, green: 133 / 255, blue: 255 / 255)  // #0085FF
        }
    }

    private struct PlatformLimitStatus: Identifiable {
        let id = UUID()
        let platform: SocialPlatform
        let remaining: Int
        let accountLabel: String
        let accountEmojiMap: [String: String]?
        var isOverLimit: Bool { remaining < 0 }
    }

    private var platformLimitStatuses: [PlatformLimitStatus] {
        selectedPlatforms.sorted(by: { $0.rawValue < $1.rawValue }).map { platform in
            let limit = platform == .mastodon ? mastodonCharLimit : blueskyCharLimit
            let remaining = limit - threadPosts[activePostIndex].text.count
            let account = selectedAccount(for: platform)
            let accountLabel =
                account?.displayName
                ?? account?.username
                ?? "Account"
            return PlatformLimitStatus(
                platform: platform,
                remaining: remaining,
                accountLabel: accountLabel,
                accountEmojiMap: account?.displayNameEmojiMap
            )
        }
    }

    // Helper to get missing platforms
    private var missingAccountPlatforms: [SocialPlatform] {
        var missing: [SocialPlatform] = []
        for platform in selectedPlatforms {
            if accounts(for: platform).isEmpty {
                missing.append(platform)
            }
        }
        return missing
    }

    // Placeholder text based on context
    private var placeholderText: String {
        if let replyingTo = replyingTo {
            return "Reply to \(replyingTo.authorName)..."
        }
        return "What's on your mind?"
    }

    @ViewBuilder
    private var replyContextHeader: some View {
        if let replyingTo = replyingTo {
            ReplyContextHeader(post: replyingTo)
                .environmentObject(navigationEnvironment)
        }
    }

    @ViewBuilder
    private var platformSelectionBar: some View {
        if replyingTo == nil {
            HStack(spacing: 16) {
                ForEach(SocialPlatform.allCases, id: \.self) { platform in
                    PlatformToggleButton(
                        platform: platform,
                        isSelected: selectedPlatforms.contains(platform),
                        action: {
                            togglePlatform(platform)
                        }
                    )
                }

                Spacer()

                // Visibility picker
                Menu {
                    Picker("Visibility", selection: $selectedVisibility) {
                        ForEach(0..<postVisibilityOptions.count, id: \.self) { index in
                            Text(postVisibilityOptions[index]).tag(index)
                        }
                    }
                } label: {
                    Image(systemName: "eye")
                        .foregroundColor(.secondary)
                        .padding(8)
                        .background(Color(UIColor.secondarySystemBackground))
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(UIColor.systemBackground))
            .overlay(
                Divider(),
                alignment: .bottom
            )
        }
    }

    @ViewBuilder
    private var accountSelectorBar: some View {
        if !selectedPlatforms.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(
                        Array(selectedPlatforms).sorted(by: { $0.rawValue < $1.rawValue }),
                        id: \.self
                    ) { platform in
                        accountSelector(for: platform)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, replyingTo == nil ? 8 : 12)
            }
        }
    }

    @ViewBuilder
    private var platformConflictBanners: some View {
        if !platformConflicts.isEmpty {
            PlatformConflictBanner(conflicts: platformConflicts) {
                // Show details sheet
                showAlert = true
                alertTitle = "Platform Conflicts"
                alertMessage = platformConflicts.map { $0.message }.joined(separator: "\n")
            }
            .padding(.horizontal)
            .padding(.bottom, 4)
        }
    }

    @ViewBuilder
    private var textEditorSection: some View {
        ZStack(alignment: .topLeading) {
            FocusableTextEditor(
                text: $threadPosts[activePostIndex].text,
                placeholder: placeholderText,
                shouldAutoFocus: true,
                onFocusChange: { isFocused in
                    isTextFieldFocused = isFocused
                },
                onAutocompleteToken: { token in
                    handleAutocompleteToken(token)
                },
                documentRevision: composerTextModel.documentRevision,
                activeDestinations: makeActiveDestinations(),
                onUndoRedo: { newText, newEntities in
                    // Sync entity state when undo/redo occurs
                    // Note: newEntities may be empty if undo/redo didn't preserve entity state
                    // In that case, we'll rebuild entities naturally as user interacts
                    composerTextModel.text = newText
                    if !newEntities.isEmpty {
                        // Merge new entities with existing ones (for paste)
                        var allEntities = composerTextModel.entities
                        for newEntity in newEntities {
                            // Remove any overlapping entities
                            allEntities.removeAll { existingEntity in
                                NSIntersectionRange(existingEntity.range, newEntity.range).length
                                    > 0
                            }
                            allEntities.append(newEntity)
                        }
                        // Sort by location
                        allEntities.sort { $0.range.location < $1.range.location }
                        composerTextModel.entities = allEntities
                    } else {
                        // Clear entities on undo/redo - they'll be rebuilt naturally
                        composerTextModel.entities = []
                    }
                    composerTextModel.documentRevision += 1
                    // Sync text back to thread post
                    threadPosts[activePostIndex].text = newText
                },
                onTextEdit: { range, replacementText in
                    // CRITICAL: Apply edit to composerTextModel to maintain entity ranges
                    // NOTE: Do NOT update threadPosts[activePostIndex].text here - that will be done
                    // in textViewDidChange after UIKit applies the change. Updating it here causes
                    // updateUIView to interfere with the current input, creating a re-entrant loop.
                    composerTextModel.applyEdit(
                        replacementRange: range, replacementText: replacementText)
                    // The binding will be synced in textViewDidChange
                },
                onPasteDetected: { pastedText, range in
                    // Parse pasted text for URLs and @handles, create entities
                    return parsePastedText(pastedText, insertionRange: range)
                }
            )

            // Autocomplete overlay - always show when token is detected
            if let token = currentAutocompleteToken {
                if !autocompleteSuggestions.isEmpty {
                    AutocompleteOverlay(
                        suggestions: autocompleteSuggestions,
                        token: token,
                        onSelect: { suggestion in
                            acceptSuggestion(suggestion, token: token)
                        },
                        onDismiss: {
                            currentAutocompleteToken = nil
                            autocompleteSuggestions = []
                            isAutocompleteSearching = false
                        }
                    )
                    .allowsHitTesting(true)
                    .zIndex(1000)
                } else {
                    // Show loading or empty state - always show when token exists
                    GeometryReader { geometry in
                        Group {
                            if isAutocompleteSearching || autocompleteService?.isSearching == true {
                                // Show loading state while searching
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Searching...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(UIColor.systemBackground))
                                        .shadow(
                                            color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                                )
                                .frame(maxWidth: 200)
                            } else if autocompleteService?.networkError != nil {
                                // Show network error state
                                VStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle")
                                        .foregroundColor(.orange)
                                    Text("Network unavailable")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("Showing recent suggestions only")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding(12)
                                .background(Color(UIColor.secondarySystemBackground))
                                .cornerRadius(8)
                                .frame(maxWidth: 200)
                            } else {
                                // Show empty state - token detected but no suggestions yet
                                // This handles the case immediately after typing @ or #
                                VStack(spacing: 8) {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                    Text("Loading suggestions...")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .padding(12)
                                .background(
                                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                                        .fill(Color(UIColor.systemBackground))
                                        .shadow(
                                            color: Color.black.opacity(0.1), radius: 8, x: 0, y: 4)
                                )
                                .frame(maxWidth: 200)
                            }
                        }
                        .position(
                            x: max(
                                100,
                                min(
                                    geometry.size.width - 100,
                                    max(
                                        50,
                                        token.caretRect.midX > 0
                                            ? token.caretRect.midX : geometry.size.width / 2))),
                            y: min(
                                max(50, token.caretRect.maxY > 0 ? token.caretRect.maxY + 30 : 100),
                                geometry.size.height - 100
                            )
                        )
                        .allowsHitTesting(true)
                        .zIndex(1000)
                    }
                }
            }
        }
        .frame(maxHeight: .infinity)
        .padding(.horizontal, 8)
        .padding(.top, 8)
    }

    @ViewBuilder
    private var threadPaginationSection: some View {
        if threadPosts.count > 1 {
            HStack {
                ForEach(0..<threadPosts.count, id: \.self) { index in
                    Circle()
                        .fill(
                            index == activePostIndex
                                ? platformColor : Color.gray.opacity(0.3)
                        )
                        .frame(width: 8, height: 8)
                        .onTapGesture {
                            activePostIndex = index
                        }
                }

                Spacer()

                Button(action: {
                    threadPosts.remove(at: activePostIndex)
                    activePostIndex = max(0, activePostIndex - 1)
                }) {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var pollCreationSection: some View {
        if threadPosts[activePostIndex].showPoll {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Poll")
                        .font(.headline)
                    Spacer()
                    Button(action: {
                        threadPosts[activePostIndex].showPoll = false
                        threadPosts[activePostIndex].pollOptions = []
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                }

                ForEach(0..<threadPosts[activePostIndex].pollOptions.count, id: \.self) {
                    index in
                    HStack {
                        TextField(
                            "Option \(index + 1)",
                            text: $threadPosts[activePostIndex].pollOptions[index]
                        )
                        .textFieldStyle(RoundedBorderTextFieldStyle())

                        if threadPosts[activePostIndex].pollOptions.count > 2 {
                            Button(action: {
                                threadPosts[activePostIndex].pollOptions.remove(at: index)
                            }) {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                    }
                }

                if threadPosts[activePostIndex].pollOptions.count < 4 {
                    Button(action: {
                        threadPosts[activePostIndex].pollOptions.append("")
                    }) {
                        Label("Add Option", systemImage: "plus.circle")
                            .font(.subheadline)
                    }
                }
            }
            .padding()
            .background(Color(UIColor.secondarySystemBackground))
            .cornerRadius(12)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    @ViewBuilder
    private var selectedImagesPreview: some View {
        if !threadPosts[activePostIndex].images.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(0..<threadPosts[activePostIndex].images.count, id: \.self) {
                        index in
                        ZStack(alignment: .topTrailing) {
                            Image(uiImage: threadPosts[activePostIndex].images[index])
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                                .shadow(
                                    color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

                            Button(action: {
                                threadPosts[activePostIndex].images.remove(at: index)
                                if index < threadPosts[activePostIndex].imageAltTexts.count {
                                    threadPosts[activePostIndex].imageAltTexts.remove(
                                        at: index)
                                }
                            }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 18))
                                    .foregroundColor(.white)
                                    .background(Color.black.opacity(0.6))
                                    .clipShape(Circle())
                            }
                            .padding(6)

                            // Alt Text Button with completion state
                            Button(action: {
                                selectedImageIndexForAltText = index
                                // Ensure array is large enough
                                while threadPosts[activePostIndex].imageAltTexts.count <= index {
                                    threadPosts[activePostIndex].imageAltTexts.append("")
                                }
                                currentAltText = threadPosts[activePostIndex].imageAltTexts[index]
                                showAltTextSheet = true
                            }) {
                                HStack(spacing: 4) {
                                    Image(
                                        systemName: index
                                            < threadPosts[activePostIndex].imageAltTexts.count
                                            && !threadPosts[activePostIndex].imageAltTexts[index]
                                                .isEmpty
                                            ? "checkmark.circle.fill" : "text.bubble"
                                    )
                                    .font(.system(size: 10))
                                    Text("ALT")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 4)
                                .background(
                                    index < threadPosts[activePostIndex].imageAltTexts.count
                                        && !threadPosts[activePostIndex].imageAltTexts[index]
                                            .isEmpty
                                        ? Color.blue : Color.black.opacity(0.6)
                                )
                                .cornerRadius(4)
                            }
                            .padding(6)
                            .frame(
                                maxWidth: .infinity, maxHeight: .infinity,
                                alignment: .bottomLeading)
                        }
                    }
                }
                .padding(.horizontal)
            }
            .frame(height: 120)
            .padding(.vertical, 10)
            .background(Color(UIColor.systemBackground))
            .overlay(
                Divider(),
                alignment: .bottom
            )
        }
    }

    @ViewBuilder
    private var contentWarningEditorSection: some View {
        if threadPosts[activePostIndex].cwEnabled {
            ContentWarningEditor(
                cwEnabled: $threadPosts[activePostIndex].cwEnabled,
                cwText: $threadPosts[activePostIndex].cwText
            )
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var bottomToolbar: some View {
        HStack {
            // Add image button
            Button(action: {
                showImagePicker = true
            }) {
                Image(systemName: "photo")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.7))
                    .clipShape(Circle())
            }

            // CW toggle button
            Button(action: {
                threadPosts[activePostIndex].cwEnabled.toggle()
                if !threadPosts[activePostIndex].cwEnabled {
                    threadPosts[activePostIndex].cwText = ""
                }
            }) {
                Image(
                    systemName: threadPosts[activePostIndex].cwEnabled
                        ? "eye.slash.fill" : "eye.slash"
                )
                .font(.system(size: 20))
                .foregroundColor(threadPosts[activePostIndex].cwEnabled ? .blue : .secondary)
                .padding(8)
                .background(Color(UIColor.secondarySystemBackground).opacity(0.7))
                .clipShape(Circle())
            }
            .contextMenu {
                // Long-press presets
                ForEach(["Spoilers", "Politics", "NSFW", "Violence"], id: \.self) { preset in
                    Button(action: {
                        threadPosts[activePostIndex].cwEnabled = true
                        threadPosts[activePostIndex].cwText = preset
                    }) {
                        Text(preset)
                    }
                }
            }

            // Add post to thread button
            Button(action: {
                let newPost = ThreadPost()
                threadPosts.append(newPost)
                activePostIndex = threadPosts.count - 1
            }) {
                Image(systemName: "plus.circle")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.7))
                    .clipShape(Circle())
            }

            // Add poll button
            Button(action: {
                if !threadPosts[activePostIndex].showPoll {
                    threadPosts[activePostIndex].showPoll = true
                    threadPosts[activePostIndex].pollOptions = ["", ""]
                }
            }) {
                Image(systemName: "chart.bar")
                    .font(.system(size: 20))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Color(UIColor.secondarySystemBackground).opacity(0.7))
                    .clipShape(Circle())
            }
            .disabled(threadPosts[activePostIndex].showPoll)

            Spacer()

            // Character counter with feedback
            HStack(spacing: 4) {
                if isOverLimit {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.red)
                }

                Text("\(remainingChars)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(
                        isOverLimit ? .red : (remainingChars < 50 ? .orange : .secondary)
                    )
            }
            .padding(.horizontal, 8)
            .onTapGesture {
                if isOverLimit {
                    alertTitle = "Character Limit Exceeded"
                    alertMessage =
                        "You are over the character limit for \(overLimitPlatformsString)."
                    showAlert = true
                }
            }

            // Post button - Enhanced with platform color
            Button(action: {
                postContent()
            }) {
                Text(buttonText)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(canPost ? platformColor : Color.gray.opacity(0.3))
            )
            .disabled(!canPost)
            .animation(.easeInOut(duration: 0.2), value: canPost)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(UIColor.systemBackground))
        .overlay(
            Divider(),
            alignment: .top
        )
    }

    var body: some View {
        let lifecycleModifier = makeLifecycleModifier()

        return NavigationStack {
            VStack(spacing: 0) {
                replyContextHeader
                platformSelectionBar
                accountSelectorBar
                platformStatusBar()
                platformConflictBanners

                textEditorSection
                threadPaginationSection
                pollCreationSection
                selectedImagesPreview
                contentWarningEditorSection
                bottomToolbar
            }
            .sheet(isPresented: $showLinkInput) {
                LinkInputDialog(isPresented: $showLinkInput) { url, displayText in
                    insertLinkAtCursor(url: url, displayText: displayText)
                }
            }
            .navigationTitle(replyingTo != nil ? "Reply" : "New Post")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(
                isPresented: Binding(
                    get: { navigationEnvironment.selectedUser != nil },
                    set: { if !$0 { navigationEnvironment.clearNavigation() } }
                )
            ) {
                if let user = navigationEnvironment.selectedUser {
                    UserDetailView(user: user)
                        .environmentObject(socialServiceManager)
                }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        let hasContent = threadPosts.contains { post in
                            !post.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                || !post.images.isEmpty
                        }
                        if hasContent {
                            showDraftActionSheet = true
                        } else {
                            dismiss()
                        }
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    if !draftStore.drafts.isEmpty && replyingTo == nil {
                        Button(action: { showDraftsList = true }) {
                            Image(systemName: "archivebox")
                        }
                    }
                }
            }
            .sheet(isPresented: $showDraftsList) {
                DraftsListView(onSelect: { draft in
                    self.threadPosts = draft.posts.map { draftPost in
                        ThreadPost(
                            text: draftPost.text,
                            images: draftPost.mediaData.compactMap { UIImage(data: $0) }
                        )
                    }
                    if self.threadPosts.isEmpty {
                        self.threadPosts = [ThreadPost()]
                    }
                    self.activePostIndex = 0
                    self.selectedPlatforms = draft.selectedPlatforms
                    hydrateAccountSelection()
                    draftStore.deleteDraft(draft)
                    showDraftsList = false
                })
                .environmentObject(draftStore)
            }
            .confirmationDialog("Drafts", isPresented: $showDraftActionSheet) {
                Button("Save Draft") {
                    draftStore.saveDraft(
                        posts: threadPosts,
                        platforms: selectedPlatforms,
                        replyingToId: replyingTo?.id,
                        selectedAccounts: selectedAccounts
                    )
                    dismiss()
                }
                Button("Delete Post", role: .destructive) {
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("What would you like to do with this post?")
            }
            .onAppear {
                // Initialize composerTextModel with current thread post text
                if composerTextModel.text != threadPosts[activePostIndex].text {
                    composerTextModel.text = threadPosts[activePostIndex].text
                    composerTextModel.entities = []
                    composerTextModel.documentRevision = 0
                }

                // Update thread scope snapshot if replying
                if let replyingTo = replyingTo, let provider = timelineContextProvider {
                    updateThreadSnapshot(for: replyingTo, provider: provider)
                }
            }
            .onChange(of: activePostIndex) { _, newIndex in
                // Sync composerTextModel when switching between thread posts
                if composerTextModel.text != threadPosts[newIndex].text {
                    composerTextModel.text = threadPosts[newIndex].text
                    composerTextModel.entities = []
                    composerTextModel.documentRevision += 1
                }
            }
            .onChange(of: selectedPlatforms) { _, _ in
                // Update platform conflicts when platforms change
                updatePlatformConflicts()
            }
            .modifier(lifecycleModifier)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showImagePicker) {
                PhotoPicker(selectedImages: $threadPosts[activePostIndex].images, maxImages: 4)
            }
            .sheet(isPresented: $showAltTextSheet) {
                NavigationView {
                    VStack {
                        if selectedImageIndexForAltText < threadPosts[activePostIndex].images.count
                        {
                            Image(
                                uiImage: threadPosts[activePostIndex].images[
                                    selectedImageIndexForAltText]
                            )
                            .resizable()
                            .scaledToFit()
                            .frame(height: 200)
                            .cornerRadius(8)
                            .padding()
                        }

                        TextField(
                            "Description for the visually impaired...", text: $currentAltText,
                            axis: .vertical
                        )
                        .lineLimit(3...10)
                        .padding()
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                        .padding(.horizontal)

                        Spacer()
                    }
                    .navigationTitle("Image Description")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .navigationBarLeading) {
                            Button("Cancel") {
                                showAltTextSheet = false
                            }
                        }
                        ToolbarItem(placement: .navigationBarTrailing) {
                            Button("Done") {
                                // Save ALT text back to the post
                                while threadPosts[activePostIndex].imageAltTexts.count <= selectedImageIndexForAltText {
                                    threadPosts[activePostIndex].imageAltTexts.append("")
                                }
                                threadPosts[activePostIndex].imageAltTexts[selectedImageIndexForAltText] = currentAltText
                                showAltTextSheet = false
                            }
                        }
                    }
                }
            }
            .alert(isPresented: $showAlert) {
                if let partial = partialSuccessInfo {
                    // Partial success - allow retry of failed platforms
                    return Alert(
                        title: Text("Partial Success"),
                        message: Text(
                            "\(partial.successMessage)\n\nFailed: \(partial.failed.keys.map { $0.rawValue }.joined(separator: ", "))"
                        ),
                        primaryButton: .default(Text("Retry Failed")) {
                            retryFailedPlatforms()
                        },
                        secondaryButton: .cancel(Text("Dismiss")) {
                            dismiss()
                        }
                    )
                } else {
                    // Complete failure - allow retry
                    return Alert(
                        title: Text(alertTitle),
                        message: Text(alertMessage),
                        primaryButton: .default(Text("Try Again")) {
                            retryPosting()
                        },
                        secondaryButton: .cancel(Text("Dismiss")) {
                            showAlert = false  // Keep compose open
                        }
                    )
                }
            }
            .overlay(
                Group {
                    if isPosting {
                        ZStack {
                            Color.black.opacity(0.4)
                                .edgesIgnoringSafeArea(.all)

                            VStack(spacing: 16) {
                                ProgressView()
                                    .scaleEffect(1.5)

                                Text(postingStatus)
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }
                            .padding(24)
                            .background(Color(UIColor.systemBackground))
                            .cornerRadius(12)
                            .shadow(radius: 10)
                        }
                    }
                }
            )
        }
    }

    private func togglePlatform(_ platform: SocialPlatform) {
        if selectedPlatforms.contains(platform) {
            // Don't allow deselecting the last platform
            if selectedPlatforms.count > 1 {
                selectedPlatforms.remove(platform)
            }
        } else {
            selectedPlatforms.insert(platform)
        }
        hydrateAccountSelection()
    }

    private func accounts(for platform: SocialPlatform) -> [SocialAccount] {
        switch platform {
        case .mastodon:
            return socialServiceManager.mastodonAccounts
        case .bluesky:
            return socialServiceManager.blueskyAccounts
        }
    }

    private func selectedAccount(for platform: SocialPlatform) -> SocialAccount? {
        let platformAccounts = accounts(for: platform)
        if let id = selectedAccounts[platform],
            let match = platformAccounts.first(where: { $0.id == id })
        {
            return match
        }
        return platformAccounts.first
    }

    private func selectedAccountOverrides() -> [SocialPlatform: SocialAccount] {
        var overrides: [SocialPlatform: SocialAccount] = [:]
        for platform in selectedPlatforms {
            if let account = selectedAccount(for: platform) {
                overrides[platform] = account
            }
        }
        return overrides
    }

    private func hydrateAccountSelection() {
        for platform in selectedPlatforms {
            if selectedAccount(for: platform) == nil,
                let account = accounts(for: platform).first
            {
                selectedAccounts[platform] = account.id
            }
        }
    }

    private func normalizedAltTexts(for post: ThreadPost) -> [String] {
        var altTexts = post.imageAltTexts
        if altTexts.count < post.images.count {
            altTexts.append(
                contentsOf: Array(repeating: "", count: post.images.count - altTexts.count))
        }
        return Array(altTexts.prefix(post.images.count))
    }


    @ViewBuilder
    private func platformStatusBar() -> some View {
        if !platformLimitStatuses.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(platformLimitStatuses) { status in
                        HStack(spacing: 8) {
                            Image(status.platform.icon)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 14, height: 14)

                            VStack(alignment: .leading, spacing: 2) {
                                EmojiDisplayNameText(
                                    status.accountLabel,
                                    emojiMap: status.accountEmojiMap,
                                    font: .caption,
                                    fontWeight: .regular,
                                    foregroundColor: .primary,
                                    lineLimit: 1
                                )
                                Text("\(status.remaining) left")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundColor(
                                        status.isOverLimit
                                            ? .red
                                            : (status.remaining < 50 ? .orange : .secondary)
                                    )
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(
                                    status.isOverLimit
                                        ? Color.red.opacity(0.12)
                                        : Color(UIColor.secondarySystemBackground)
                                )
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    status.isOverLimit
                                        ? Color.red.opacity(0.4)
                                        : platformColor.opacity(0.3),
                                    lineWidth: 1
                                )
                        )
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
        }
    }

    @ViewBuilder
    private func accountSelector(for platform: SocialPlatform) -> some View {
        let platformAccounts = accounts(for: platform)
        if platformAccounts.isEmpty {
            EmptyView()
        } else {
            Menu {
                ForEach(platformAccounts, id: \.id) { account in
                    Button {
                        selectedAccounts[platform] = account.id
                    } label: {
                        HStack {
                            EmojiDisplayNameText(
                                account.displayName ?? account.username,
                                emojiMap: account.displayNameEmojiMap,
                                font: .body,
                                fontWeight: .regular,
                                foregroundColor: .primary,
                                lineLimit: 1
                            )
                            if selectedAccounts[platform] == account.id {
                                Spacer()
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(platform.icon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 14, height: 14)

                    if let account = selectedAccount(for: platform) {
                        EmojiDisplayNameText(
                            account.displayName ?? account.username,
                            emojiMap: account.displayNameEmojiMap,
                            font: .subheadline,
                            fontWeight: .medium,
                            foregroundColor: .primary,
                            lineLimit: 1
                        )
                    } else {
                        Text("Select account")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemBackground))
                .clipShape(Capsule())
            }
        }
    }

    private func postContent() {
        guard canPost else {
            // Handle the case where user tries to post without proper accounts
            if !hasAccountsForSelectedPlatforms {
                let missing = missingAccountPlatforms.map { $0.rawValue }.joined(separator: " and ")
                alertTitle = "Missing Accounts"
                alertMessage = "Please add \(missing) account(s) to post to the selected platforms."
                showAlert = true
            }
            return
        }

        isPosting = true
        partialSuccessInfo = nil  // Clear any previous partial success info
        if quotingTo != nil {
            postingStatus = "Creating quote..."
        } else {
            postingStatus = replyingTo != nil ? "Sending reply..." : "Posting..."
        }
        HapticEngine.tap.trigger()

        // Convert visibility index to string
        let visibilityString: String
        switch selectedVisibility {
        case 0:
            visibilityString = "public"
        case 1:
            visibilityString = "unlisted"
        case 2:
            visibilityString = "private"
        default:
            visibilityString = "public"
        }

        Task {
            do {
                // Handle quote posts
                if let quoteTarget = quotingTo {
                    _ = try await socialServiceManager.createQuotePost(
                        content: threadPosts[0].text,
                        quotedPost: quoteTarget,
                        platforms: selectedPlatforms
                    )

                    // Register quote success with PostActionCoordinator
                    if FeatureFlagManager.isEnabled(.postActionsV2) {
                        await MainActor.run {
                            socialServiceManager.postActionCoordinator.registerQuoteSuccess(
                                for: quoteTarget)
                        }
                    }

                    await MainActor.run {
                        isPosting = false
                        dismiss()
                    }
                    return
                }

                var previousPostsByPlatform: [SocialPlatform: Post] = [:]
                var blueskyRootByPlatform: [SocialPlatform: BlueskyStrongRef] = [:]
                if let replyTarget = replyingTo {
                    previousPostsByPlatform[replyTarget.platform] = replyTarget
                    if replyTarget.platform == .bluesky {
                        let cid =
                            replyTarget.cid
                            ?? replyTarget.platformSpecificId.components(separatedBy: "/").last
                            ?? ""
                        blueskyRootByPlatform[.bluesky] = BlueskyStrongRef(
                            uri: replyTarget.platformSpecificId,
                            cid: cid
                        )
                    }
                }

                for (index, threadPost) in threadPosts.enumerated() {
                    await MainActor.run {
                        if threadPosts.count > 1 {
                            postingStatus =
                                replyingTo != nil
                                ? "Reply \(index + 1) of \(threadPosts.count)"
                                : "Post \(index + 1) of \(threadPosts.count)"
                        }
                    }

                    let mediaData: [Data] = threadPost.images.compactMap { image in
                        image.jpegData(compressionQuality: 0.8)
                    }
                    let mediaAltTexts = normalizedAltTexts(for: threadPost)
                    let pollOptions = threadPost.pollOptions.filter { !$0.isEmpty }

                    if previousPostsByPlatform.isEmpty && replyingTo == nil {
                        // Sync composer text model with current text
                        if composerTextModel.text != threadPost.text {
                            composerTextModel.text = threadPost.text
                        }

                        // CRITICAL: Parse entities from text before posting
                        // This ensures manually typed mentions/hashtags/links are converted to entities
                        composerTextModel.parseEntitiesFromText(
                            activeDestinations: makeActiveDestinations())

                        let createdPosts = try await socialServiceManager.createPost(
                            content: threadPost.text,
                            platforms: selectedPlatforms,
                            mediaAttachments: mediaData,
                            mediaAltTexts: mediaAltTexts,
                            pollOptions: pollOptions,
                            pollExpiresIn: 86400,  // 24 hours
                            visibility: visibilityString,
                            accountOverrides: selectedAccountOverrides(),
                            cwText: threadPost.cwText.isEmpty ? nil : threadPost.cwText,
                            cwEnabled: threadPost.cwEnabled,
                            attachmentSensitiveFlags: threadPost.attachmentSensitiveFlags,
                            composerTextModel: composerTextModel
                        )
                        for post in createdPosts {
                            previousPostsByPlatform[post.platform] = post
                            if post.platform == .bluesky, blueskyRootByPlatform[.bluesky] == nil {
                                let cid =
                                    post.cid
                                    ?? post.platformSpecificId.components(separatedBy: "/").last
                                    ?? ""
                                blueskyRootByPlatform[.bluesky] = BlueskyStrongRef(
                                    uri: post.platformSpecificId,
                                    cid: cid
                                )
                            }
                        }
                    } else {
                        var updatedPrevious: [SocialPlatform: Post] = [:]
                        var failedReplies: [SocialPlatform: String] = [:]

                        for (platform, parentPost) in previousPostsByPlatform {
                            guard selectedPlatforms.contains(platform) else { continue }

                            do {
                                // Sync composer text model
                                if composerTextModel.text != threadPost.text {
                                    composerTextModel.text = threadPost.text
                                }

                                // CRITICAL: Parse entities from text before posting
                                // This ensures manually typed mentions/hashtags/links are converted to entities
                                composerTextModel.parseEntitiesFromText(
                                    activeDestinations: makeActiveDestinations())

                                let reply = try await socialServiceManager.replyToPost(
                                    parentPost,
                                    content: threadPost.text,
                                    mediaAttachments: mediaData,
                                    mediaAltTexts: mediaAltTexts,
                                    pollOptions: pollOptions,
                                    pollExpiresIn: 86400,
                                    visibility: visibilityString,
                                    accountOverride: selectedAccount(for: platform),
                                    blueskyRoot: blueskyRootByPlatform[platform],
                                    cwText: threadPost.cwText.isEmpty ? nil : threadPost.cwText,
                                    cwEnabled: threadPost.cwEnabled,
                                    attachmentSensitiveFlags: threadPost.attachmentSensitiveFlags,
                                    composerTextModel: composerTextModel
                                )
                                updatedPrevious[platform] = reply

                                // Register reply success with PostActionCoordinator
                                if FeatureFlagManager.isEnabled(.postActionsV2) {
                                    await MainActor.run {
                                        socialServiceManager.postActionCoordinator
                                            .registerReplySuccess(
                                                for: parentPost)
                                    }
                                }
                            } catch {
                                // Collect failure but don't throw - allow other platforms to succeed
                                failedReplies[platform] = error.localizedDescription
                                print(
                                    "❌ Failed to reply on \(platform.rawValue): \(error.localizedDescription)"
                                )
                            }
                        }

                        // If all platforms failed, throw error
                        if updatedPrevious.isEmpty && !failedReplies.isEmpty {
                            throw ServiceError.postFailed(
                                reason:
                                    "Failed to reply on all platforms: \(failedReplies.values.joined(separator: ", "))"
                            )
                        }

                        // If partial success, note it for later handling
                        if !failedReplies.isEmpty && !updatedPrevious.isEmpty {
                            // Store partial success info for alert
                            await MainActor.run {
                                partialSuccessInfo = PartialSuccessInfo(
                                    successful: updatedPrevious,
                                    failed: failedReplies
                                )
                            }
                        } else {
                            // Complete success - clear any previous partial success info
                            await MainActor.run {
                                partialSuccessInfo = nil
                            }
                        }
                        previousPostsByPlatform = updatedPrevious
                    }
                }

                await MainActor.run {
                    isPosting = false

                    // Check if there was partial success
                    if let partial = partialSuccessInfo {
                        // Partial success - show alert with retry option
                        HapticEngine.warning.trigger()
                        alertTitle = "Partial Success"
                        alertMessage = partial.successMessage
                        showAlert = true
                    } else {
                        // Complete success - dismiss immediately
                        HapticEngine.success.trigger()

                        // Reset the compose view
                        threadPosts = [ThreadPost()]
                        activePostIndex = 0

                        // Reset platform selection to default and rehydrate account picks
                        selectedPlatforms = [.mastodon, .bluesky]
                        selectedAccounts.removeAll()
                        hydrateAccountSelection()

                        // Dismiss the view immediately - no need for success alert
                        // User will see their post appear in the timeline
                        dismiss()
                    }
                }

            } catch {
                await MainActor.run {
                    isPosting = false
                    HapticEngine.error.trigger()
                    alertTitle = "Error"
                    alertMessage =
                        "Failed to \(replyingTo != nil ? "reply" : "post"): \(error.localizedDescription)"
                    showAlert = true
                }

                print("Posting error: \(error)")
            }
        }
    }

    /// Retry posting with the same content and platforms
    private func retryPosting() {
        isRetrying = true
        partialSuccessInfo = nil
        lastError = nil
        postContent()
    }

    /// Retry only the failed platforms from a partial success
    private func retryFailedPlatforms() {
        guard let partial = partialSuccessInfo else { return }

        // Filter selected platforms to only failed ones
        selectedPlatforms = Set(partial.failed.keys)

        // Reset state
        isRetrying = true
        partialSuccessInfo = nil
        lastError = nil

        postContent()
    }

    private var selectedPlatformsString: String {
        selectedPlatforms.map { $0.rawValue }.joined(separator: " and ")
    }

    // MARK: - Text Edit Utilities

    /// Compute edit range by comparing old and new text
    private func computeEditRange(oldText: String, newText: String) -> NSRange {
        let oldNS = oldText as NSString
        let newNS = newText as NSString

        // Find common prefix
        var prefixLength = 0
        let minLength = min(oldNS.length, newNS.length)
        while prefixLength < minLength
            && oldNS.character(at: prefixLength) == newNS.character(at: prefixLength)
        {
            prefixLength += 1
        }

        // Find common suffix
        var suffixLength = 0
        while suffixLength < minLength - prefixLength
            && oldNS.character(at: oldNS.length - suffixLength - 1)
                == newNS.character(at: newNS.length - suffixLength - 1)
        {
            suffixLength += 1
        }

        // Compute edit range in old text
        let editLocation = prefixLength
        let editLength = oldNS.length - prefixLength - suffixLength

        return NSRange(location: editLocation, length: editLength)
    }

    // MARK: - Platform Conflict Detection

    /// Create lifecycle modifier with all required parameters
    private func makeLifecycleModifier() -> ComposeViewLifecycleModifier {
        ComposeViewLifecycleModifier(
            hydrateAccountSelection: hydrateAccountSelection,
            updatePlatformConflicts: updatePlatformConflicts,
            autocompleteService: $autocompleteService,
            socialServiceManager: socialServiceManager,
            selectedPlatforms: selectedPlatforms,
            selectedAccount: selectedAccount(for:),
            canPost: canPost,
            postContent: postContent,
            currentAutocompleteToken: $currentAutocompleteToken,
            autocompleteSuggestions: $autocompleteSuggestions,
            selectedVisibility: $selectedVisibility,
            threadPosts: $threadPosts,
            activePostIndex: activePostIndex,
            toggleCW: toggleCW,
            toggleLabels: toggleLabels,
            insertLink: insertLink
        )
    }

    /// Toggle content warning
    private func toggleCW() {
        threadPosts[activePostIndex].cwEnabled.toggle()
        if !threadPosts[activePostIndex].cwEnabled {
            threadPosts[activePostIndex].cwText = ""
        }
    }

    /// Toggle Bluesky labels (opens picker)
    private func toggleLabels() {
        // Labels picker is already shown conditionally in bottomToolbar
        // This method exists for keyboard shortcut compatibility
        // In a future enhancement, this could open a dedicated labels sheet
    }

    /// Insert link (placeholder for Cmd+K shortcut)
    private func insertLink() {
        // Show link input dialog
        showLinkInput = true
    }

    /// Insert link at current cursor position
    private func insertLinkAtCursor(url: String, displayText: String) {
        // We'll use the current text selection or end of text
        // Note: Getting exact cursor position from UITextView in SwiftUI is tricky.
        // We'll append if no range is captured, or we could improve FocusableTextEditor to track selection.
        
        // For now, let's use the end of the text if we don't have a reliable selection
        let insertionRange = NSRange(location: threadPosts[activePostIndex].text.utf16.count, length: 0)
        
        // Create link entity
        var payloads: [String: EntityPayload] = [:]
        let activeDestinations = makeActiveDestinations()
        for destinationID in activeDestinations {
            let components = destinationID.split(separator: ":")
            guard components.count >= 2,
                  let platformStr = components.first,
                  let platform = SocialPlatform(rawValue: String(platformStr)) else {
                continue
            }
            
            switch platform {
            case .mastodon:
                payloads[destinationID] = EntityPayload(platform: .mastodon, data: ["url": url])
            case .bluesky:
                payloads[destinationID] = EntityPayload(platform: .bluesky, data: ["uri": url])
            }
        }
        
        let entity = TextEntity(
            kind: .link,
            range: NSRange(location: insertionRange.location, length: displayText.utf16.count),
            displayText: displayText,
            payloadByDestination: payloads,
            data: .link(LinkData(url: url, title: displayText))
        )
        
        // Apply to model
        composerTextModel.replace(range: insertionRange, with: displayText, entities: [entity])
        
        // Sync back to thread post
        threadPosts[activePostIndex].text = composerTextModel.text
        composerTextModel.documentRevision += 1
    }

    /// Update platform conflicts based on current state
    private func updatePlatformConflicts() {
        var conflicts: [PlatformConflict] = []

        // Check CW conflicts (Bluesky doesn't support CW)
        if threadPosts[activePostIndex].cwEnabled && selectedPlatforms.contains(.bluesky) {
            conflicts.append(
                PlatformConflict(
                    feature: "Content Warning",
                    platforms: [.bluesky]
                ))
        }

        platformConflicts = conflicts
    }

    // MARK: - Paste Detection

    /// Parse pasted text for URLs and @handles, create entities
    private func parsePastedText(_ text: String, insertionRange: NSRange) -> [TextEntity] {
        var entities: [TextEntity] = []
        let nsString = text as NSString
        let textLength = nsString.length
        let activeDestinations = makeActiveDestinations()

        // Parse URLs: http:// or https://
        let urlPattern = "https?://[A-Za-z0-9./?=_%-]+"
        if let urlRegex = try? NSRegularExpression(pattern: urlPattern, options: []) {
            let matches = urlRegex.matches(
                in: text, options: [], range: NSRange(location: 0, length: textLength))
            for match in matches {
                var range = match.range
                var urlText = nsString.substring(with: range)
                // Clean trailing punctuation
                while let last = urlText.last, ".,!?;:".contains(last) {
                    urlText = String(urlText.dropLast())
                    range = NSRange(location: range.location, length: range.length - 1)
                }

                _ = URL(string: urlText)

                // Create payloads for active destinations
                var payloads: [String: EntityPayload] = [:]
                for destinationID in activeDestinations {
                    let components = destinationID.split(separator: ":")
                    guard components.count >= 2,
                        let platformStr = components.first,
                        let platform = SocialPlatform(rawValue: String(platformStr))
                    else {
                        continue
                    }

                    switch platform {
                    case .mastodon:
                        payloads[destinationID] = EntityPayload(
                            platform: .mastodon,
                            data: ["url": urlText]
                        )
                    case .bluesky:
                        payloads[destinationID] = EntityPayload(
                            platform: .bluesky,
                            data: ["uri": urlText]
                        )
                    }
                }

                let entity = TextEntity(
                    kind: .link,
                    range: range,  // Range relative to pasted text (will be adjusted in Coordinator)
                    displayText: urlText,
                    payloadByDestination: payloads,
                    data: .link(LinkData(url: urlText))
                )
                entities.append(entity)
            }
        }

        // Parse @handles: @username or @username@domain
        let mentionPattern = "@([A-Za-z0-9_]+)(@[A-Za-z0-9_.-]+)?"
        if let mentionRegex = try? NSRegularExpression(pattern: mentionPattern, options: []) {
            let matches = mentionRegex.matches(
                in: text, options: [], range: NSRange(location: 0, length: textLength))
            for match in matches {
                let range = match.range
                let usernameRange = match.range(at: 1)
                let username = nsString.substring(with: usernameRange)
                var domain: String? = nil
                if match.numberOfRanges > 2 && match.range(at: 2).location != NSNotFound {
                    let domainRange = match.range(at: 2)
                    domain = nsString.substring(with: domainRange)
                }

                let displayText = nsString.substring(with: range)
                let acct = domain != nil ? "\(username)\(domain!)" : username

                // Create payloads for active destinations
                var payloads: [String: EntityPayload] = [:]
                for destinationID in activeDestinations {
                    let components = destinationID.split(separator: ":")
                    guard components.count >= 2,
                        let platformStr = components.first,
                        let platform = SocialPlatform(rawValue: String(platformStr))
                    else {
                        continue
                    }

                    switch platform {
                    case .mastodon:
                        payloads[destinationID] = EntityPayload(
                            platform: .mastodon,
                            data: [
                                "acct": acct,
                                "username": username,
                            ]
                        )
                    case .bluesky:
                        // For Bluesky, we'd need DID lookup
                        payloads[destinationID] = EntityPayload(
                            platform: .bluesky,
                            data: [
                                "handle": username,
                                "did": "",  // Will be resolved in background
                            ]
                        )
                        
                        // Trigger background resolution
                        if let account = selectedAccount(for: .bluesky) {
                            Task {
                                do {
                                    let did = try await socialServiceManager.blueskyService.resolveHandle(handle: username, account: account)
                                    await MainActor.run {
                                        self.resolvePastedHandle(username, did: did)
                                    }
                                } catch {
                                    print("⚠️ Failed to resolve pasted handle @\(username): \(error)")
                                }
                            }
                        }
                    }
                }

                let entity = TextEntity(
                    kind: .mention,
                    range: range,  // Range relative to pasted text (will be adjusted in Coordinator)
                    displayText: displayText,
                    payloadByDestination: payloads,
                    data: .mention(
                        MentionData(
                            acct: acct,
                            handle: username
                        ))
                )
                entities.append(entity)
            }
        }

        return entities
    }

    /// Update a previously pasted handle with its resolved DID
    private func resolvePastedHandle(_ handle: String, did: String) {
        // Find entities with this handle and empty DID
        var updated = false
        for (index, entity) in composerTextModel.entities.enumerated() {
            if entity.kind == .mention {
                for (destID, payload) in entity.payloadByDestination {
                    if payload.platform == .bluesky && payload.data["handle"] as? String == handle && (payload.data["did"] as? String ?? "").isEmpty {
                        var newPayload = payload
                        newPayload.data["did"] = did
                        composerTextModel.entities[index].payloadByDestination[destID] = newPayload
                        updated = true
                    }
                }
            }
        }
        
        if updated {
            composerTextModel.documentRevision += 1
            print("✅ Resolved DID for pasted handle @\(handle): \(did)")
        }
    }

    // MARK: - Thread Context Updates

    /// Update thread snapshot with conversation context when replying
    private func updateThreadSnapshot(for post: Post, provider: TimelineContextProvider) {
        // Collect thread posts: the post itself, its parent chain, and any quoted post
        var threadPosts: [Post] = [post]

        // Add parent chain
        var currentParent = post.parent
        while let parent = currentParent {
            threadPosts.append(parent)
            currentParent = parent.parent
        }

        // Add original post if this is a boost
        if let originalPost = post.originalPost {
            threadPosts.append(originalPost)
        }

        // Add quoted post if present
        if let quotedPost = post.quotedPost {
            threadPosts.append(quotedPost)
        }

        // Update snapshot for thread scope
        let threadScope = AutocompleteTimelineScope.thread(post.id)
        provider.updateSnapshot(posts: threadPosts, scope: threadScope)
    }

    // MARK: - Autocomplete Helpers

    /// Make active destinations list for autocomplete scope
    private func makeActiveDestinations() -> [String] {
        var destinations: [String] = []
        for platform in selectedPlatforms {
            if let account = selectedAccount(for: platform) {
                destinations.append(makeDestinationID(platform: platform, accountId: account.id))
            }
        }
        return destinations
    }

    /// Handle autocomplete token detection
    private func handleAutocompleteToken(_ token: AutocompleteToken?) {
        guard let token = token else {
            currentAutocompleteToken = nil
            autocompleteSuggestions = []
            isAutocompleteSearching = false
            autocompleteService?.cancelSearch()
            return
        }

        // Always set token immediately to show overlay
        currentAutocompleteToken = token
        isAutocompleteSearching = true

        // Get current accounts for all selected platforms
        let currentAccounts = selectedPlatforms.compactMap { selectedAccount(for: $0) }
        let timelineScope: AutocompleteTimelineScope = replyingTo != nil ? .thread(replyingTo!.id) : .unified
        ensureAutocompleteService(accounts: currentAccounts, timelineScope: timelineScope)

        Task { @MainActor in
            guard let service = autocompleteService else {
                isAutocompleteSearching = false
                return
            }

            let suggestions = await service.searchRequest(token: token)

            // Only apply if token is still current
            if currentAutocompleteToken?.requestID == token.requestID {
                autocompleteSuggestions = suggestions
                isAutocompleteSearching = false  // Search completed
            } else {
                isAutocompleteSearching = false
            }
        }
    }

    private func resolveTimelineContextProvider() -> TimelineContextProvider {
        if let provider = timelineContextProvider {
            return provider
        }
        if let fallback = fallbackTimelineContextProvider {
            return fallback
        }
        let fallback = UnifiedTimelineContextProvider()
        fallbackTimelineContextProvider = fallback
        return fallback
    }

    private func ensureAutocompleteService(
        accounts: [SocialAccount],
        timelineScope: AutocompleteTimelineScope
    ) {
        let nextKey = ComposeAutocompleteServiceKey.make(
            accounts: accounts,
            timelineScope: timelineScope
        )
        guard autocompleteService == nil || autocompleteServiceKey != nextKey else {
            return
        }

        let contextProvider = resolveTimelineContextProvider()

        var providers: [SuggestionProvider] = []
        providers.append(LocalHistoryProvider(cache: AutocompleteCache.shared))
        providers.append(
            TimelineContextSuggestionProvider(
                contextProvider: contextProvider,
                scope: timelineScope
            ))
        providers.append(
            NetworkSuggestionProvider(
                mastodonService: socialServiceManager.mastodonService,
                blueskyService: socialServiceManager.blueskyService,
                accounts: accounts
            ))

        autocompleteService = AutocompleteService(
            cache: AutocompleteCache.shared,
            mastodonService: socialServiceManager.mastodonService,
            blueskyService: socialServiceManager.blueskyService,
            accounts: accounts,
            suggestionProviders: providers,
            timelineContextProvider: contextProvider,
            timelineScope: timelineScope
        )
        autocompleteServiceKey = nextKey
    }

    /// Accept an autocomplete suggestion
    private func acceptSuggestion(_ suggestion: AutocompleteSuggestion, token: AutocompleteToken) {
        // Build entity from suggestion
        let entity: TextEntity
        switch token.prefix {
        case "@":
            // Create mention entity
            let mentionData: MentionData
            if suggestion.entityPayload.platform == .bluesky {
                mentionData = MentionData(
                    accountId: nil,
                    acct: nil,
                    displayName: suggestion.entityPayload.data["displayName"] as? String,
                    did: suggestion.entityPayload.data["did"] as? String,
                    handle: suggestion.entityPayload.data["handle"] as? String
                )
            } else {
                mentionData = MentionData(
                    accountId: suggestion.entityPayload.data["accountId"] as? String,
                    acct: suggestion.entityPayload.data["acct"] as? String,
                    displayName: suggestion.entityPayload.data["displayName"] as? String,
                    did: nil,
                    handle: nil
                )
            }

            // Build payload by destination (only for active destinations)
            var payloadByDestination: [String: EntityPayload] = [:]
            for destinationID in token.scope {
                payloadByDestination[destinationID] = suggestion.entityPayload
            }

            entity = TextEntity(
                kind: .mention,
                range: token.replaceRange,
                displayText: suggestion.displayText,
                payloadByDestination: payloadByDestination,
                data: .mention(mentionData)
            )
        case "#":
            // Create hashtag entity
            let normalizedTag = suggestion.displayText.lowercased().trimmingCharacters(
                in: CharacterSet(charactersIn: "#"))
            let hashtagData = HashtagData(normalizedTag: normalizedTag)

            var payloadByDestination: [String: EntityPayload] = [:]
            for destinationID in token.scope {
                payloadByDestination[destinationID] = EntityPayload(
                    platform: suggestion.platforms.first ?? .mastodon, data: ["tag": normalizedTag])
            }

            entity = TextEntity(
                kind: .hashtag,
                range: token.replaceRange,
                displayText: suggestion.displayText,
                payloadByDestination: payloadByDestination,
                data: .hashtag(hashtagData)
            )
        case ":":
            // Emoji entity
            let emojiData = EmojiData(
                shortcode: suggestion.displayText.trimmingCharacters(
                    in: CharacterSet(charactersIn: ":")),
                emojiURL: suggestion.avatarURL,
                unicodeEmoji: nil
            )

            var payloadByDestination: [String: EntityPayload] = [:]
            for destinationID in token.scope {
                payloadByDestination[destinationID] = suggestion.entityPayload
            }

            entity = TextEntity(
                kind: .emoji,
                range: token.replaceRange,
                displayText: suggestion.displayText,
                payloadByDestination: payloadByDestination,
                data: .emoji(emojiData)
            )
        default:
            return
        }

        // Apply atomic replace
        composerTextModel.replace(
            range: token.replaceRange, with: suggestion.displayText, entities: [entity])

        // Update text in thread post (this will trigger UITextView update via binding)
        let newText = composerTextModel.toPlainText()
        threadPosts[activePostIndex].text = newText

        // Also sync composer model text
        composerTextModel.text = newText

        // Register undo action for entity state
        // UITextView will handle text undo automatically via its undo manager
        // We sync entities when text changes (including undo/redo) via onUndoRedo callback
        // This ensures entity state stays in sync with text state

        // Dismiss autocomplete
        currentAutocompleteToken = nil
        autocompleteSuggestions = []

        // Update cache
        if token.prefix == "@" {
            AutocompleteCache.shared.addRecentMention(
                suggestion,
                accountId: token.scope.first?.split(separator: ":").last.map(String.init) ?? "")
        } else if token.prefix == "#" {
            AutocompleteCache.shared.addRecentHashtag(
                suggestion,
                accountId: token.scope.first?.split(separator: ":").last.map(String.init) ?? "")
        } else if token.prefix == ":" {
            EmojiService(mastodonService: socialServiceManager.mastodonService).addRecentlyUsed(
                suggestion.displayText.trimmingCharacters(in: CharacterSet(charactersIn: ":")))
        }
    }
}

struct PlatformToggleButton: View {
    let platform: SocialPlatform
    let isSelected: Bool
    let action: () -> Void

    // Helper function to get platform color that's compatible with iOS 16
    private func getPlatformColor() -> Color {
        switch platform {
        case .mastodon:
            return Color("AppPrimaryColor")
        case .bluesky:
            return Color("AppSecondaryColor")
        }
    }

    // Helper function to get a lighter version of the platform color
    private func getLightPlatformColor() -> Color {
        return getPlatformColor().opacity(0.1)
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(platform.icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 14, height: 14)

                Text(platform.rawValue)
                    .font(.subheadline)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .foregroundColor(isSelected ? .white : getPlatformColor())
            .background(
                Capsule()
                    .fill(isSelected ? getPlatformColor() : getLightPlatformColor())
            )
        }
    }
}

struct ComposeView_Previews: PreviewProvider {
    static var previews: some View {
        ComposeView()
    }
}

struct DraftsListView: View {
    @EnvironmentObject var draftStore: DraftStore
    let onSelect: (DraftPost) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draftToRename: DraftPost? = nil
    @State private var newName: String = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(draftStore.drafts) { draft in
                    Button(action: {
                        onSelect(draft)
                    }) {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                if draft.isPinned {
                                    Image(systemName: "pin.fill")
                                        .font(.caption2)
                                        .foregroundColor(.orange)
                                }
                                
                                if let name = draft.name {
                                    Text(name)
                                        .font(.headline)
                                        .lineLimit(1)
                                } else {
                                    let firstPostText = draft.posts.first?.text ?? ""
                                    Text(firstPostText.isEmpty ? "(No content)" : firstPostText)
                                        .lineLimit(1)
                                        .font(.headline)
                                }
                            }

                            if draft.name != nil {
                                let firstPostText = draft.posts.first?.text ?? ""
                                if !firstPostText.isEmpty {
                                    Text(firstPostText)
                                        .lineLimit(1)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            }

                            HStack {
                                Text(
                                    draft.createdAt.formatted(date: .abbreviated, time: .shortened)
                                )
                                .font(.caption)
                                .foregroundColor(.secondary)

                                if draft.posts.count > 1 {
                                    Text("• \(draft.posts.count) posts")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                HStack(spacing: 4) {
                                    ForEach(Array(draft.selectedPlatforms), id: \.self) {
                                        platform in
                                        Image(platform.icon)
                                            .resizable()
                                            .scaledToFit()
                                            .frame(width: 12, height: 12)
                                    }
                                }
                                .foregroundColor(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .swipeActions(edge: .leading) {
                        Button {
                            draftStore.togglePin(draft)
                        } label: {
                            Label(draft.isPinned ? "Unpin" : "Pin", systemImage: draft.isPinned ? "pin.slash.fill" : "pin.fill")
                        }
                        .tint(.orange)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            draftStore.deleteDraft(draft)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        
                        Button {
                            draftToRename = draft
                            newName = draft.name ?? ""
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                    .contextMenu {
                        Button {
                            draftStore.togglePin(draft)
                        } label: {
                            Label(draft.isPinned ? "Unpin" : "Pin", systemImage: draft.isPinned ? "pin.slash.fill" : "pin.fill")
                        }
                        
                        Button {
                            draftToRename = draft
                            newName = draft.name ?? ""
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            draftStore.deleteDraft(draft)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    EditButton()
                }
            }
            .alert("Rename Draft", isPresented: Binding(get: { draftToRename != nil }, set: { if !$0 { draftToRename = nil } })) {
                TextField("Draft Name", text: $newName)
                Button("Cancel", role: .cancel) {
                    draftToRename = nil
                }
                Button("Rename") {
                    if let draft = draftToRename {
                        draftStore.renameDraft(draft, newName: newName)
                    }
                    draftToRename = nil
                }
            }
        }
    }
}

struct PhotoPicker: UIViewControllerRepresentable {
    @Binding var selectedImages: [UIImage]
    let maxImages: Int

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = maxImages

        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoPicker

        init(_ parent: PhotoPicker) {
            self.parent = parent
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)

            let group = DispatchGroup()
            var newImages: [UIImage] = []

            for result in results {
                group.enter()
                if result.itemProvider.canLoadObject(ofClass: UIImage.self) {
                    result.itemProvider.loadObject(ofClass: UIImage.self) { image, error in
                        if let image = image as? UIImage {
                            newImages.append(image)
                        }
                        group.leave()
                    }
                } else {
                    group.leave()
                }
            }

            group.notify(queue: .main) {
                self.parent.selectedImages.append(contentsOf: newImages)
                // Limit to maxImages
                if self.parent.selectedImages.count > self.parent.maxImages {
                    self.parent.selectedImages = Array(
                        self.parent.selectedImages.prefix(self.parent.maxImages))
                }
            }
        }
    }
}
import SwiftUI

struct LinkInputDialog: View {
    @Binding var isPresented: Bool
    @State private var url: String = ""
    @State private var displayText: String = ""
    var onInsert: (String, String) -> Void
    
    // Auto-focus the URL field
    @FocusState private var isUrlFocused: Bool
    
    init(isPresented: Binding<Bool>, initialText: String = "", onInsert: @escaping (String, String) -> Void) {
        self._isPresented = isPresented
        self._displayText = State(initialValue: initialText)
        self.onInsert = onInsert
    }
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Link Details")) {
                    TextField("URL (https://...)", text: $url)
                        .keyboardType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($isUrlFocused)
                    
                    TextField("Display Text", text: $displayText)
                }
            }
            .navigationTitle("Insert Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        isPresented = false
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Insert") {
                        if !url.isEmpty {
                            // Ensure URL has scheme
                            var finalURL = url
                            if !finalURL.lowercased().hasPrefix("http://") && !finalURL.lowercased().hasPrefix("https://") {
                                finalURL = "https://" + finalURL
                            }
                            onInsert(finalURL, displayText.isEmpty ? url : displayText)
                        }
                        isPresented = false
                    }
                    .disabled(url.isEmpty)
                    .fontWeight(.bold)
                }
            }
            .onAppear {
                isUrlFocused = true
            }
        }
    }
}
