import SwiftUI

/// Chip row showing search parameters (network, scope, sort, instance info)
struct SearchChipRow: View {
  let model: SearchChipRowModel
  let onNetworkTap: (() -> Void)?
  let onSortTap: (() -> Void)?
  
  @State private var showInstanceInfo = false
  
  var body: some View {
    if model.showInstanceInfo || model.instanceDomain != nil {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          // Network chip
          Chip(
            text: model.network.displayName,
            isTappable: onNetworkTap != nil,
            action: onNetworkTap
          )
          
          // Scope chip
          Chip(text: model.scope.displayName, isTappable: false, action: nil)
          
          // Sort chip (if supported)
          if let sort = model.sort {
            Chip(
              text: sort.displayName,
              isTappable: onSortTap != nil,
              action: onSortTap
            )
          }
          
          // Instance index chip with info (Mastodon)
          if let instanceDomain = model.instanceDomain {
            HStack(spacing: 4) {
              Chip(text: "\(instanceDomain) index", isTappable: false, action: nil)
              
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
}

private struct Chip: View {
  let text: String
  let isTappable: Bool
  let action: (() -> Void)?
  
  var body: some View {
    Button(action: {
      action?()
    }) {
      Text(text)
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(.systemGray5))
        .foregroundColor(.primary)
        .cornerRadius(16)
    }
    .disabled(!isTappable || action == nil)
    .opacity(isTappable && action != nil ? 1.0 : 0.7)
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
