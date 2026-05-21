import Foundation

/// Utility for robustly parsing API date strings from Bluesky, Mastodon, etc.
struct DateParser {
    /// Attempts to parse a date string using common API formats.
    /// - Returns: The parsed Date, or nil if parsing fails.
    static func parse(_ dateString: String?) -> Date? {
        guard let dateString = dateString else { return nil }

        // Fast path: ISO 8601 with fractional seconds (the Bluesky shape).
        if let date = CachedFormatters.isoWithFractional.date(from: dateString) {
            return date
        }
        // Fast path: ISO 8601 without fractional seconds (the Mastodon shape).
        if let date = CachedFormatters.isoNoFractional.date(from: dateString) {
            return date
        }
        // Fallback: exotic formats some servers emit.
        for formatter in CachedFormatters.fallbackDateFormatters {
            if let date = formatter.date(from: dateString) {
                return date
            }
        }
        return nil
    }

    /// Cached formatter instances. DateParser.parse runs once per
    /// post / notification / chat event off the wire, so allocating
    /// fresh ISO8601DateFormatters per call meant a fresh ICU setup
    /// on every API response. ISO8601DateFormatter and DateFormatter
    /// are thread-safe for read-only parsing per Apple's docs, so
    /// one shared instance per format is the correct shape.
    ///
    /// Note: ISO8601DateFormatter is a *class* whose formatOptions
    /// is mutable. We keep one per option-set rather than mutating
    /// in-place, since mutation across threads would race.
    private enum CachedFormatters {
        static let isoWithFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [
                .withInternetDateTime,
                .withFractionalSeconds,
                .withColonSeparatorInTimeZone,
            ]
            return f
        }()

        static let isoNoFractional: ISO8601DateFormatter = {
            let f = ISO8601DateFormatter()
            f.formatOptions = [
                .withInternetDateTime,
                .withColonSeparatorInTimeZone,
            ]
            return f
        }()

        static let fallbackDateFormatters: [DateFormatter] = {
            let formats = [
                "yyyy-MM-dd'T'HH:mm:ss.SSSXXXXX",
                "yyyy-MM-dd'T'HH:mm:ssXXXXX",
                "yyyy-MM-dd'T'HH:mm:ss.SSSZ",
                "yyyy-MM-dd'T'HH:mm:ssZ",
            ]
            return formats.map { format in
                let f = DateFormatter()
                f.locale = Locale(identifier: "en_US_POSIX")
                f.dateFormat = format
                return f
            }
        }()
    }
}
