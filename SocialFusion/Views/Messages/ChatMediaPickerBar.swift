import SwiftUI
import PhotosUI

struct ChatMediaPickerBar: View {
  @Binding var selectedItems: [PhotosPickerItem]
  @State private var thumbnails: [String: Image] = [:]
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    if !selectedItems.isEmpty {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 10) {
          ForEach(Array(selectedItems.enumerated()), id: \.element.itemIdentifier) { index, item in
            let key = item.itemIdentifier ?? "\(index)"
            ThumbnailCell(
              thumbnail: thumbnails[key],
              onRemove: {
                HapticEngine.tap.trigger()
                withAnimation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82)) {
                  thumbnails.removeValue(forKey: key)
                  selectedItems.remove(at: index)
                }
              }
            )
            .task(id: item.itemIdentifier) {
              if let data = try? await item.loadTransferable(type: Data.self),
                 let uiImage = UIImage(data: data) {
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) {
                  thumbnails[key] = Image(uiImage: uiImage)
                }
              }
            }
            .transition(
              .asymmetric(
                insertion: .scale(scale: 0.85).combined(with: .opacity),
                removal: .scale(scale: 0.7, anchor: .center).combined(with: .opacity)
              )
            )
          }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
      }
      .background(.ultraThinMaterial)
      .overlay(
        Divider(),
        alignment: .top
      )
    }
  }
}

/// A single thumbnail cell with a refined remove affordance.
private struct ThumbnailCell: View {
  let thumbnail: Image?
  let onRemove: () -> Void

  var body: some View {
    ZStack(alignment: .topTrailing) {
      Group {
        if let thumb = thumbnail {
          thumb
            .resizable()
            .aspectRatio(contentMode: .fill)
        } else {
          RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(.systemGray5))
            .overlay(ProgressView().scaleEffect(0.6))
        }
      }
      .frame(width: 64, height: 64)
      .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
      )
      .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 1)

      // Remove button — sits in the corner, larger hit target than the visual
      Button(action: onRemove) {
        Image(systemName: "xmark.circle.fill")
          .font(.system(size: 20))
          .foregroundStyle(.white, .black.opacity(0.55))
          .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0.5)
          .frame(width: 32, height: 32)  // expanded hit area
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .offset(x: 6, y: -6)
      .accessibilityLabel("Remove attachment")
    }
  }
}
