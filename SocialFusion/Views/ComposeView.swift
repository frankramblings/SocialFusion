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
    @State private var showAltTextSheet = false
    @State private var postingStatus: String = "Posting..."
    @State private var selectedImageIndexForAltText: Int = 0
    @State private var currentAltText: String = ""
    @State private var selectedAccounts: [SocialPlatform: String] = [:]

    @Environment(\.dismiss) private var dismiss

    // Reply and quote context
    let replyingTo: Post?
    let quotingTo: Post?
    @State private var isTextFieldFocused: Bool = false
    
    init(replyingTo: Post? = nil, quotingTo: Post? = nil) {
        self.replyingTo = replyingTo
        self.quotingTo = quotingTo
        // Initialize with the default visibility from user preferences
        _selectedVisibility = State(
            initialValue: UserDefaults.standard.integer(forKey: "defaultPostVisibility"))

        // For replies or quotes, filter platforms to match the original post
        if let post = replyingTo ?? quotingTo {
            _selectedPlatforms = State(initialValue: [post.platform])
        }
    }

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
        var isOverLimit: Bool { remaining < 0 }
    }

    private var platformLimitStatuses: [PlatformLimitStatus] {
        selectedPlatforms.sorted(by: { $0.rawValue < $1.rawValue }).map { platform in
            let limit = platform == .mastodon ? mastodonCharLimit : blueskyCharLimit
            let remaining = limit - threadPosts[activePostIndex].text.count
            let accountLabel =
                selectedAccount(for: platform)?.displayName
                ?? selectedAccount(for: platform)?.username
                ?? "Account"
            return PlatformLimitStatus(
                platform: platform,
                remaining: remaining,
                accountLabel: accountLabel
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

                platformStatusBar()

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

                // Poll creation section
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
                                        if index < threadPosts[activePostIndex].imageAltTexts.count
                                        {
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

                                    // Alt Text Button
                                    Button(action: {
                                        selectedImageIndexForAltText = index
                                        currentAltText =
                                            index < threadPosts[activePostIndex].imageAltTexts.count
                                            ? threadPosts[activePostIndex].imageAltTexts[index] : ""
                                        showAltTextSheet = true
                                    }) {
                                        Text("ALT")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 4)
                                            .background(
                                                index
                                                    < threadPosts[activePostIndex].imageAltTexts
                                                    .count
                                                    && !threadPosts[activePostIndex].imageAltTexts[
                                                        index
                                                    ].isEmpty
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
                                // Ensure imageAltTexts array is large enough
                                while threadPosts[activePostIndex].imageAltTexts.count
                                    < threadPosts[activePostIndex].images.count
                                {
                                    threadPosts[activePostIndex].imageAltTexts.append("")
                                }
                                threadPosts[activePostIndex].imageAltTexts[
                                    selectedImageIndexForAltText] = currentAltText
                                showAltTextSheet = false
                            }
                            .fontWeight(.bold)
                        }
                    }
                }
                .presentationDetents([.medium, .large])
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
            .onAppear {
                hydrateAccountSelection()
            }
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
                                Text(status.accountLabel)
                                    .font(.caption)
                                    .lineLimit(1)
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
                            Text(account.displayName ?? account.username)
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

                    Text(
                        selectedAccount(for: platform)?.displayName
                            ?? selectedAccount(for: platform)?.username ?? "Select account"
                    )
                    .font(.subheadline)
                    .fontWeight(.medium)
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
        if quotingTo != nil {
            postingStatus = "Creating quote..."
        } else {
            postingStatus = replyingTo != nil ? "Sending reply..." : "Posting..."
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

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
                    let mediaData: [Data] = threadPosts[0].images.compactMap { image in
                        image.jpegData(compressionQuality: 0.8)
                    }
                    let mediaAltTexts = normalizedAltTexts(for: threadPosts[0])
                    
                    let createdPosts = try await socialServiceManager.createQuotePost(
                        content: threadPosts[0].text,
                        quotedPost: quoteTarget,
                        platforms: selectedPlatforms
                    )
                    
                    // Register quote success with PostActionCoordinator
                    if FeatureFlagManager.isEnabled(.postActionsV2) {
                        await MainActor.run {
                            socialServiceManager.postActionCoordinator.registerQuoteSuccess(for: quoteTarget)
                        }
                    }
                    
                    await MainActor.run {
                        isPosting = false
                        dismiss()
                    }
                    return
                }
                
                var previousPostsByPlatform: [SocialPlatform: Post] = [:]
                if let replyTarget = replyingTo {
                    previousPostsByPlatform[replyTarget.platform] = replyTarget
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
                        let createdPosts = try await socialServiceManager.createPost(
                            content: threadPost.text,
                            platforms: selectedPlatforms,
                            mediaAttachments: mediaData,
                            mediaAltTexts: mediaAltTexts,
                            pollOptions: pollOptions,
                            pollExpiresIn: 86400,  // 24 hours
                            visibility: visibilityString,
                            accountOverrides: selectedAccountOverrides()
                        )
                        for post in createdPosts {
                            previousPostsByPlatform[post.platform] = post
                        }
                    } else {
                        var updatedPrevious: [SocialPlatform: Post] = [:]
                        for (platform, parentPost) in previousPostsByPlatform {
                            guard selectedPlatforms.contains(platform) else { continue }
                            let reply = try await socialServiceManager.replyToPost(
                                parentPost,
                                content: threadPost.text,
                                mediaAttachments: mediaData,
                                mediaAltTexts: mediaAltTexts,
                                pollOptions: pollOptions,
                                pollExpiresIn: 86400,
                                visibility: visibilityString,
                                accountOverride: selectedAccount(for: platform)
                            )
                            updatedPrevious[platform] = reply
                            
                            // Register reply success with PostActionCoordinator
                            if FeatureFlagManager.isEnabled(.postActionsV2) {
                                await MainActor.run {
                                    socialServiceManager.postActionCoordinator.registerReplySuccess(for: parentPost)
                                }
                            }
                        }
                        previousPostsByPlatform = updatedPrevious
                    }
                }

                await MainActor.run {
                    isPosting = false
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
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

                    // Reset platform selection to default and rehydrate account picks
                    selectedPlatforms = [.mastodon, .bluesky]
                    selectedAccounts.removeAll()
                    hydrateAccountSelection()

                    // Dismiss the view
                    dismiss()
                }

            } catch {
                await MainActor.run {
                    isPosting = false
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
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
