import AVKit
import SwiftUI

/// View for displaying media attachments in fullscreen mode
struct FullscreenMediaView: View {
    // For single attachment view
    var attachment: Post.Attachment? = nil
    // For gallery view with multiple attachments
    var attachments: [Post.Attachment] = []
    var initialIndex: Int = 0

    @State private var currentIndex: Int = 0
    @State private var scale: CGFloat = 1.0
    @State private var lastScale: CGFloat = 1.0
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero
    @State private var showControls = true
    @Environment(\.dismiss) private var dismiss

    // Computed property to work with either single attachment or collection
    private var currentAttachments: [Post.Attachment] {
        if let attachment = attachment {
            return [attachment]
        } else {
            return attachments
        }
    }

    private var currentAttachment: Post.Attachment? {
        guard currentAttachments.indices.contains(currentIndex) else {
            return nil
        }
        return currentAttachments[currentIndex]
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                if let currentAttachment = currentAttachment {
                    TabView(selection: $currentIndex) {
                        ForEach(currentAttachments.indices, id: \.self) { index in
                            ZStack {
                                mediaView(for: currentAttachments[index], in: geometry)
                                    .gesture(
                                        MagnificationGesture()
                                            .onChanged { value in
                                                let delta = value / lastScale
                                                lastScale = value
                                                scale = min(max(scale * delta, 1.0), 4.0)
                                            }
                                            .onEnded { _ in
                                                lastScale = 1.0
                                                if scale < 1.2 {
                                                    withAnimation {
                                                        scale = 1.0
                                                        offset = .zero
                                                    }
                                                }
                                            }
                                    )
                                    .simultaneousGesture(
                                        DragGesture()
                                            .onChanged { value in
                                                if scale > 1.0 {
                                                    offset = CGSize(
                                                        width: lastOffset.width
                                                            + value.translation.width,
                                                        height: lastOffset.height
                                                            + value.translation.height
                                                    )
                                                }
                                            }
                                            .onEnded { _ in
                                                lastOffset = offset
                                                if scale < 1.2 {
                                                    withAnimation {
                                                        offset = .zero
                                                    }
                                                }
                                            }
                                    )
                                    .simultaneousGesture(
                                        TapGesture(count: 2)
                                            .onEnded { _ in
                                                withAnimation {
                                                    if scale > 1.0 {
                                                        scale = 1.0
                                                        offset = .zero
                                                    } else {
                                                        scale = 2.0
                                                    }
                                                }
                                                lastOffset = offset
                                            }
                                    )
                                    .simultaneousGesture(
                                        TapGesture()
                                            .onEnded { _ in
                                                withAnimation {
                                                    showControls.toggle()
                                                }
                                            }
                                    )
                            }
                            .tag(index)
                        }
                    }
                    .tabViewStyle(PageTabViewStyle(indexDisplayMode: .never))
                    .onAppear {
                        currentIndex = initialIndex
                        // Preload adjacent images
                        preloadAdjacentImages()
                    }
                    .onChange(of: currentIndex) { _ in
                        withAnimation {
                            scale = 1.0
                            offset = .zero
                        }
                        lastOffset = .zero
                        // Preload adjacent images when index changes
                        preloadAdjacentImages()
                    }
                } else {
                    Text("No media to display")
                        .foregroundColor(.white)
                }

                // Controls overlay
                if showControls {
                    VStack {
                        HStack {
                            Button(action: {
                                dismiss()
                            }) {
                                Image(systemName: "xmark")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding(12)
                                    .background(Color.black.opacity(0.5))
                                    .clipShape(Circle())
                            }
                            .padding(.leading)

                            Spacer()

                            if let currentAttachment = currentAttachment,
                                currentAttachment.type == .image,
                                let imageURLString = currentAttachment.url,
                                let imageURL = URL(string: imageURLString)
                            {
                                Button(action: {
                                    saveImageToPhotos(from: imageURL)
                                }) {
                                    Image(systemName: "square.and.arrow.down")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding(12)
                                        .background(Color.black.opacity(0.5))
                                        .clipShape(Circle())
                                }
                                .padding(.trailing)
                            }
                        }
                        .padding(.top)

                        Spacer()

                        // Alt text display if available
                        if let currentAttachment = currentAttachment,
                            let altText = currentAttachment.altText,
                            !altText.isEmpty
                        {
                            Text(altText)
                                .font(.caption)
                                .padding()
                                .background(Color.black.opacity(0.6))
                                .foregroundColor(.white)
                                .cornerRadius(8)
                                .padding()
                        }

                        // Page indicator dots
                        if currentAttachments.count > 1 {
                            HStack(spacing: 8) {
                                ForEach(0..<currentAttachments.count, id: \.self) { index in
                                    Circle()
                                        .fill(
                                            currentIndex == index
                                                ? Color.white : Color.white.opacity(0.5)
                                        )
                                        .frame(width: 8, height: 8)
                                }
                            }
                            .padding(.bottom)
                        }
                    }
                    .transition(.opacity)
                }
            }
        }
        .statusBar(hidden: true)
        .onDisappear {
            // Cancel any pending network operations
            ConnectionManager.shared.cancelAllRequests()
        }
    }

    @ViewBuilder
    private func mediaView(for attachment: Post.Attachment, in geometry: GeometryProxy) -> some View
    {
        switch attachment.type {
        case .image:
            if let urlString = attachment.url, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .foregroundColor(.white)
                            .scaleEffect(2)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: geometry.size.width, height: geometry.size.height)
                            .scaleEffect(scale)
                            .offset(offset)
                    case .failure:
                        VStack {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.largeTitle)
                                .foregroundColor(.white)
                            Text("Failed to load image")
                                .foregroundColor(.white)
                        }
                    @unknown default:
                        EmptyView()
                    }
                }
            } else {
                Text("Invalid image URL")
                    .foregroundColor(.white)
            }
        case .video:
            if let urlString = attachment.url, let url = URL(string: urlString) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(width: geometry.size.width, height: geometry.size.height)
            } else {
                Text("Invalid video URL")
                    .foregroundColor(.white)
            }
        case .gifv:
            if let urlString = attachment.url, let url = URL(string: urlString) {
                VideoPlayer(player: AVPlayer(url: url))
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .onAppear {
                        // Auto-play and loop GIFs
                        NotificationCenter.default.addObserver(
                            forName: .AVPlayerItemDidPlayToEndTime,
                            object: nil,
                            queue: .main
                        ) { _ in
                            if let player = AVPlayer(url: url) {
                                player.seek(to: .zero)
                                player.play()
                            }
                        }
                    }
            } else {
                Text("Invalid GIF URL")
                    .foregroundColor(.white)
            }
        default:
            Text("Unsupported media type")
                .foregroundColor(.white)
        }
    }

    private func preloadAdjacentImages() {
        // Only preload if we have attachments
        guard !currentAttachments.isEmpty else { return }

        // Get indices to preload: current, previous, and next
        var indicesToPreload = [currentIndex]

        if currentIndex > 0 {
            indicesToPreload.append(currentIndex - 1)
        }

        if currentIndex < currentAttachments.count - 1 {
            indicesToPreload.append(currentIndex + 1)
        }

        // Preload each image
        for index in indicesToPreload {
            guard index >= 0 && index < currentAttachments.count else { continue }
            let attachment = currentAttachments[index]

            if attachment.type == .image,
                let urlString = attachment.url,
                let url = URL(string: urlString)
            {
                ConnectionManager.shared.performRequest {
                    URLSession.shared.dataTask(with: url) { _, _, _ in
                        // Data is automatically cached by URLSession
                        ConnectionManager.shared.requestCompleted()
                    }.resume()
                }
            }
        }
    }

    private func saveImageToPhotos(from url: URL) {
        ConnectionManager.shared.performRequest {
            let task = URLSession.shared.dataTask(with: url) { data, response, error in
                guard let data = data, error == nil,
                    let image = UIImage(data: data)
                else {
                    ConnectionManager.shared.requestCompleted()
                    return
                }

                UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
                ConnectionManager.shared.requestCompleted()
            }
            task.resume()
        }
    }
}

struct MediaFullscreenView: View {
    let attachment: Post.Attachment
    @Environment(\.presentationMode) var presentationMode

    var body: some View {
        // Redirect to the new FullscreenMediaView for better functionality
        FullscreenMediaView(attachment: attachment)
    }
}

#Preview {
    MediaFullscreenView(
        attachment: Post.Attachment(
            url: "https://picsum.photos/800/600",
            type: .image,
            altText: "Sample image description"
        )
    )
}
