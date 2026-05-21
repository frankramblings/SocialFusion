import SwiftUI

struct NavBarPillSelector<LeadingContent: View>: View {
    let title: String
    let isExpanded: Bool
    let action: () -> Void
    let leadingContent: LeadingContent?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(title: String, isExpanded: Bool, action: @escaping () -> Void, @ViewBuilder leadingContent: () -> LeadingContent) {
        self.title = title
        self.isExpanded = isExpanded
        self.action = action
        self.leadingContent = leadingContent()
    }

    var body: some View {
        Button {
            HapticEngine.tap.trigger()
            action()
        } label: {
            HStack(spacing: 6) {
                if let leadingContent {
                    leadingContent
                }
                Text(title)
                    .font(.subheadline.weight(.medium))
                Image(systemName: "chevron.down")
                    .font(.caption2.weight(.semibold))
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    .animation(reduceMotion ? nil : .spring(response: 0.32, dampingFraction: 0.82), value: isExpanded)
                    .accessibilityHidden(true)
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    // Solid fallback under Reduce Transparency so the
                    // pill remains a distinct shape against the
                    // navigation bar's content blur.
                    .fill(reduceTransparency
                          ? AnyShapeStyle(Color(.secondarySystemBackground))
                          : AnyShapeStyle(.ultraThinMaterial))
                    .overlay(
                        Capsule()
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 0.5)
            )
        }
        .buttonStyle(NavBarPillButtonStyle())
        .accessibilityLabel(title)
        .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint(isExpanded ? "Closes the feed picker" : "Opens the feed picker")
    }
}

/// Subtle press feedback for the nav-bar pill — a small scale-down on press.
private struct NavBarPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.88 : 1.0)
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

extension NavBarPillSelector where LeadingContent == EmptyView {
    init(title: String, isExpanded: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isExpanded = isExpanded
        self.action = action
        self.leadingContent = nil
    }
}

struct NavBarPillDropdownItem: Identifiable {
    let id: String
    let icon: String?
    let title: String
    let isSelected: Bool
    let showChevron: Bool
    let action: () -> Void

    init(id: String, icon: String? = nil, title: String, isSelected: Bool, showChevron: Bool = false, action: @escaping () -> Void) {
        self.id = id
        self.icon = icon
        self.title = title
        self.isSelected = isSelected
        self.showChevron = showChevron
        self.action = action
    }
}

struct NavBarPillDropdownSection: Identifiable {
    let id: String
    let header: String?
    let items: [NavBarPillDropdownItem]
}

struct NavBarPillDropdown: View {
    let sections: [NavBarPillDropdownSection]
    let width: CGFloat

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(sections.enumerated()), id: \.offset) { sectionIndex, section in
                if let header = section.header {
                    Text(header)
                        .font(.caption2)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                }

                ForEach(Array(section.items.enumerated()), id: \.element.id) { itemIndex, item in
                    NavBarPillDropdownRow(
                        icon: item.icon,
                        title: item.title,
                        isSelected: item.isSelected,
                        showChevron: item.showChevron,
                        action: item.action
                    )

                    if itemIndex < section.items.count - 1 {
                        Divider()
                            .padding(.horizontal, 12)
                    }
                }

                if sectionIndex < sections.count - 1 {
                    Divider()
                        .padding(.horizontal, 12)
                }
            }
        }
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                // Dropdown panel — solid fallback for Reduce Transparency
                // matches the pill above. The two surfaces need consistent
                // treatment or one looks like glass and the other like
                // a card during the same interaction.
                .fill(reduceTransparency
                      ? AnyShapeStyle(Color(.secondarySystemBackground))
                      : AnyShapeStyle(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .frame(maxHeight: 300)
    }
}

struct NavBarPillDropdownContainer<Content: View>: View {
    let width: CGFloat
    let maxHeight: CGFloat
    let content: Content

    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    init(width: CGFloat, maxHeight: CGFloat = 300, @ViewBuilder content: () -> Content) {
        self.width = width
        self.maxHeight = maxHeight
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            content
        }
        .frame(width: width)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(reduceTransparency
                      ? AnyShapeStyle(Color(.secondarySystemBackground))
                      : AnyShapeStyle(.ultraThinMaterial))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.1), radius: 12, x: 0, y: 4)
                .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 2)
        )
        .frame(maxHeight: maxHeight)
    }
}

struct NavBarPillDropdownRow: View {
    var icon: String? = nil
    let title: String
    let isSelected: Bool
    var showChevron: Bool = false
    let action: () -> Void

    var body: some View {
        Button {
            HapticEngine.selection.trigger()
            action()
        } label: {
            HStack(spacing: 10) {
                if let icon {
                    Image(icon)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 16, height: 16)
                        .foregroundColor(isSelected ? .accentColor : .primary.opacity(0.75))
                }
                Text(title)
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? .accentColor : .primary)
                    .lineLimit(1)

                Spacer()

                if showChevron {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary.opacity(0.7))
                } else if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.accentColor)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(NavBarPillRowPressStyle())
    }
}

/// Subtle background flash on press for dropdown rows — feels like a real
/// menu row, not a static button.
private struct NavBarPillRowPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                Color.primary.opacity(configuration.isPressed ? 0.06 : 0)
            )
            .animation(.interactiveSpring(response: 0.2, dampingFraction: 0.85), value: configuration.isPressed)
    }
}
