import AVFoundation
import Foundation
import SwiftUI

/// Comprehensive error handling and retry logic for media content
@MainActor
class MediaErrorHandler: ObservableObject {
    static let shared = MediaErrorHandler()

    // MARK: - Error Types

    enum MediaError: LocalizedError, Equatable {
        case networkUnavailable
        case invalidURL(String)
        case unsupportedFormat(String)
        case loadTimeout
        case decodingFailed(String)
        case playerSetupFailed(String)
        case insufficientMemory
        case permissionDenied
        case serverError(Int)
        case unknown(String)

        var errorDescription: String? {
            switch self {
            case .networkUnavailable:
                return "No internet connection available"
            case .invalidURL(let url):
                return "Invalid media URL: \(url)"
            case .unsupportedFormat(let format):
                return "Unsupported media format: \(format)"
            case .loadTimeout:
                return "Media loading timed out"
            case .decodingFailed(let reason):
                return "Failed to decode media: \(reason)"
            case .playerSetupFailed(let reason):
                return "Player setup failed: \(reason)"
            case .insufficientMemory:
                return "Insufficient memory to load media"
            case .permissionDenied:
                return "Permission denied to access media"
            case .serverError(let code):
                return "Server error (\(code))"
            case .unknown(let message):
                return "Unknown error: \(message)"
            }
        }

        var recoverySuggestion: String? {
            switch self {
            case .networkUnavailable:
                return "Check your internet connection and try again"
            case .invalidURL:
                return "The media link appears to be broken"
            case .unsupportedFormat:
                return "This media format is not supported"
            case .loadTimeout:
                return "Try again with a better connection"
            case .decodingFailed:
                return "The media file may be corrupted"
            case .playerSetupFailed:
                return "Try restarting the app"
            case .insufficientMemory:
                return "Close other apps and try again"
            case .permissionDenied:
                return "Check app permissions in Settings"
            case .serverError:
                return "The server is temporarily unavailable"
            case .unknown:
                return "Please try again later"
            }
        }

        var isRetryable: Bool {
            switch self {
            case .networkUnavailable, .loadTimeout, .serverError, .unknown:
                return true
            case .invalidURL, .unsupportedFormat, .decodingFailed, .playerSetupFailed,
                .insufficientMemory, .permissionDenied:
                return false
            }
        }
    }

    // MARK: - Retry Configuration

    struct RetryConfig {
        let maxAttempts: Int
        let baseDelay: TimeInterval
        let maxDelay: TimeInterval
        let backoffMultiplier: Double

        static let `default` = RetryConfig(
            maxAttempts: 3,
            baseDelay: 1.0,
            maxDelay: 10.0,
            backoffMultiplier: 2.0
        )

        static let aggressive = RetryConfig(
            maxAttempts: 5,
            baseDelay: 0.5,
            maxDelay: 8.0,
            backoffMultiplier: 1.5
        )
    }

    // MARK: - State Management

    @Published private(set) var activeRetries: [String: RetryState] = [:]

    public struct RetryState {
        let url: String
        var attempts: Int = 0
        var lastError: MediaError?
        var nextRetryDate: Date?
        var isRetrying: Bool = false
    }

    private init() {}

    // MARK: - Public API

    /// Attempt to load media with automatic retry logic
    func loadMediaWithRetry<T>(
        url: URL,
        config: RetryConfig = .default,
        loader: @escaping (URL) async throws -> T
    ) async throws -> T {
        let urlString = url.absoluteString

        // Initialize retry state if needed
        if activeRetries[urlString] == nil {
            activeRetries[urlString] = RetryState(url: urlString)
        }

        var retryState = activeRetries[urlString]!

        while retryState.attempts < config.maxAttempts {
            do {
                // Clear retry state on success
                activeRetries[urlString] = nil
                return try await loader(url)

            } catch {
                retryState.attempts += 1
                let mediaError = mapError(error, for: url)
                retryState.lastError = mediaError

                print(
                    "🔄 [MediaErrorHandler] Attempt \(retryState.attempts)/\(config.maxAttempts) failed for \(url): \(mediaError.localizedDescription)"
                )

                // Don't retry if error is not retryable or we've exceeded max attempts
                if !mediaError.isRetryable || retryState.attempts >= config.maxAttempts {
                    activeRetries[urlString] = retryState
                    throw mediaError
                }

                // Calculate delay with exponential backoff
                let delay = min(
                    config.baseDelay
                        * pow(config.backoffMultiplier, Double(retryState.attempts - 1)),
                    config.maxDelay
                )

                retryState.nextRetryDate = Date().addingTimeInterval(delay)
                retryState.isRetrying = true
                activeRetries[urlString] = retryState

                print("🔄 [MediaErrorHandler] Retrying in \(String(format: "%.1f", delay))s...")

                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                retryState.isRetrying = false
                activeRetries[urlString] = retryState
            }
        }

        // This should never be reached, but just in case
        throw retryState.lastError ?? MediaError.unknown("Max retry attempts exceeded")
    }

    /// Check if a URL is currently being retried
    func isRetrying(url: String) -> Bool {
        return activeRetries[url]?.isRetrying ?? false
    }

