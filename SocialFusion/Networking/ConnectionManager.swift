import Foundation
import UIKit

/// A manager class to handle API connections with proper retry, timeout and concurrency control
class ConnectionManager {
    static let shared = ConnectionManager()

    // Configurable parameters
    private let maxConcurrentConnections = 4
    private let defaultTimeoutInterval: TimeInterval = 15.0
    private let requestRetryLimit = 2
    private let requestRetryDelay: TimeInterval = 2.0

    // Active state tracking
    private var activeConnections = 0
    private var queue = [() -> Void]()
    private var pendingRequests = [URLRequest: URLSessionTask]()
    private var completedRequestHashes = Set<Int>()
    private let serialQueue = DispatchQueue(label: "com.socialfusion.connectionmanager")

    private init() {
        // Setup background task handling
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    // MARK: - Public API

    /// Perform a network request with proper queue management
    func performRequest(request: @escaping () -> Void) {
        serialQueue.async { [weak self] in
            guard let self = self else { return }

            if self.activeConnections < self.maxConcurrentConnections {
                self.activeConnections += 1
                DispatchQueue.main.async {
                    request()
                }
            } else {
                self.queue.append(request)
            }
        }
    }

    /// Send a URLRequest with retry logic and proper connection management
    func sendRequest<T: Decodable>(
        _ request: URLRequest,
        responseType: T.Type,
        attemptNumber: Int = 0
    ) async throws -> T {
        // Generate a unique hash for this request to track it
        let requestHash = request.hashValue

        // Check if this exact request was just completed (avoid duplicates)
        if completedRequestHashes.contains(requestHash) {
            throw NetworkError.duplicateRequest
        }

        // Create a proper timeout if needed
        var finalRequest = request
        if finalRequest.timeoutInterval == 60 {  // Default URLRequest timeout
            finalRequest.timeoutInterval = defaultTimeoutInterval
        }

        // Track this request
        return try await withCheckedThrowingContinuation { continuation in
            let task = URLSession.shared.dataTask(with: finalRequest) {
                [weak self] data, response, error in
                guard let self = self else {
                    continuation.resume(throwing: NetworkError.cancelled)
                    return
                }

                // Handle request completion
                self.serialQueue.async {
                    // Remove from pending requests
                    self.pendingRequests[finalRequest] = nil

                    // Add to completed hashes (temporary cache to avoid duplicates)
                    self.completedRequestHashes.insert(requestHash)

                    // Clean up old completed hashes if needed
                    if self.completedRequestHashes.count > 100 {
                        self.completedRequestHashes.removeFirst(50)
                    }

                    // Process result
                    if let error = error {
                        // Check if we should retry
                        if attemptNumber < self.requestRetryLimit {
                            // Network error that can be retried
                            if (error as NSError).domain == NSURLErrorDomain {
                                // Wait then retry
                                DispatchQueue.global().asyncAfter(
                                    deadline: .now() + self.requestRetryDelay
                                ) {
                                    Task {
                                        do {
                                            let result = try await self.sendRequest(
                                                finalRequest,
                                                responseType: responseType,
                                                attemptNumber: attemptNumber + 1
                                            )
                                            continuation.resume(returning: result)
                                        } catch {
                                            continuation.resume(throwing: error)
                                        }
                                    }
                                }
                                return
                            }
                        }

                        // No more retries or not a retriable error
                        continuation.resume(throwing: NetworkError.requestFailed(error))
                        return
                    }

                    // Check HTTP status code
                    if let httpResponse = response as? HTTPURLResponse {
                        let statusCode = httpResponse.statusCode

                        if statusCode < 200 || statusCode >= 300 {
                            // Check if we should retry based on status code
                            if statusCode == 429 || statusCode >= 500,
                                attemptNumber < self.requestRetryLimit
                            {
                                // Server error or rate limit, retry after delay
                                DispatchQueue.global().asyncAfter(
                                    deadline: .now() + self.requestRetryDelay
                                ) {
                                    Task {
                                        do {
                                            let result = try await self.sendRequest(
                                                finalRequest,
                                                responseType: responseType,
                                                attemptNumber: attemptNumber + 1
                                            )
                                            continuation.resume(returning: result)
                                        } catch {
                                            continuation.resume(throwing: error)
                                        }
                                    }
                                }
                                return
                            }

                            // Error response with valid status code
                            continuation.resume(throwing: NetworkError.httpError(statusCode))
                            return
                        }
                    }

                    // Process successful data
                    guard let data = data else {
                        continuation.resume(throwing: NetworkError.noData)
                        return
                    }

                    // Decode the response
                    do {
                        let decoder = JSONDecoder()
                        decoder.keyDecodingStrategy = .convertFromSnakeCase
                        decoder.dateDecodingStrategy = .iso8601

                        let decoded = try decoder.decode(responseType, from: data)
                        continuation.resume(returning: decoded)
                    } catch {
                        print("Decoding error: \(error.localizedDescription)")
                        // Print the raw response for debugging
                        if let dataString = String(data: data, encoding: .utf8) {
                            print("Raw response: \(dataString.prefix(200))...")
                        }
                        continuation.resume(throwing: NetworkError.decodingError(error))
                    }
                }

                // Mark this request as completed and process next
                self.requestCompleted()
            }

            // Store task and start it
            serialQueue.async { [weak self] in
                guard let self = self else { return }
                self.pendingRequests[finalRequest] = task
                task.resume()
            }
        }
    }

    /// Called when a request completes to start the next one
    func requestCompleted() {
        serialQueue.async { [weak self] in
            guard let self = self else { return }

            self.activeConnections -= 1

            if !self.queue.isEmpty && self.activeConnections < self.maxConcurrentConnections {
                let nextRequest = self.queue.removeFirst()
                self.activeConnections += 1
                DispatchQueue.main.async {
                    nextRequest()
                }
            }
        }
    }

    /// Cancel all pending requests
    func cancelAllRequests() {
        serialQueue.async { [weak self] in
            guard let self = self else { return }

            // Cancel all pending URLSessionTasks
            for (_, task) in self.pendingRequests {
                task.cancel()
            }

            // Clear all queues
            self.pendingRequests.removeAll()
            self.queue.removeAll()
            self.activeConnections = 0
        }
    }

    /// Cancel a specific request
    func cancelRequest(matching request: URLRequest) {
        serialQueue.async { [weak self] in
            guard let self = self else { return }

            if let task = self.pendingRequests[request] {
                task.cancel()
                self.pendingRequests[request] = nil
            }
        }
    }

    // MARK: - App State Handling

    @objc private func appDidEnterBackground() {
        // Cancel non-essential requests when app goes to background
        serialQueue.async { [weak self] in
            guard let self = self else { return }

            // Keep only high-priority requests (could be implemented with a priority system)
            // For now, cancel all for simplicity
            self.cancelAllRequests()
        }
    }

    @objc private func appWillEnterForeground() {
        // Reinitialize if needed when coming back to foreground
        serialQueue.async { [weak self] in
            guard let self = self else { return }

            // Reset state
            self.activeConnections = 0
            self.completedRequestHashes.removeAll()
        }
    }
}

/// Network-related errors
enum NetworkError: Error {
    case requestFailed(Error)
    case httpError(Int)
    case noData
    case decodingError(Error)
    case invalidURL
    case cancelled
    case duplicateRequest
    case timeout
}

extension NetworkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .requestFailed(let error):
            return "Request failed: \(error.localizedDescription)"
        case .httpError(let statusCode):
            return "HTTP error: \(statusCode)"
        case .noData:
            return "No data received"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .invalidURL:
            return "Invalid URL"
        case .cancelled:
            return "Request was cancelled"
        case .duplicateRequest:
            return "Duplicate request detected"
        case .timeout:
            return "Request timed out"
        }
    }
}
