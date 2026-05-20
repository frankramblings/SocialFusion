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
        SharedFormatters.detailedDateTime.string(from: date)
    }
}

/// Cached, thread-safe formatter instances. RelativeDateTimeFormatter
/// and DateFormatter are both expensive to instantiate — across a
/// feed full of posts each rendering its own header, we were
/// allocating one formatter per post per body re-evaluation. Holding
/// these as static lets pays the cost once.
///
/// Apple's docs confirm RelativeDateTimeFormatter and DateFormatter
/// are thread-safe for read-only use (formatting), which is all we do.
enum SharedFormatters {
    /// "5m", "2h", "1d" — for visual scanning under post timestamps.
    static let relativeAbbreviated: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f
    }()

    /// "5 minutes ago", "2 hours ago" — for VoiceOver and other
    /// accessibility surfaces where the abbreviated form sounds off.
    static let relativeFull: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    /// "Yesterday", "5 minutes ago" — uses named substitutions where
    /// the locale provides them (e.g. yesterday/tomorrow), falling
    /// back to the standard relative phrasing otherwise.
    static let relativeNamedFull: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.dateTimeStyle = .named
        f.unitsStyle = .full
        return f
    }()

    /// "Mar 4, 2026 at 3:42 PM" — for detail views and permalinks.
    static let detailedDateTime: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()
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
