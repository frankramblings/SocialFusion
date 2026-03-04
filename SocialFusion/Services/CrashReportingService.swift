import Foundation
import MetricKit
import os

/// Lightweight MetricKit subscriber for crash diagnostics and performance metrics.
/// Provides crash reports via Xcode Organizer and os_log without any third-party SDK.
@MainActor
final class CrashReportingService: NSObject, ObservableObject {
  static let shared = CrashReportingService()

  private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "SocialFusion",
                              category: "CrashReporting")

  private override init() {
    super.init()
    MXMetricManager.shared.add(self)
    logger.info("MetricKit crash reporting initialized")
  }

  deinit {
    MXMetricManager.shared.remove(self)
  }
}

// MARK: - MXMetricManagerSubscriber

extension CrashReportingService: MXMetricManagerSubscriber {

  nonisolated func didReceive(_ payloads: [MXMetricPayload]) {
    for payload in payloads {
      let json = payload.jsonRepresentation()
      Task { @MainActor in
        logger.info("Received MetricKit metric payload (\(json.count) bytes)")
      }
    }
  }

  nonisolated func didReceive(_ payloads: [MXDiagnosticPayload]) {
    for payload in payloads {
      if let crashes = payload.crashDiagnostics, !crashes.isEmpty {
        Task { @MainActor in
          logger.error("MetricKit received \(crashes.count) crash diagnostic(s)")
          for crash in crashes {
            logger.error("Crash: \(crash.applicationVersion) signal \(crash.signal?.description ?? "unknown")")
          }
        }
      }

      if let hangs = payload.hangDiagnostics, !hangs.isEmpty {
        Task { @MainActor in
          logger.warning("MetricKit received \(hangs.count) hang diagnostic(s)")
        }
      }

      if let diskWrites = payload.diskWriteExceptionDiagnostics, !diskWrites.isEmpty {
        Task { @MainActor in
          logger.warning("MetricKit received \(diskWrites.count) disk write exception(s)")
        }
      }
    }
  }
}
