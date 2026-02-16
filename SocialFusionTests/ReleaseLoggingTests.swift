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

  /// Ensure cancellations are not logged as generic timeline fetch errors.
  func testTimelineCancellationIsNotLoggedAsGenericError() {
    let file = "SocialFusion/Services/BlueskyService.swift"
    let path = (sourceRoot as NSString).appendingPathComponent(file)
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
      XCTFail("Could not read \(file)")
      return
    }

    XCTAssertFalse(
      content.contains("logger.error(\"Error fetching Bluesky timeline: \\(error.localizedDescription)\")"),
      "Cancelled timeline requests should not be reported with generic error logging"
    )
  }

  /// Ensure timeout/slow LP logs only emit for actual fallback paths.
  func testLinkPreviewTimeoutAndSlowLogsAreGuardedByFallbackCondition() {
    let file = "SocialFusion/Views/Components/StabilizedLinkPreview.swift"
    let path = (sourceRoot as NSString).appendingPathComponent(file)
    guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
      XCTFail("Could not read \(file)")
      return
    }

    let timeoutPattern = #"if\s*!serverFieldsExist\s*\{[\s\S]*?\[LinkPreview\] TIMEOUT"#
    let slowPattern = #"if\s*!serverFieldsExist\s*\{[\s\S]*?\[LinkPreview\] SLOW"#

    XCTAssertTrue(
      content.range(of: timeoutPattern, options: .regularExpression) != nil,
      "TIMEOUT logs should be emitted only when server card fields are absent"
    )
    XCTAssertTrue(
      content.range(of: slowPattern, options: .regularExpression) != nil,
      "SLOW logs should be emitted only when server card fields are absent"
    )
  }

  /// Ensure timeline parsing logs that are known to be high-volume are not emitted at info/print level.
  func testNoHighVolumeTimelineParserLogs() {
    let checks: [(file: String, forbiddenPatterns: [String])] = [
      (
        file: "SocialFusion/Services/MastodonService.swift",
        forbiddenPatterns: [
          #"logger\.info\(\s*"\[Mastodon\] 🔍 Processing reblog:"#,
          #"print\(\s*"\[Mastodon\] 🔍 Processing reblog:"#,
          #"logger\.info\(\s*"\[Mastodon\] 📎 Parsed"#,
          #"print\(\s*"\[Mastodon\] 📎 Parsed"#,
          #"print\(\s*"📊 \[MastodonService\] Post"#,
        ]
      ),
      (
        file: "SocialFusion/Services/BlueskyService.swift",
        forbiddenPatterns: [
          #"logger\.info\(\s*"\[Bluesky\] 🔍 Parsing attachments from"#,
          #"print\(\s*"\[Bluesky\] 🔍 Processing embed for post"#,
          #"logger\.info\(\s*"\[Bluesky\] Processing embed for post"#,
          #"print\(\s*"🔍 \[QUOTE_DEBUG\] Found embed for post"#,
          #"logger\.info\(\s*"\[Bluesky\] 📎 Parsed"#,
        ]
      ),
    ]

    for check in checks {
      let path = (sourceRoot as NSString).appendingPathComponent(check.file)
      guard let content = try? String(contentsOfFile: path, encoding: .utf8) else {
        XCTFail("Could not read \(check.file)")
        continue
      }

      for pattern in check.forbiddenPatterns {
        XCTAssertNil(
          content.range(of: pattern, options: .regularExpression),
          "High-volume parser log should be debug-only in \(check.file). Forbidden pattern: \(pattern)"
        )
      }
    }
  }

  /// Ensure app Info.plist defines timeline configuration, so runtime avoids default-warning fallback.
  func testAppInfoPlistContainsTimelineConfiguration() throws {
    let plistPath = (sourceRoot as NSString).appendingPathComponent("SocialFusion/Info.plist")
    let data = try Data(contentsOf: URL(fileURLWithPath: plistPath))
    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(from: data, format: nil)
        as? [String: Any]
    )

    let timelineConfig = try XCTUnwrap(
      plist["SocialFusionTimelineConfiguration"] as? [String: Any],
      "Info.plist must define SocialFusionTimelineConfiguration to avoid runtime fallback warnings"
    )

    XCTAssertNotNil(timelineConfig["PositionPersistence"])
    XCTAssertNotNil(timelineConfig["TimelineCache"])
    XCTAssertNotNil(timelineConfig["Performance"])
    XCTAssertNotNil(timelineConfig["Debug"])
  }
}
