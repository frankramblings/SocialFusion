import SwiftUI

/// Modifier to handle keyboard shortcuts for ComposeView
/// Uses onKeyPress for iOS 17+, falls back gracefully for iOS 16
private struct KeyboardShortcutsModifier: ViewModifier {
    let canPost: Bool
    let postContent: () -> Void
    @Binding var selectedVisibility: Int
    let selectedPlatforms: Set<SocialPlatform>
    let toggleCW: () -> Void
    let toggleLabels: () -> Void
    let insertLink: () -> Void
    @Binding var currentAutocompleteToken: AutocompleteToken?
    @Binding var autocompleteSuggestions: [AutocompleteSuggestion]
    let autocompleteService: AutocompleteService?
    
    func body(content: Content) -> some View {
        if #available(iOS 17.0, *) {
            content
                .onKeyPress { keyPress in
                    // Check for Command+Return (Cmd+Enter)
                    if keyPress.key == .return && keyPress.modifiers.contains(.command) && !keyPress.modifiers.contains(.shift) {
                        if canPost {
                            postContent()
                        }
                        return .handled
                    }
                    // Check for Command+Shift+Return (Cmd+Shift+Enter)
                    if keyPress.key == .return && keyPress.modifiers.contains(.command) && keyPress.modifiers.contains(.shift) {
                        if canPost {
                            let originalVisibility = selectedVisibility
                            selectedVisibility = 1 // Unlisted
                            postContent()
                            selectedVisibility = originalVisibility
                        }
                        return .handled
                    }
                    // Check for Command+K
                    if keyPress.characters == "k" && keyPress.modifiers.contains(.command) {
                        insertLink()
                        return .handled
                    }
                    // Check for Command+L
                    if keyPress.characters == "l" && keyPress.modifiers.contains(.command) {
                        if selectedPlatforms.contains(.bluesky) {
                            toggleLabels()
                        } else {
                            toggleCW()
                        }
                        return .handled
                    }
                    // Check for Command+,
                    if keyPress.characters == "," && keyPress.modifiers.contains(.command) {
                        currentAutocompleteToken = nil
                        autocompleteSuggestions = []
                        autocompleteService?.cancelSearch()
                        return .handled
                    }
                    return .ignored
                }
        } else {
            // iOS 16 fallback: keyboard shortcuts not available at view level
            // Users can still use the UI buttons
            content
        }
    }
}

struct ComposeViewLifecycleModifier: ViewModifier {
    let hydrateAccountSelection: () -> Void
    let updatePlatformConflicts: () -> Void
    @Binding var autocompleteService: AutocompleteService?
    let socialServiceManager: SocialServiceManager
    let selectedPlatforms: Set<SocialPlatform>
    let selectedAccount: (SocialPlatform) -> SocialAccount?
    let canPost: Bool
    let postContent: () -> Void
    @Binding var currentAutocompleteToken: AutocompleteToken?
    @Binding var autocompleteSuggestions: [AutocompleteSuggestion]
    @Binding var selectedVisibility: Int
    @Binding var threadPosts: [ThreadPost]
    let activePostIndex: Int
    let toggleCW: () -> Void
    let toggleLabels: () -> Void
    let insertLink: () -> Void
    
    func body(content: Content) -> some View {
        content
            .onAppear {
                hydrateAccountSelection()
                autocompleteService = AutocompleteService(
                    cache: AutocompleteCache.shared,
                    mastodonService: socialServiceManager.mastodonService,
                    blueskyService: socialServiceManager.blueskyService,
                    accounts: selectedPlatforms.compactMap { selectedAccount($0) }
                )
                updatePlatformConflicts()
                socialServiceManager.isComposing = true
            }
            .onChange(of: threadPosts[activePostIndex].cwEnabled) { _ in
                updatePlatformConflicts()
            }
            .onChange(of: selectedPlatforms) { _ in
                updatePlatformConflicts()
            }
            .modifier(KeyboardShortcutsModifier(
                canPost: canPost,
                postContent: postContent,
                selectedVisibility: $selectedVisibility,
                selectedPlatforms: selectedPlatforms,
                toggleCW: toggleCW,
                toggleLabels: toggleLabels,
                insertLink: insertLink,
                currentAutocompleteToken: $currentAutocompleteToken,
                autocompleteSuggestions: $autocompleteSuggestions,
                autocompleteService: autocompleteService
            ))
            .onDisappear {
                socialServiceManager.isComposing = false
                if let service = autocompleteService {
                    service.cancelSearch()
                }
            }
    }
}
