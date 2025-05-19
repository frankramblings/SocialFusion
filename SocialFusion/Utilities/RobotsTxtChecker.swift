import Foundation
import SwiftUI

/// Utility for checking robots.txt files to respect website crawling rules
final class RobotsTxtChecker {
    static let shared = RobotsTxtChecker()

    // Cache of robots.txt rules - domain: allowed paths
    private var robotsCache: [String: (allowed: [String], disallowed: [String], timestamp: Date)] =
        [:]

    // Cache expiration time (24 hours)
    private let cacheExpirationTime: TimeInterval = 86400

    private init() {}

    /// Check if crawling a URL is allowed according to the site's robots.txt
    /// - Parameters:
    ///   - url: The URL to check
    ///   - completion: Closure called with a boolean indicating if crawling is allowed
    func isAllowedToFetch(url: URL, completion: @escaping (Bool) -> Void) {
        guard let host = url.host else {
            completion(false)
            return
        }

        // Check cache first
        if let cachedRules = robotsCache[host] {
            // Check if cache is expired
            let now = Date()
            if now.timeIntervalSince(cachedRules.timestamp) <= cacheExpirationTime {
                // Use cached result
                let path = url.path

                // Check if path is explicitly disallowed
                for disallowedPath in cachedRules.disallowed {
                    if path.hasPrefix(disallowedPath) {
                        completion(false)
                        return
                    }
                }

                // If no disallow rule matches, it's allowed
                completion(true)
                return
            }
        }

        // Fetch robots.txt
        fetchRobotsTxt(for: host) { [weak self] allowed, disallowed in
            guard let self = self else {
                completion(false)
                return
            }

            // Cache the results
            self.robotsCache[host] = (allowed, disallowed, Date())

            // Check the path against the rules
            let path = url.path

            // Check if path is explicitly disallowed
            for disallowedPath in disallowed {
                if path.hasPrefix(disallowedPath) {
                    completion(false)
                    return
                }
            }

            // If no disallow rule matches, it's allowed
            completion(true)
        }
    }

    /// Fetch and parse robots.txt for a given domain
    /// - Parameters:
    ///   - host: The host domain
    ///   - completion: Closure called with parsed allow and disallow rules
    private func fetchRobotsTxt(
        for host: String, completion: @escaping ([String], [String]) -> Void
    ) {
        // Construct robots.txt URL
        let robotsUrl = URL(string: "https://\(host)/robots.txt")!

        let task = URLSession.shared.dataTask(with: robotsUrl) { data, response, error in
            // Default to permissive if there's an error or no data
            guard let data = data, error == nil,
                let httpResponse = response as? HTTPURLResponse,
                httpResponse.statusCode == 200
            else {
                completion([], [])
                return
            }

            // Parse the robots.txt
            if let content = String(data: data, encoding: .utf8) {
                let (allowed, disallowed) = self.parseRobotsTxt(content)
                completion(allowed, disallowed)
            } else {
                completion([], [])
            }
        }

        task.resume()
    }

    /// Parse robots.txt content to extract allow and disallow rules
    /// - Parameter content: The robots.txt file content
    /// - Returns: Tuple of allowed and disallowed paths
    private func parseRobotsTxt(_ content: String) -> ([String], [String]) {
        var allowed: [String] = []
        var disallowed: [String] = []

        let userAgentSections = content.components(separatedBy: "User-agent:")

        for section in userAgentSections {
            if section.contains("*") || section.lowercased().contains("socialfusion") {
                // Process this section as it applies to all user-agents or our app specifically
                let lines = section.components(separatedBy: .newlines)

                for line in lines {
                    let trimmedLine = line.trimmingCharacters(in: .whitespacesAndNewlines)

                    if trimmedLine.lowercased().hasPrefix("allow:") {
                        let path = trimmedLine.replacingOccurrences(
                            of: "Allow:", with: "", options: .caseInsensitive
                        )
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        allowed.append(path)
                    } else if trimmedLine.lowercased().hasPrefix("disallow:") {
                        let path = trimmedLine.replacingOccurrences(
                            of: "Disallow:", with: "", options: .caseInsensitive
                        )
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        disallowed.append(path)
                    }
                }
            }
        }

        return (allowed, disallowed)
    }

    /// Clear the robots.txt cache
    func clearCache() {
        robotsCache.removeAll()
    }
}
