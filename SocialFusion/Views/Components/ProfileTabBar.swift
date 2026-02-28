import SwiftUI

/// A segmented tab bar for profile content sections with an animated underline indicator.
struct ProfileTabBar: View {
  @Binding var selectedTab: ProfileTab

  var body: some View {
    HStack(spacing: 0) {
      ForEach(ProfileTab.allCases, id: \.self) { tab in
        Button {
          withAnimation(.easeInOut(duration: 0.2)) {
            selectedTab = tab
          }
        } label: {
          VStack(spacing: 6) {
            Text(tab.rawValue)
              .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
              .foregroundStyle(selectedTab == tab ? .primary : .secondary)

            Rectangle()
              .fill(selectedTab == tab ? Color.accentColor : Color.clear)
              .frame(height: 2)
          }
        }
        .frame(maxWidth: .infinity)
        .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
      }
    }
    .accessibilityElement(children: .contain)
    .padding(.horizontal, 16)
    .background(Color(.systemBackground))
  }
}

#Preview {
  struct PreviewWrapper: View {
    @State private var tab: ProfileTab = .posts

    var body: some View {
      VStack {
        ProfileTabBar(selectedTab: $tab)
        Spacer()
        Text("Selected: \(tab.rawValue)")
          .foregroundStyle(.secondary)
        Spacer()
      }
    }
  }

  return PreviewWrapper()
}
