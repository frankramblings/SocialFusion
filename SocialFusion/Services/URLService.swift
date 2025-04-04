import Foundation

/// A service class for handling URL validation and normalization
class URLService {
    static let shared = URLService()

    private init() {}

    /// Validates and fixes common URL issues
    /// - Parameter urlString: The URL string to validate
    /// - Returns: A validated URL or nil if the URL is invalid and can't be fixed
    func validateURL(_ urlString: String) -> URL? {
        // First, try to create URL as-is
        guard var url = URL(string: urlString) else {
            // If initial creation fails, try percent encoding the string
            let encodedString = urlString.addingPercentEncoding(
                withAllowedCharacters: .urlQueryAllowed)
            return URL(string: encodedString ?? "")
        }

        return validateURL(url)
    }

    /// Validates and fixes common URL issues
    /// - Parameter url: The URL to validate
    /// - Returns: A validated URL
    func validateURL(_ url: URL) -> URL {
        var fixedURL = url

        // Fix URLs with missing schemes
        if url.scheme == nil {
            if let urlWithScheme = URL(string: "https://" + url.absoluteString) {
                fixedURL = urlWithScheme
            }
        }

        // Fix the "www" hostname issue
        if url.host == "www" {
            if let correctedURL = URL(string: "https://www." + (url.path.trimmingPrefix("/"))) {
                return correctedURL
            }
        }

        // Fix "www/" hostname issue
        if let host = url.host, host.contains("www/") {
            let fixedHost = host.replacingOccurrences(of: "www/", with: "www.")
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.host = fixedHost
            if let fixedURL = components?.url {
                return fixedURL
            }
        }

        return fixedURL
    }

    /// Determines if a URL needs App Transport Security exceptions
    /// - Parameter url: The URL to check
    /// - Returns: True if the URL uses HTTP and might need ATS exceptions
    func needsATSException(_ url: URL) -> Bool {
        return url.scheme?.lowercased() == "http"
    }

    /// Generates a user-friendly error message for URL loading failures
    /// - Parameter error: The error encountered
    /// - Returns: A simplified error message suitable for display to users
    func friendlyErrorMessage(for error: Error) -> String {
        let errorDescription = error.localizedDescription

        if errorDescription.contains("App Transport Security") {
            return "Site security issue"
        } else if errorDescription.contains("cancelled") {
            return "Request cancelled"
        } else if errorDescription.contains("network connection") {
            return "Network error"
        } else if errorDescription.contains("hostname could not be found") {
            return "Invalid hostname"
        } else if errorDescription.contains("timed out") {
            return "Request timed out"
        } else {
            // Truncate error message if too long
            let message = errorDescription
            return message.count > 40 ? message.prefix(40) + "..." : message
        }
    }
}
