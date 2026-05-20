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
        let now = Date()
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second],
            from: date,
            to: now
        )
        
        if let year = components.year, year > 0 {
            return "\(year)y"
        } else if let month = components.month, month > 0 {
            return "\(month)mo"
        } else if let day = components.day, day > 0 {
            if day < 7 {
                return "\(day)d"
            } else {
                let week = day / 7
                return "\(week)w"
            }
        } else if let hour = components.hour, hour > 0 {
            return "\(hour)h"
        } else if let minute = components.minute, minute > 0 {
            return "\(minute)m"
        } else {
            return "now"
        }
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
