import SwiftUI

/// A segmented tab bar for profile content sections with a sliding underline indicator.
/// Shadow only appears when the tab bar is pinned to the top.
struct ProfileTabBar: View {
  @Binding var selectedTab: ProfileTab
  @Namespace private var underlineNamespace
  @State private var isPinned = false

  var body: some View {
    VStack(spacing: 0) {
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

              ZStack {
                // Invisible spacer to maintain layout
                Rectangle()
                  .fill(Color.clear)
                  .frame(height: 2)

                if selectedTab == tab {
                  Rectangle()
                    .fill(Color.accentColor)
                    .frame(height: 2)
                    .matchedGeometryEffect(id: "underline", in: underlineNamespace)
                }
              }
            }
          }
          .frame(maxWidth: .infinity)
          .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
        }
      }
      .accessibilityElement(children: .contain)
      .padding(.horizontal, 16)
    }
    .background(
      GeometryReader { geo in
        Color(.systemBackground)
          .preference(
            key: TabBarPinnedKey.self,
            value: geo.frame(in: .global).minY
          )
      }
    )
    .onPreferenceChange(TabBarPinnedKey.self) { minY in
      // Tab bar is pinned when it's near the top of the screen (safe area ~59pt on modern iPhones)
      let pinned = minY < 100
      if pinned != isPinned {
        withAnimation(.easeOut(duration: 0.15)) {
          isPinned = pinned
        }
      }
    }
    .shadow(
      color: .black.opacity(isPinned ? 0.08 : 0),
      radius: isPinned ? 4 : 0,
      y: isPinned ? 2 : 0
    )
  }
}

private struct TabBarPinnedKey: PreferenceKey {
  static var defaultValue: CGFloat = .infinity
  static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
    value = min(value, nextValue())
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
