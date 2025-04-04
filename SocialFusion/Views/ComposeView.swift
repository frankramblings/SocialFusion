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
        !postText.isEmpty && !isOverLimit && !selectedPlatforms.isEmpty && !isPosting
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
                .padding(.vertical, 8)

                Divider()

                // Text editor
                ZStack(alignment: .topLeading) {
                    if postText.isEmpty {
                        Text("What's on your mind?")
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.top, 8)
                    }

                    TextEditor(text: $postText)
                        .padding(4)
                        .background(Color(UIColor.systemBackground))
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

                // Selected images preview
                if !selectedImages.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(0..<selectedImages.count, id: \.self) { index in
                                ZStack(alignment: .topTrailing) {
                                    Image(uiImage: selectedImages[index])
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 100, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    Button(action: {
                                        selectedImages.remove(at: index)
                                    }) {
                                        Image(systemName: "xmark.circle.fill")
                                            .foregroundColor(.white)
                                            .background(Color.black.opacity(0.6))
                                            .clipShape(Circle())
                                    }
                                    .padding(4)
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .frame(height: 120)
                    .padding(.vertical, 8)

                    Divider()
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
                    }

                    Spacer()

                    // Character counter
                    Text("\(remainingChars)")
                        .font(.subheadline)
                        .foregroundColor(isOverLimit ? .red : .secondary)

                    // Post button
                    Button(action: {
                        postContent()
                    }) {
                        Text("Post")
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(canPost ? Color("PrimaryColor") : Color.gray)
                            .cornerRadius(20)
                    }
                    .disabled(!canPost)
                }
                .padding()
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
        guard canPost else { return }

        isPosting = true

        // Convert selectedVisibility to PostVisibilityType
        let visibilityType: PostVisibilityType
        switch selectedVisibility {
        case 0:
            visibilityType = .public_
        case 1:
            visibilityType = .unlisted
        case 2:
            visibilityType = .private_
        default:
            visibilityType = .public_
        }

        // This would be replaced with actual API calls to Mastodon and Bluesky
        // For now, we'll just simulate posting with a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // Simulate successful post
            isPosting = false
            alertTitle = "Success"
            alertMessage = "Your post has been shared to \(selectedPlatformsString)."
            showAlert = true

            // Reset the compose view
            postText = ""
            selectedImages = []
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

// A placeholder for the ImagePicker that would use UIImagePickerController or PHPickerViewController
struct ImagePicker: View {
    @Binding var selectedImages: [UIImage]
    let maxImages: Int
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        NavigationView {
            VStack {
                Text("This is a placeholder for the image picker.")
                    .padding()

                Button("Add Sample Image") {
                    // Add a placeholder image for demonstration
                    if selectedImages.count < maxImages {
                        // In a real app, this would be replaced with actual image selection
                        let placeholderImage =
                            UIImage(systemName: "photo")?.withTintColor(
                                .gray, renderingMode: .alwaysOriginal) ?? UIImage()
                        selectedImages.append(placeholderImage)
                    }
                }
                .padding()

                Button("Done") {
                    presentationMode.wrappedValue.dismiss()
                }
                .padding()
            }
            .navigationTitle("Select Images")
            .navigationBarItems(
                trailing: Button("Cancel") {
                    presentationMode.wrappedValue.dismiss()
                })
        }
    }
}

struct ComposeView_Previews: PreviewProvider {
    static var previews: some View {
        ComposeView()
    }
}
