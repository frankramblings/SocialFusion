import SwiftUI

struct NavBarPillSelector<LeadingContent: View>: View {
    let title: String
    let isExpanded: Bool
    let action: () -> Void
    let leadingContent: LeadingContent?

    init(title: String, isExpanded: Bool, action: @escaping () -> Void, @ViewBuilder leadingContent: () -> LeadingContent) {
        self.title = title
        self.isExpanded = isExpanded
        self.action = action
        self.leadingContent = leadingContent()
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let leadingContent {
                    leadingContent
                }
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Image(systemName: "chevron.down")
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .rotationEffect(.degrees(isExpanded ? 180 : 0))
            }
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        Capsule()
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.05), radius: 4, x: 0, y: 1)
                    .shadow(color: .black.opacity(0.02), radius: 2, x: 0, y: 0.5)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
    let title: String
    let isSelected: Bool
    let action: () -> Void
}

struct NavBarPillDropdownSection: Identifiable {
    let id: String
    let header: String?
    let items: [NavBarPillDropdownItem]
}

struct NavBarPillDropdown: View {
    let sections: [NavBarPillDropdownSection]
    let width: CGFloat

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
                        title: item.title,
                        isSelected: item.isSelected,
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
                .fill(.ultraThinMaterial)
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
                .fill(.ultraThinMaterial)
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
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(title)
                    .font(.subheadline)
                    .foregroundColor(.primary)

                Spacer()

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}
