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
        let safeTop = geo.safeAreaInsets.top
        // Nav bar is ~44pt; pinned when tab bar's global minY is near safe area + nav bar
        let threshold = safeTop + 44 + 4  // 4pt tolerance
        Color(.systemBackground)
          .preference(
            key: TabBarPinnedKey.self,
            value: TabBarPinnedValue(minY: geo.frame(in: .global).minY, threshold: threshold)
          )
      }
    )
    .onPreferenceChange(TabBarPinnedKey.self) { value in
      let pinned = value.minY <= value.threshold
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

private struct TabBarPinnedValue: Equatable {
  let minY: CGFloat
  let threshold: CGFloat
}

private struct TabBarPinnedKey: PreferenceKey {
  static var defaultValue = TabBarPinnedValue(minY: .infinity, threshold: 100)
  static func reduce(value: inout TabBarPinnedValue, nextValue: () -> TabBarPinnedValue) {
    let next = nextValue()
    if next.minY < value.minY {
      value = next
    }
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
