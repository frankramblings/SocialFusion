import SwiftUI
import PhotosUI

struct ChatMediaPickerBar: View {
  @Binding var selectedItems: [PhotosPickerItem]
  @State private var thumbnails: [String: Image] = [:]

  var body: some View {
    if !selectedItems.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(Array(selectedItems.enumerated()), id: \.element.itemIdentifier) { index, item in
            attachmentCell(index: index, item: item)
          }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
      }
      .background(Color(.systemGray6))
    }
  }

  @ViewBuilder
  private func attachmentCell(index: Int, item: PhotosPickerItem) -> some View {
    let key = item.itemIdentifier ?? "\(index)"
    ZStack(alignment: .topTrailing) {
      thumbnailView(key: key, index: index)

      Button {
        // Selection haptic so a VoiceOver user (or anyone looking
        // away) knows the tap landed — the thumbnail animates out
        // visually but is silent otherwise.
        HapticEngine.selection.trigger()
        thumbnails.removeValue(forKey: key)
        selectedItems.remove(at: index)
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 18))
          .foregroundStyle(.white, .black.opacity(0.5))
      }
      .offset(x: 4, y: -4)
      .accessibilityLabel("Remove attachment \(index + 1)")
    }
    .task(id: item.itemIdentifier) {
      if let data = try? await item.loadTransferable(type: Data.self),
         let uiImage = UIImage(data: data) {
        thumbnails[key] = Image(uiImage: uiImage)
      }
    }
  }

  @ViewBuilder
  private func thumbnailView(key: String, index: Int) -> some View {
    if let thumb = thumbnails[key] {
      thumb
        .resizable()
        .aspectRatio(contentMode: .fill)
        .frame(width: 60, height: 60)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .accessibilityLabel("Attachment \(index + 1) of \(selectedItems.count)")
    } else {
      RoundedRectangle(cornerRadius: 8)
        .fill(Color(.systemGray5))
        .frame(width: 60, height: 60)
        .overlay(ProgressView().scaleEffect(0.6))
        .accessibilityLabel("Loading attachment \(index + 1) of \(selectedItems.count)")
    }
  }
}
