import SwiftUI

/// A view that displays a formatted timestamp
struct PostTimestamp: View {
    let date: Date
    let style: TimestampStyle
    
    enum TimestampStyle {
        case relative
        case absolute
        case compact
    }
    
    var body: some View {
        Text(formattedDate)
            .font(.subheadline)
            .foregroundColor(.secondary)
    }
    
    private var formattedDate: String {
        switch style {
        case .relative:
            return formatRelativeDate()
        case .absolute:
            return formatAbsoluteDate()
        case .compact:
            return formatCompactDate()
        }
    }
    
    private func formatRelativeDate() -> String {
        date.relativeTimeString
    }
    
    private func formatAbsoluteDate() -> String {
        SharedFormatters.detailedDateTime.string(from: date)
    }

    private func formatCompactDate() -> String {
        // Locale-aware "MMM d" — picks the right glyph order for
        // the user's locale (e.g. '4 Mar' for en-GB instead of
        // 'Mar 4'). The previous hard-coded "MMM d" was English-only.
        SharedFormatters.compactMonthDay.string(from: date)
    }
}

// MARK: - Preview
struct PostTimestamp_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 16) {
            // Recent timestamp
            PostTimestamp(
                date: Date().addingTimeInterval(-300), // 5 minutes ago
                style: .relative
            )
            
            // Older timestamp
            PostTimestamp(
                date: Date().addingTimeInterval(-86400), // 1 day ago
                style: .relative
            )
            
            // Absolute timestamp
            PostTimestamp(
                date: Date(),
                style: .absolute
            )
            
            // Compact timestamp
            PostTimestamp(
                date: Date(),
                style: .compact
            )
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
