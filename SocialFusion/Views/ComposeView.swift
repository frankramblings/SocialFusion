import SwiftUI
import UIKit

struct ComposeView: View {
    @State private var postText = ""
    @State private var selectedPlatforms: Set<SocialPlatform> = [.mastodon, .bluesky]
    @State private var showImagePicker = false
    @State private var selectedImages: [UIImage] = []
    @State private var isPosting = false
    @State private var showAlert = false
    @State private var alertTitle = ""
    @State private var alertMessage = ""
    
    // Add SocialServiceManager for actual posting
    @ObservedObject private var socialServiceManager = SocialServiceManager.shared

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
        !postText.isEmpty && !isOverLimit && !selectedPlatforms.isEmpty && !isPosting && hasAccountsForSelectedPlatforms
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
            return "Posting..."
        } else {
            return "Post"
        }
    }
    
    // Helper for button color
    private var buttonColor: Color {
        if !hasAccountsForSelectedPlatforms {
            return Color.orange
        } else if canPost {
            return Color.blue
        } else {
            return Color.gray.opacity(0.5)
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

    init() {
        // Initialize with the default visibility from user preferences
        _selectedVisibility = State(
            initialValue: UserDefaults.standard.integer(forKey: "defaultPostVisibility"))
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Platform selection
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

                // Text editor
                ZStack(alignment: .topLeading) {
                    if postText.isEmpty {
                        Text("What's on your mind?")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 12)
                            .padding(.top, 12)
                    }

                    TextEditor(text: $postText)
                        .padding(8)
                        .background(Color(UIColor.systemBackground))
                        .cornerRadius(8)
                        // Add keyboard toolbar to avoid SystemInputAssistantView conflict
                        .toolbar {
                            ToolbarItemGroup(placement: .keyboard) {
                                Spacer()
                                Button("Done") {
                                    UIApplication.shared.sendAction(
                                        #selector(UIResponder.resignFirstResponder), to: nil,
                                        from: nil, for: nil)
                                }
                            }
                        }
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

                // Bottom toolbar
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

                    // Post button
                    Button(action: {
                        postContent()
                    }) {
                        Text(buttonText)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(buttonColor)
                            .cornerRadius(20)
                            .shadow(
                                color: canPost ? Color.blue.opacity(0.3) : Color.clear, radius: 2,
                                x: 0, y: 1)
                    }
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
            .navigationTitle("New Post")
            .navigationBarTitleDisplayMode(.inline)
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
                // Call the actual posting API
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
                        let platformNames = createdPosts.map { $0.platform.rawValue }.joined(separator: " and ")
                        alertMessage = "Your post has been successfully shared to \(platformNames)."
                    } else {
                        let successfulPlatforms = createdPosts.map { $0.platform.rawValue }.joined(separator: " and ")
                        alertMessage = "Your post was shared to \(successfulPlatforms). Some platforms may have failed."
                    }
                    showAlert = true

                    // Reset the compose view
                    postText = ""
                    selectedImages = []
                    
                    // Reset platform selection to default
                    selectedPlatforms = [.mastodon, .bluesky]
                }
                
            } catch {
                await MainActor.run {
                    isPosting = false
                    alertTitle = "Error"
                    alertMessage = "Failed to post: \(error.localizedDescription)"
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
            return Color("PrimaryColor")
        case .bluesky:
            return Color("SecondaryColor")
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
            .navigationTitle("Select Photos")
            .navigationBarTitleDisplayMode(.inline)
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
