import Combine
import SwiftUI
import UIKit

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
                Image(systemName: post.platform.icon)
                    .font(.caption2)
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
    @State private var postText = ""
    @State private var selectedPlatforms: Set<SocialPlatform> = [.mastodon, .bluesky]
    @State private var showImagePicker = false
    @State private var selectedImages: [UIImage] = []
    @State private var isPosting = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""

    // Reply context
    let replyingTo: Post?
    @State private var isTextFieldFocused: Bool = false

    // Add SocialServiceManager for actual posting
    @EnvironmentObject private var socialServiceManager: SocialServiceManager

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
        currentCharLimit - postText.count
    }

    private var isOverLimit: Bool {
        remainingChars < 0
    }

    private var canPost: Bool {
        !postText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !isOverLimit
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
                        text: $postText,
                        placeholder: placeholderText,
                        shouldAutoFocus: replyingTo != nil,
                        onFocusChange: { isFocused in
                            isTextFieldFocused = isFocused
                        }
                    )
                }
                .frame(maxHeight: .infinity)
                .padding(.horizontal, 8)
                .padding(.top, 8)

                // Selected images preview
                if !selectedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(0..<selectedImages.count, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: selectedImages[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 10))
                                        .shadow(
                                            color: Color.black.opacity(0.1), radius: 2, x: 0, y: 1)

                                    Button(action: {
                                        selectedImages.remove(at: index)
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

                    Spacer()

                    // Character counter
                    Text("\(remainingChars)")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(
                            isOverLimit ? .red : (remainingChars < 50 ? .orange : .secondary)
                        )
                        .padding(.horizontal, 10)

                    // Post button - Enhanced with Liquid Glass
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
                            .fill(canPost ? .regularMaterial : .ultraThinMaterial)
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

            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .keyboardAdaptive()
            .sheet(isPresented: $showImagePicker) {
                ImagePicker(selectedImages: $selectedImages, maxImages: 4)
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

        // Convert UIImages to Data for API calls
        let mediaData: [Data] = selectedImages.compactMap { image in
            return image.jpegData(compressionQuality: 0.8)
        }

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
                // Handle reply vs new post
                if let replyingTo = replyingTo {
                    // This is a reply
                    let _ = try await socialServiceManager.replyToPost(
                        replyingTo, content: postText)

                    await MainActor.run {
                        isPosting = false
                        alertTitle = "Reply Sent!"
                        alertMessage = "Your reply has been posted successfully."
                        showAlert = true

                        // Reset the compose view
                        postText = ""
                        selectedImages = []
                    }
                } else {
                    // This is a new post
                    let createdPosts = try await socialServiceManager.createPost(
                        content: postText,
                        platforms: selectedPlatforms,
                        mediaAttachments: mediaData,
                        visibility: visibilityString
                    )

                    await MainActor.run {
                        isPosting = false
                        alertTitle = "Success!"

                        if createdPosts.count == selectedPlatforms.count {
                            let platformNames = createdPosts.map { $0.platform.rawValue }.joined(
                                separator: " and ")
                            alertMessage =
                                "Your post has been successfully shared to \(platformNames)."
                        } else {
                            let successfulPlatforms = createdPosts.map { $0.platform.rawValue }
                                .joined(separator: " and ")
                            alertMessage =
                                "Your post was shared to \(successfulPlatforms). Some platforms may have failed."
                        }
                        showAlert = true

                        // Reset the compose view
                        postText = ""
                        selectedImages = []

                        // Reset platform selection to default
                        selectedPlatforms = [.mastodon, .bluesky]
                    }
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
                Image(systemName: platform.icon)
                    .font(.system(size: 14))

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