    /// Get retry state for a URL
    func getRetryState(url: String) -> (attempts: Int, maxAttempts: Int, nextRetry: Date?)? {
        guard let state = activeRetries[url] else { return nil }
        return (state.attempts, 3, state.nextRetryDate)  // Using default max attempts
    }

    /// Cancel retry for a specific URL
    func cancelRetry(url: String) {
        activeRetries[url] = nil
    }

    /// Clear all retry states
    func clearAllRetries() {
        activeRetries.removeAll()
    }

    // MARK: - Error Mapping

    private func mapError(_ error: Error, for url: URL) -> MediaError {
        // Network errors
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return .networkUnavailable
            case .badURL:
                return .invalidURL(url.absoluteString)
            case .timedOut:
                return .loadTimeout
            case .badServerResponse:
                return .serverError(urlError.errorCode)
            case .unsupportedURL:
                return .unsupportedFormat(url.pathExtension)
            default:
                return .unknown(urlError.localizedDescription)
            }
        }

        // AVPlayer errors
        if let avError = error as? AVError {
            switch avError.code {
            case .contentIsNotAuthorized:
                return .permissionDenied
            case .contentIsUnavailable:
                return .serverError(503)
            case .mediaServicesWereReset:
                return .playerSetupFailed("Media services reset")
            case .diskFull, .outOfMemory:
                return .insufficientMemory
            case .invalidSourceMedia:
                return .unsupportedFormat("Invalid media source")
            default:
                return .unknown(avError.localizedDescription)
            }
        }
        
        // CoreMedia errors (format description errors, etc.)
        // Check for CoreMediaErrorDomain errors (e.g., -12881)
        if let nsError = error as NSError?,
           nsError.domain == "CoreMediaErrorDomain"
        {
            // Format description errors (-12881) are often retryable
            // They can occur due to timing issues with HLS segment loading
            let code = nsError.code
            if code == -12881 {
                // kCMFormatDescriptionError_InvalidParameter
                // This can happen when AVFoundation hasn't fully processed content info
                return .unknown("Format description error (code: \(code))")
            } else if code == -12783 || code == -12753 {
                // Allocation/timebase errors - often retryable
                return .unknown("Media processing error (code: \(code))")
            }
            return .unknown("CoreMedia error (code: \(code))")
        }

        // HTTP errors
        if let httpError = error as? HTTPError {
            return .serverError(httpError.statusCode)
        }

        // Generic errors
        return .unknown(error.localizedDescription)
    }

    #if DEBUG
    // Testing shim to expose private mapping for unit tests
    @usableFromInline
    internal func _test_mapError(_ error: Error, for url: URL) -> MediaError {
        return mapError(error, for: url)
    }
    #endif
}

// MARK: - HTTP Error Helper

struct HTTPError: Error {
    let statusCode: Int
    let data: Data?

    var localizedDescription: String {
        return "HTTP Error \(statusCode)"
    }
}

// MARK: - SwiftUI Integration

/// A view modifier that shows retry UI for media loading errors
struct MediaRetryModifier: ViewModifier {
    let url: String
    let onRetry: () -> Void

    @StateObject private var errorHandler = MediaErrorHandler.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .center) {
                if let retryState = errorHandler.getRetryState(url: url),
                    retryState.attempts > 0
                {
                    MediaRetryOverlay(
                        attempts: retryState.attempts,
                        maxAttempts: retryState.maxAttempts,
                        isRetrying: errorHandler.isRetrying(url: url),
                        nextRetry: retryState.nextRetry,
                        onRetry: onRetry,
                        onCancel: {
                            errorHandler.cancelRetry(url: url)
                        }
                    )
                }
            }
    }
}

private struct MediaRetryOverlay: View {
    let attempts: Int
    let maxAttempts: Int
    let isRetrying: Bool
    let nextRetry: Date?
    let onRetry: () -> Void
    let onCancel: () -> Void

    @State private var timeUntilRetry: TimeInterval = 0
    @State private var timer: Timer?

    var body: some View {
        VStack(spacing: 16) {
            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 32))
                .foregroundColor(.orange)

            // Status text
            VStack(spacing: 4) {
                Text("Loading Failed")
                    .font(.headline)
                    .fontWeight(.semibold)

                if isRetrying {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Retrying...")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Attempt \(attempts)/\(maxAttempts)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    if timeUntilRetry > 0 {
                        Text("Next retry in \(Int(timeUntilRetry))s")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            // Action buttons
            if !isRetrying {
                HStack(spacing: 12) {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(.bordered)

                    Button("Retry Now") {
                        onRetry()
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
        )
        .shadow(color: .black.opacity(0.1), radius: 8, x: 0, y: 4)
        .onAppear {
            startTimer()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }

    private func startTimer() {
        timer?.invalidate()

        guard let nextRetry = nextRetry else { return }

        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            let remaining = nextRetry.timeIntervalSinceNow
            if remaining > 0 {
                timeUntilRetry = remaining
            } else {
                timeUntilRetry = 0
                timer?.invalidate()
            }
        }
    }
}

// MARK: - View Extension

extension View {
    func mediaRetryHandler(url: String, onRetry: @escaping () -> Void) -> some View {
        self.modifier(MediaRetryModifier(url: url, onRetry: onRetry))
    }
}
