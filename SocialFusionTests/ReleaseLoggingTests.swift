import XCTest
@testable import SocialFusion

/// Scans source files for logging patterns that could leak sensitive data in release builds.
/// These tests fail if token previews or raw response body dumps are found.
final class ReleaseLoggingTests: XCTestCase {

  private let sourceRoot: String = {
    // Use #file to locate the source tree at compile time
    let thisFile = #filePath // .../SocialFusionTests/ReleaseLoggingTests.swift
    let testsDir = (thisFile as NSString).deletingLastPathComponent // .../SocialFusionTests
    return (testsDir as NSString).deletingLastPathComponent // .../SocialFusion (repo root)
  }()

  /// Verify no token prefix logging in service files.
  func testNoTokenPreviewsInServiceLogs() {
    XCTAssertFalse(sourceRoot.isEmpty, "Source root should be derived from #filePath")

    let files = [
      "SocialFusion/Services/MastodonService.swift",
      "SocialFusion/Services/BlueskyService.swift",
      "SocialFusion/Models/SocialAccount.swift",
      "SocialFusion/Services/OAuthManager.swift",
    ]

    let tokenPatterns = [
      "token.prefix(",
      "accessToken.prefix(",
      "refreshToken.prefix(",
      "Token preview:",
      "Using access token for",
      "Saved access token for",
      "Saved refresh token for",
    ]

    for file in files {
      let path = (sourceRoot as NSString).appendingPathComponent(file)
      guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        continue // File not found — skip
      }

      let lines = content.components(separatedBy: "\n")
      var inDebugBlock = false

      for (index, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Track #if DEBUG / #endif blocks
        if trimmed == "#if DEBUG" { inDebugBlock = true; continue }
        if trimmed == "#endif" { inDebugBlock = false; continue }
        if inDebugBlock { continue }
        if trimmed.hasPrefix("//") { continue }

        for pattern in tokenPatterns {
          XCTAssertFalse(
            line.contains(pattern),
            "Token preview found in \(file):\(index + 1) — '\(pattern)' must be guarded by #if DEBUG or removed"
          )
        }
      }
    }
  }

  /// Verify no unbounded raw response body dumps in service files.
  func testNoRawResponseBodyDumps() {
    XCTAssertFalse(sourceRoot.isEmpty, "Source root should be derived from #filePath")

    let files = [
      "SocialFusion/Services/MastodonService.swift",
      "SocialFusion/Services/BlueskyService.swift",
    ]

    // Patterns that dump response bodies (outside of #if DEBUG)
    let dumpPatterns = [
      "Raw response:",
      "RAW RESPONSE:",
      "Response body:",
      "response body:",
      "Raw response data:",
      "Raw search posts response:",
      "Raw response from Mastodon",
    ]

    for file in files {
      let path = (sourceRoot as NSString).appendingPathComponent(file)
      guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        continue
      }

      let lines = content.components(separatedBy: "\n")
      var inDebugBlock = false

      for (index, line) in lines.enumerated() {
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        // Track #if DEBUG / #endif blocks
        if trimmed == "#if DEBUG" { inDebugBlock = true; continue }
        if trimmed == "#endif" { inDebugBlock = false; continue }
        if inDebugBlock { continue }
        if trimmed.hasPrefix("//") { continue }

        for pattern in dumpPatterns {
          XCTAssertFalse(
            line.contains(pattern),
            "Raw response dump in \(file):\(index + 1) — '\(pattern)' must be guarded by #if DEBUG"
          )
        }
      }
    }
  }
}
