import SwiftUI
import UIKit
import Photos

/// Sheet that presents share-as-image configuration and preview
public struct ShareAsImageSheet: View {
    @ObservedObject var viewModel: ShareAsImageViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingShareSheet = false
    @State private var shareFileURLs: [URL] = []
    @State private var isSavingToPhotos = false
    @State private var saveToPhotosError: String?

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
                        HapticEngine.tap.trigger()
                        dismiss()
                    }
                }

                ToolbarItem(placement: .primaryAction) {
                    HStack(spacing: 12) {
                        Button {
                            HapticEngine.tap.trigger()
                            Task {
                                await handleSaveToPhotos()
                            }
                        } label: {
                            if isSavingToPhotos {
                                ProgressView()
                            } else {
                                Label("Save", systemImage: "photo.badge.plus")
                            }
                        }
                        .disabled(viewModel.isRendering || isSavingToPhotos)
                        .accessibilityHint("Saves the image to your Photos library")

                        Button {
                            HapticEngine.tap.trigger()
                            Task {
                                await handleShare()
                            }
                        } label: {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                        .disabled(viewModel.isRendering)
                        .fontWeight(.semibold)
                        .accessibilityHint("Opens share options for this image")
                    }
                }
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
            .sheet(isPresented: $showingShareSheet, onDismiss: cleanupShareFiles) {
                if !shareFileURLs.isEmpty {
                    ShareSheet(activityItems: shareFileURLs)
                }
            }
        }
    }
    
    // MARK: - Preview Section

    private var previewSection: some View {
        let isPreviewBusy = viewModel.isRendering || viewModel.isRefiningPreview

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Preview")
                    .font(.headline)

                Spacer()

                // Page indicator for multi-page exports
                if viewModel.pageCount > 1 {
                    HStack(spacing: 4) {
                        Image(systemName: "rectangle.stack")
                            .font(.caption2.weight(.semibold))
                        Text("\(viewModel.pageCount) pages")
                            .font(.caption.weight(.medium))
                            .monospacedDigit()
                    }
                    .foregroundColor(.accentColor)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule()
                            .fill(Color.accentColor.opacity(0.14))
                    )
                    .accessibilityLabel("\(viewModel.pageCount) pages")
                }
            }

            ZStack {
                // Background
                Color(.systemGray6)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                if let image = viewModel.previewImage {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: .infinity)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .shadow(color: .black.opacity(0.1), radius: 4, y: 2)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }

                if viewModel.previewImage == nil {
                    VStack(spacing: 14) {
                        ProgressView()
                            .scaleEffect(1.2)

                        Text(viewModel.renderingProgress.isEmpty ? "Preparing preview" : viewModel.renderingProgress)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 400)
                }

                if isPreviewBusy, viewModel.previewImage != nil {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)

                        Text(viewModel.renderingProgress.isEmpty ? "Updating preview" : viewModel.renderingProgress)
                            .font(.caption.weight(.medium))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(.ultraThinMaterial, in: Capsule())
                    .overlay(
                        Capsule()
                            .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                    )
                    .shadow(color: .black.opacity(0.08), radius: 4, y: 2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                    .padding(12)
                    .transition(reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)))
                }
            }
            .frame(height: 400)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: viewModel.previewImage != nil)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isPreviewBusy)

            if let error = viewModel.errorMessage {
                VStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.14))
                            .frame(width: 72, height: 72)
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 30, weight: .semibold))
                            .foregroundStyle(Color.orange.gradient)
                            .symbolRenderingMode(.hierarchical)
                    }
                    Text(error)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
                .accessibilityElement(children: .combine)
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
            Toggle(isOn: $viewModel.hideUsernames) {
                Label {
                    Text("Hide names")
                } icon: {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(Color.orange.gradient)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .onChange(of: viewModel.hideUsernames) { _, _ in
                HapticEngine.selection.trigger()
            }

            // Branding
            Toggle(isOn: $viewModel.showWatermark) {
                Label {
                    Text("Watermark")
                } icon: {
                    Image(systemName: "signature")
                        .foregroundStyle(Color.accentColor.gradient)
                        .symbolRenderingMode(.hierarchical)
                }
            }
            .onChange(of: viewModel.showWatermark) { _, _ in
                HapticEngine.selection.trigger()
            }
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
                Toggle(isOn: $viewModel.includeEarlier) {
                    Label {
                        Text("Earlier replies")
                    } icon: {
                        Image(systemName: "arrow.up.message")
                            .foregroundStyle(Color.secondary.gradient)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .onChange(of: viewModel.includeEarlier) { _, _ in
                    HapticEngine.selection.trigger()
                }

                Toggle(isOn: $viewModel.includeLater) {
                    Label {
                        Text("Later replies")
                    } icon: {
                        Image(systemName: "arrow.down.message")
                            .foregroundStyle(Color.secondary.gradient)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .onChange(of: viewModel.includeLater) { _, _ in
                    HapticEngine.selection.trigger()
                }
            } else {
                // Post: Only show "Later replies" (labeled as "Replies" for both networks)
                Toggle(isOn: $viewModel.includeLater) {
                    Label {
                        Text("Replies")
                    } icon: {
                        Image(systemName: "bubble.left.and.bubble.right")
                            .foregroundStyle(Color.secondary.gradient)
                            .symbolRenderingMode(.hierarchical)
                    }
                }
                .onChange(of: viewModel.includeLater) { _, _ in
                    HapticEngine.selection.trigger()
                }
            }
        }
    }
    
    // MARK: - Actions

    private func handleShare() async {
        do {
            let result = try await viewModel.exportImages()
            cleanupShareFiles()
            shareFileURLs = try ShareImageRenderer.saveAllToTempFiles(
                result.images,
                baseFilename: "SocialFusion Share.jpg"
            )
            showingShareSheet = true
        } catch {
            cleanupShareFiles()
            viewModel.errorMessage = error.localizedDescription
            HapticEngine.error.trigger()
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
                    HapticEngine.warning.trigger()
                }
                return
            }
        } else if status != .authorized && status != .limited {
            await MainActor.run {
                saveToPhotosError = "Photo library access is required to save images. Please enable it in Settings."
                HapticEngine.warning.trigger()
            }
            return
        }

        // Export the images
        await MainActor.run {
            isSavingToPhotos = true
            saveToPhotosError = nil
        }

        do {
            let result = try await viewModel.exportImages()
            let fileURLs = try ShareImageRenderer.saveAllToTempFiles(
                result.images,
                baseFilename: "SocialFusion Save.jpg"
            )
            defer {
                for fileURL in fileURLs {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }

            // Save all images to Photos library
            try await PHPhotoLibrary.shared().performChanges {
                for fileURL in fileURLs {
                    PHAssetChangeRequest.creationRequestForAssetFromImage(atFileURL: fileURL)
                }
            }

            // Success — use a toast instead of a modal alert. Apple's
            // own Photos and screenshot flows use unobtrusive HUDs for
            // non-critical save confirmations; a modal alert with an
            // OK button interrupts the user's flow unnecessarily.
            await MainActor.run {
                isSavingToPhotos = false
                ToastManager.shared.show("Saved to Photos", severity: .success, duration: 1.8)
            }

            // Haptic still fires alongside the toast for tactile
            // confirmation independent of visual attention.
            HapticEngine.success.trigger()

        } catch {
            await MainActor.run {
                isSavingToPhotos = false
                saveToPhotosError = "Failed to save image: \(error.localizedDescription)"
            }

            // Provide haptic feedback
            HapticEngine.error.trigger()
        }
    }

    private func cleanupShareFiles() {
        for fileURL in shareFileURLs {
            try? FileManager.default.removeItem(at: fileURL)
        }
        shareFileURLs = []
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
