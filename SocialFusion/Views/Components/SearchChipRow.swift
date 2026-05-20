import SwiftUI

/// Chip row showing search parameters (network, scope, sort, instance info)
struct SearchChipRow: View {
  let model: SearchChipRowModel
  let onNetworkChange: ((SearchNetworkSelection) -> Void)?
  let onSortChange: ((SearchSort) -> Void)?

  @State private var showInstanceInfo = false

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        // Network chip (tappable menu)
        if let onNetworkChange {
          Menu {
            ForEach(SearchNetworkSelection.allCases, id: \.self) { selection in
              Button(action: { onNetworkChange(selection) }) {
                if selection == model.network {
                  Label(selection.displayName, systemImage: "checkmark")
                } else {
                  Text(selection.displayName)
                }
              }
            }
          } label: {
            ChipLabel(text: model.network.displayName, isInteractive: true)
          }
        } else {
          ChipLabel(text: model.network.displayName, isInteractive: false)
        }

        // Scope chip (read-only)
        ChipLabel(text: model.scope.displayName, isInteractive: false)

        // Sort chip (tappable menu, only for post scope)
        if model.scope == .posts {
          if let onSortChange {
            Menu {
              ForEach([SearchSort.latest, .top], id: \.self) { sort in
                Button(action: { onSortChange(sort) }) {
                  if sort == model.sort {
                    Label(sort.displayName, systemImage: "checkmark")
                  } else {
                    Text(sort.displayName)
                  }
                }
              }
            } label: {
              ChipLabel(
                text: model.sort?.displayName ?? "Latest",
                isInteractive: true
              )
            }
          }
        }

        // Instance index chip with info (Mastodon)
        if let instanceDomain = model.instanceDomain {
          HStack(spacing: 4) {
            ChipLabel(text: "\(instanceDomain) index", isInteractive: false)

            if model.showInstanceInfo {
              Button(action: {
                showInstanceInfo.toggle()
              }) {
                Image(systemName: "info.circle")
                  .font(.caption)
                  .foregroundColor(.secondary)
              }
            }
          }
        }
      }
      .padding(.horizontal)
    }
    .sheet(isPresented: $showInstanceInfo) {
      InstanceInfoSheet(instanceDomain: model.instanceDomain ?? "")
    }
  }
}

private struct ChipLabel: View {
  let text: String
  let isInteractive: Bool

  var body: some View {
    HStack(spacing: 4) {
      Text(text)
        .font(.caption.weight(isInteractive ? .semibold : .regular))
      if isInteractive {
        Image(systemName: "chevron.down")
          .font(.system(size: 8, weight: .bold))
      }
    }
    .foregroundColor(isInteractive ? .primary.opacity(0.85) : .primary.opacity(0.6))
    .padding(.horizontal, 12)
    .padding(.vertical, 6)
    .background(
      Capsule(style: .continuous)
        .fill(isInteractive ? Color(.systemGray5) : Color(.systemGray6))
        .overlay(
          Capsule(style: .continuous)
            .strokeBorder(
              isInteractive ? Color.primary.opacity(0.08) : Color.clear,
              lineWidth: 0.5
            )
        )
    )
  }
}

private struct InstanceInfoSheet: View {
  let instanceDomain: String
  @Environment(\.dismiss) var dismiss
  
  var body: some View {
    NavigationView {
      VStack(alignment: .leading, spacing: 16) {
        Text("Search Limitations")
          .font(.headline)
        
        Text("This Mastodon instance (\(instanceDomain)) may not support full-text post search. You can still search for accounts and hashtags.")
          .font(.body)
          .foregroundColor(.secondary)
        
        Spacer()
      }
      .padding()
      .navigationTitle("Instance Search Info")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .navigationBarTrailing) {
          Button("Done") {
            dismiss()
          }
        }
      }
    }
  }
}
