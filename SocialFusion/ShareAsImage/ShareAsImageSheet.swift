import SwiftUI
import UIKit

/// Sheet that presents share-as-image configuration and preview
public struct ShareAsImageSheet: View {
    @ObservedObject var viewModel: ShareAsImageViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var showingShareSheet = false
    @State private var shareImage: UIImage?
    @State private var shareURL: URL?
    
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
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share") {
                        Task {
                            await handleShare()
                        }
                    }
                    .disabled(viewModel.isRendering)
                }
            }
            .sheet(isPresented: $showingShareSheet) {
                if let image = shareImage, let url = shareURL {
                    ShareSheet(activityItems: [image, url])
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
            shareURL = result.url
            showingShareSheet = true
        } catch {
            viewModel.errorMessage = error.localizedDescription
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
        // Ensure Save to Photos appears
        controller.excludedActivityTypes = []
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No updates needed
    }
}
