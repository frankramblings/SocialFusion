import SwiftUI
import UIKit
import UniformTypeIdentifiers
import Photos

/// Sheet that presents share-as-image configuration and preview
public struct ShareAsImageSheet: View {
    @ObservedObject var viewModel: ShareAsImageViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var shareImage: UIImage?
    @State private var isSavingToPhotos = false
    @State private var saveToPhotosError: String?
    @State private var saveToPhotosSuccess = false
    
    public init(viewModel: ShareAsImageViewModel) {
        self.viewModel = viewModel
    }
    
    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Preview
                    previewSection
                    
                    // Controls
                    controlsSection
                }
                .padding()
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                
                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button(action: {
                            Task {
                                await handleSaveToPhotos()
                            }
                        }) {
                            if isSavingToPhotos {
                                ProgressView()
                            } else {
                                Label("Save", systemImage: "photo.badge.plus")
                            }
                        }
                        .disabled(viewModel.isRendering || isSavingToPhotos)
                        
                        Button(action: {
                            Task {
                                await handleShare()
                            }
                        }) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .disabled(viewModel.isRendering)
                    }
                }
            }
            .alert("Saved to Photos", isPresented: $saveToPhotosSuccess) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("The image has been saved to your photo library.")
            }
            .alert("Error Saving to Photos", isPresented: .constant(saveToPhotosError != nil)) {
                Button("OK", role: .cancel) {
                    saveToPhotosError = nil
                }
            } message: {
                if let error = saveToPhotosError {
                    Text(error)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let image = shareImage {
                    // Use ImageActivityItemSource - same approach as FullscreenMediaView uses for images
                    // This ensures "Save to Photos" appears in the share sheet
                    ShareSheet(activityItems: [ImageActivityItemSource(image: image)])
                }
            }
        }
    }
    
    // MARK: - Preview Section
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Preview")
                .font(.headline)
            
            ZStack {
                // Background
                Color(.systemGray6)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                
                if viewModel.isRendering || viewModel.previewImage == nil {
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.2)
                        
                        if !viewModel.renderingProgress.isEmpty {
                            Text(viewModel.renderingProgress)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Preparing preview...")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 400)
                }
                
                if let image = viewModel.previewImage, !viewModel.isRendering {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            }
            .frame(height: 400)
            .animation(.easeInOut(duration: 0.2), value: viewModel.previewImage != nil)
            
            if let error = viewModel.errorMessage {
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundColor(.orange)
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 200)
            }
        }
    }
    
    // MARK: - Controls Section
    
    private var controlsSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Show section (Earlier/Later toggles)
            showSection
            
            Divider()
            
            // Privacy
            Toggle("Hide names", isOn: $viewModel.hideUsernames)
            
            // Branding
            Toggle("Watermark", isOn: $viewModel.showWatermark)
        }
    }
    
    // MARK: - Show Section
    
    private var showSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Show")
                .font(.headline)
            
            // Dynamic toggles based on whether sharing a post or reply
            if viewModel.isReply {
                // Reply: Show both toggles
                Toggle("Earlier replies", isOn: $viewModel.includeEarlier)
                Toggle("Later replies", isOn: $viewModel.includeLater)
            } else {
                // Post: Only show "Later replies" (labeled as "Replies" for both networks)
                Toggle("Replies", isOn: $viewModel.includeLater)
            }
        }
    }
    
    // MARK: - Actions
    
    private func handleShare() async {
        do {
            let result = try await viewModel.exportImage()
            shareImage = result.image
            // Use ImageActivityItemSource - same approach as FullscreenMediaView
            // The temp file (result.url) will be cleaned up automatically
            showingShareSheet = true
        } catch {
            viewModel.errorMessage = error.localizedDescription
        }
    }
    
    private func handleSaveToPhotos() async {
        // Check authorization status
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        
        // Request authorization if needed
        if status == .notDetermined {
            let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
            if newStatus != .authorized && newStatus != .limited {
                await MainActor.run {
                    saveToPhotosError = "Photo library access is required to save images. Please enable it in Settings."
                }
                return
            }
        } else if status != .authorized && status != .limited {
            await MainActor.run {
                saveToPhotosError = "Photo library access is required to save images. Please enable it in Settings."
            }
            return
        }
        
        // Export the image
        await MainActor.run {
            isSavingToPhotos = true
            saveToPhotosError = nil
        }
        
        do {
            let result = try await viewModel.exportImage()
            let image = result.image
            
            // Save to Photos library
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
            
            // Success
            await MainActor.run {
                isSavingToPhotos = false
                saveToPhotosSuccess = true
            }
            
            // Provide haptic feedback
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            
        } catch {
            await MainActor.run {
                isSavingToPhotos = false
                saveToPhotosError = "Failed to save image: \(error.localizedDescription)"
            }
            
            // Provide haptic feedback
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
}

// MARK: - Share Sheet Wrapper

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        // Match FullscreenMediaView's excluded activity types
        // Don't exclude activity types - let iOS show all available options
        // This enables Save to Photos, Messages, Mail, AirDrop, etc.
        // Only exclude activity types that truly don't make sense for images
        controller.excludedActivityTypes = [
            .assignToContact,  // Don't assign images to contacts
            .addToReadingList   // Reading list doesn't make sense for images
        ]
        
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}
