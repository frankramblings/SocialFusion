import Foundation

/// Utility for robustly parsing API date strings from Bluesky, Mastodon, etc.
struct DateParser {
    /// Attempts to parse a date string using common API formats.
    /// - Returns: The parsed Date, or nil if parsing fails.
    static func parse(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }
        // Try ISO8601DateFormatter first (handles most cases)
        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [
            .withInternetDateTime,
            .withFractionalSeconds,
            .withColonSeparatorInTimeZone,
        ]
        if let date = isoFormatter.date(from: dateString) {
            return date
        }
        // Try without fractional seconds
        isoFormatter.formatOptions = [
            .withInternetDateTime,
            .withColonSeparatorInTimeZone,
        ]
        if let date = isoFormatter.date(from: dateString) {
            return date
        }
        // Try with DateFormatter for more exotic cases
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
            "yyyy-MM-dd'T'HH:mm:ssXXXXX",
            "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
            "yyyy-MM-dd'T'HH:mm:ssZ",
        ]
        for format in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }
}
