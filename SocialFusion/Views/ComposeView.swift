import Combine
import SwiftUI
import UIKit

/// A single post within a thread
public struct ThreadPost: Identifiable {
    public let id = UUID()
    public var text: String = ""
    public var images: [UIImage] = []
}

/// A view that shows context for what post is being replied to
struct ReplyContextHeader: View {
    let post: Post
    @Environment(\.colorScheme) private var colorScheme

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

                    VStack(alignment: .leading, spacing: 2) {
                        Text(post.authorName)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .lineLimit(1)

                        Text("@\(post.authorUsername)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
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

/// A UIViewRepresentable wrapper for UITextView with better focus control
struct FocusableTextEditor: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String
    let shouldAutoFocus: Bool
    let onFocusChange: (Bool) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = UITextView()
        textView.delegate = context.coordinator
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
        if uiView.text != text && uiView.textColor != UIColor.placeholderText {
            uiView.text = text
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

        init(_ parent: FocusableTextEditor) {
            self.parent = parent
            super.init()
        }

        deinit {
            parent = nil
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            guard let parent = parent, !isUpdating else { return }
            isUpdating = true

            if textView.textColor == UIColor.placeholderText {
                textView.text = ""
                textView.textColor = UIColor.label
            }
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

            isUpdating = false
        }

        func textViewDidChange(_ textView: UITextView) {
            guard let parent = parent,
                !isUpdating,
                textView.textColor != UIColor.placeholderText
            else { return }

            isUpdating = true
            parent.text = textView.text
            isUpdating = false
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

    @Environment(\.dismiss) private var dismiss

    // Reply context
    let replyingTo: Post?
    @State private var isTextFieldFocused: Bool = false

    // Add SocialServiceManager for actual posting
    @EnvironmentObject private var socialServiceManager: SocialServiceManager
    @EnvironmentObject private var draftStore: DraftStore

    @AppStorage("defaultPostVisibility") private var defaultPostVisibility = 0  // 0: Public, 1: Unlisted, 2: Followers Only

    private var postVisibilityOptions = ["Public", "Unlisted", "Followers Only"]
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
        for platform in selectedPlatforms {
            switch platform {
            case .mastodon:
                if socialServiceManager.mastodonAccounts.isEmpty {
                    return false
                }
            case .bluesky:
                if socialServiceManager.blueskyAccounts.isEmpty {
                    return false
                }
            }
        }
        return true
    }

    // Helper for button text
    private var buttonText: String {
        if !hasAccountsForSelectedPlatforms {
            return "No Accounts"
        } else if isPosting {
            return replyingTo != nil ? "Replying..." : "Posting..."
        } else {
            return replyingTo != nil ? "Reply" : "Post"
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

    // Helper to get missing platforms
    private var missingAccountPlatforms: [SocialPlatform] {
        var missing: [SocialPlatform] = []
        for platform in selectedPlatforms {
            switch platform {
            case .mastodon:
                if socialServiceManager.mastodonAccounts.isEmpty {
                    missing.append(.mastodon)
                }
            case .bluesky:
                if socialServiceManager.blueskyAccounts.isEmpty {
                    missing.append(.bluesky)
                }
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

    init(replyingTo: Post? = nil) {
        self.replyingTo = replyingTo
        // Initialize with the default visibility from user preferences
        _selectedVisibility = State(
            initialValue: UserDefaults.standard.integer(forKey: "defaultPostVisibility"))

        // For replies, filter platforms to match the original post
        if let post = replyingTo {
            _selectedPlatforms = State(initialValue: [post.platform])
        }
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Reply context header (only shown for replies)
                if let replyingTo = replyingTo {
                    ReplyContextHeader(post: replyingTo)
                }

                // Platform selection (hidden for replies since platform is predetermined)
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

                // Text editor
                ZStack(alignment: .topLeading) {
                    FocusableTextEditor(
                        text: $threadPosts[activePostIndex].text,
                        placeholder: placeholderText,
                        shouldAutoFocus: true,
                        onFocusChange: { isFocused in
                            isTextFieldFocused = isFocused
                        }
                    )
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 8)
                .padding(.top, 8)

                // Thread pagination / navigation if multiple posts
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

                // Selected images preview
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
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .font(.system(size: 18))
                                            .foregroundColor(.white)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Circle())
                                    }
                                    .padding(6)
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

                // Bottom toolbar - this will stay above keyboard
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
                    .padding(.horizontal, 10)
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
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
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
            .navigationTitle(replyingTo != nil ? "Reply" : "New Post")
            .navigationBarTitleDisplayMode(.inline)
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
                        replyingToId: replyingTo?.id
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
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .keyboardAdaptive()
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImages: $threadPosts[activePostIndex].images, maxImages: 4)
            }
            .alert(isPresented: $showAlert) {
                Alert(
                    title: Text(alertTitle),
                    message: Text(alertMessage),
                    dismissButton: .default(Text("OK"))
                )
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

                                Text("Posting...")
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
                var previousPost: Post? = replyingTo
                var createdCount = 0

                for threadPost in threadPosts {
                    // Convert UIImages to Data for API calls
                    let mediaData: [Data] = threadPost.images.compactMap { image in
                        return image.jpegData(compressionQuality: 0.8)
                    }

                    if let replyToPost = previousPost {
                        // This is a reply
                        let createdReply = try await socialServiceManager.replyToPost(
                            replyToPost,
                            content: threadPost.text,
                            mediaAttachments: mediaData
                        )
                        previousPost = createdReply
                        createdCount += 1
                    } else {
                        // This is a new post (first in thread)
                        let createdPosts = try await socialServiceManager.createPost(
                            content: threadPost.text,
                            platforms: selectedPlatforms,
                            mediaAttachments: mediaData,
                            visibility: visibilityString
                        )
                        previousPost = createdPosts.first
                        createdCount += 1
                    }
                }

                await MainActor.run {
                    isPosting = false
                    alertTitle =
                        threadPosts.count > 1
                        ? "Thread Sent!" : (replyingTo != nil ? "Reply Sent!" : "Success!")

                    if threadPosts.count > 1 {
                        alertMessage = "Your thread of \(threadPosts.count) posts has been shared."
                    } else if replyingTo != nil {
                        alertMessage = "Your reply has been posted successfully."
                    } else {
                        alertMessage = "Your post has been shared."
                    }

                    showAlert = true

                    // Reset the compose view
                    threadPosts = [ThreadPost()]
                    activePostIndex = 0

                    // Reset platform selection to default
                    selectedPlatforms = [.mastodon, .bluesky]

                    // Dismiss the view
                    dismiss()
                }

            } catch {
                await MainActor.run {
                    isPosting = false
                    alertTitle = "Error"
                    alertMessage =
                        "Failed to \(replyingTo != nil ? "reply" : "post"): \(error.localizedDescription)"
                    showAlert = true
                }

                print("Posting error: \(error)")
            }
        }
    }

    private var selectedPlatformsString: String {
        selectedPlatforms.map { $0.rawValue }.joined(separator: " and ")
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

// A more realistic implementation of the ImagePicker
struct ImagePicker: View {
    @Binding var selectedImages: [UIImage]
    let maxImages: Int
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) private var colorScheme

    // Sample images for demonstration
    private let sampleImages: [UIImage] = [
        UIImage(systemName: "photo")?.withTintColor(.blue, renderingMode: .alwaysOriginal)
            ?? UIImage(),
        UIImage(systemName: "camera")?.withTintColor(.green, renderingMode: .alwaysOriginal)
            ?? UIImage(),
        UIImage(systemName: "doc.text.image")?.withTintColor(
            .orange, renderingMode: .alwaysOriginal) ?? UIImage(),
        UIImage(systemName: "photo.on.rectangle")?.withTintColor(
            .purple, renderingMode: .alwaysOriginal) ?? UIImage(),
        UIImage(systemName: "square.and.arrow.up")?.withTintColor(
            .red, renderingMode: .alwaysOriginal) ?? UIImage(),
        UIImage(systemName: "square.and.arrow.down")?.withTintColor(
            .cyan, renderingMode: .alwaysOriginal) ?? UIImage(),
    ]

    // Track selected state for each image
    @State private var selectedIndices: Set<Int> = []

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Selection info
                HStack {
                    Text("\(selectedIndices.count) selected")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Spacer()

                    Text("\(maxImages - selectedIndices.count) remaining")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color(UIColor.secondarySystemBackground))

                // Photo grid
                ScrollView {
                    LazyVGrid(
                        columns: [
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                            GridItem(.flexible()),
                        ], spacing: 8
                    ) {
                        ForEach(0..<sampleImages.count, id: \.self) { index in
                            ZStack(alignment: .topTrailing) {
                                Image(uiImage: sampleImages[index])
                                    .resizable()
                                    .scaledToFill()
                                    .frame(
                                        width: (UIScreen.main.bounds.width - 32) / 3,
                                        height: (UIScreen.main.bounds.width - 32) / 3
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(
                                                selectedIndices.contains(index)
                                                    ? Color.blue : Color.clear, lineWidth: 3)
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        toggleSelection(index)
                                    }

                                if selectedIndices.contains(index) {
                                    ZStack {
                                        Circle()
                                            .fill(Color.blue)
                                            .frame(width: 24, height: 24)

                                        Image(systemName: "checkmark")
                                            .font(.system(size: 12, weight: .bold))
                                            .foregroundColor(.white)
                                    }
                                    .padding(6)
                                }
                            }
                        }
                    }
                    .padding()
                }

                Divider()

                // Action buttons
                HStack {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Cancel")
                            .foregroundColor(.secondary)
                    }

                    Spacer()

                    Button(action: {
                        // Add selected images to the selectedImages array
                        selectedImages = selectedIndices.map { sampleImages[$0] }
                        presentationMode.wrappedValue.dismiss()
                    }) {
                        Text("Add \(selectedIndices.count) Photos")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(
                                selectedIndices.isEmpty ? Color.gray.opacity(0.5) : Color.blue
                            )
                            .cornerRadius(20)
                    }
                    .disabled(selectedIndices.isEmpty)
                }
                .padding()
            }

        }
    }

    private func toggleSelection(_ index: Int) {
        if selectedIndices.contains(index) {
            selectedIndices.remove(index)
        } else {
            if selectedIndices.count < maxImages {
                selectedIndices.insert(index)
            }
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

    var body: some View {
        NavigationView {
            List {
                ForEach(draftStore.drafts) { draft in
                    Button(action: {
                        onSelect(draft)
                    }) {
                        VStack(alignment: .leading, spacing: 4) {
                            let firstPostText = draft.posts.first?.text ?? ""
                            Text(firstPostText.isEmpty ? "(No content)" : firstPostText)
                                .lineLimit(2)
                                .font(.body)

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
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        draftStore.deleteDraft(draftStore.drafts[index])
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
        }
    }
}
