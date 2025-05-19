import Foundation

/// Utility for formatting timestamps in a consistent way throughout the app
class TimeFormatters {
    /// Shared instance of TimeFormatters
    static let shared = TimeFormatters()

    /// Returns a user-friendly relative time string (e.g., "6m", "2h", "1d")
    func relativeTimeString(from date: Date) -> String {
        let now = Date()
        let components = Calendar.current.dateComponents(
            [.year, .month, .day, .hour, .minute, .second], from: date, to: now)

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

    /// Returns a precise timestamp for posts
    func timestampWithChevron(from date: Date) -> String {
        let timeString = relativeTimeString(from: date)
        return timeString
    }

    /// Returns a detailed date format for profile views or permalinks
    func detailedDateTimeString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// Extension on Date to easily access formatted strings
extension Date {
    var relativeTimeString: String {
        return TimeFormatters.shared.relativeTimeString(from: self)
    }

    var timestampWithChevron: String {
        return TimeFormatters.shared.timestampWithChevron(from: self)
    }

    var detailedDateTimeString: String {
        return TimeFormatters.shared.detailedDateTimeString(from: self)
    }
}
