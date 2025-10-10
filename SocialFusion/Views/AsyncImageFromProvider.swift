import LinkPresentation
import SwiftUI
import UIKit

/// Helper view to load images from LPImageProvider asynchronously
struct AsyncImageFromProvider: View {
    let imageProvider: NSItemProvider
    @State private var uiImage: UIImage?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var errorMessage: String? = nil

    var body: some View {
        ZStack {
            if let image = uiImage {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if isLoading {
                Color.gray.opacity(0.2)
                    .overlay(
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    )
            } else if loadFailed {
                Color.gray.opacity(0.1)
                    .overlay(
                        VStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.gray)

                            if let errorMessage = errorMessage {
                                Text(errorMessage)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal)
                            }
                        }
                    )
            } else {
                Color.gray.opacity(0.1)
                    .overlay(
                        Image(systemName: "photo")
                            .font(.largeTitle)
                            .foregroundColor(.gray)
                    )
            }
        }
        .onAppear {
            loadImage()
        }
    }

    private func loadImage() {
        // Set a timeout for image loading (10 seconds)
        let timeout = DispatchTime.now() + 10.0

        imageProvider.loadObject(ofClass: UIImage.self) { image, error in
            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error {
                    self.loadFailed = true
                    self.errorMessage = URLService.shared.friendlyErrorMessage(for: error)
                    print("Error loading image from provider: \(error.localizedDescription)")
                    return
                }

                if let image = image as? UIImage {
                    self.uiImage = image
                } else {
                    self.loadFailed = true
                    self.errorMessage = "Invalid image format"
                }
            }
        }

        // Backup timeout handler
        DispatchQueue.main.asyncAfter(deadline: timeout) {
            if self.isLoading {
                self.isLoading = false
                self.loadFailed = true
                self.errorMessage = "Image loading timed out"
            }
        }
    }
}

// Preview
#Preview {
    // This can't be easily previewed since it needs an LPImageProvider
    Text("AsyncImageFromProvider needs an LPImageProvider")
}
