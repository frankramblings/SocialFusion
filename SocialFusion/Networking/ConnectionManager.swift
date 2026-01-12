import Foundation
import UIKit

/// A manager class to handle API connections with proper retry, timeout and concurrency control
class ConnectionManager {
    static let shared = ConnectionManager()

    // Track active requests and connections
    private var activeConnections = 0
    private var queue = [() -> Void]()
    private var pendingRequests = [URLRequest: URLSessionTask]()
    private var completedRequestHashes = Set<Int>()
    private let serialQueue = DispatchQueue(label: "com.socialfusion.connectionmanager")

    // Session configuration
    private let session: URLSession

    // Track background tasks
    private var backgroundTaskIdentifier: UIBackgroundTaskIdentifier = .invalid

    private init() {
        // Create a custom URL session configuration
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = NetworkConfig.defaultRequestTimeout
        config.timeoutIntervalForResource = NetworkConfig.defaultRequestTimeout * 2
        config.waitsForConnectivity = true
        config.httpMaximumConnectionsPerHost = NetworkConfig.maxConcurrentConnections
        config.httpShouldSetCookies = true
        config.httpCookieAcceptPolicy = .always
        config.httpAdditionalHeaders = NetworkConfig.commonHeaders

        // Create session
        session = URLSession(configuration: config)

        // Register for app state notifications
        setupNotifications()
    }

    private func setupNotifications() {
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

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillTerminate),
            name: UIApplication.willTerminateNotification,
            object: nil
        )
    }

    // MARK: - Public API

    /// Perform a network request with proper queue management
    func performRequest(request: @escaping () -> Void) {
        serialQueue.async { [weak self] in
            guard let self = self else { return }

            if self.activeConnections < NetworkConfig.maxConcurrentConnections {
                self.activeConnections += 1
                DispatchQueue.main.async {
                    request()
                }
            } else {
                self.queue.append(request)
            }
        }
    }

    /// Sends a URLRequest and handles errors in a standardized way
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let finalRequest = prepareRequest(request)
        let requestHash = finalRequest.hashValue

        // Check for duplicates
        if completedRequestHashes.contains(requestHash) {
            throw NetworkError.duplicateRequest
        }

        // Check if URL is allowed
        guard let url = finalRequest.url,
            NetworkConfig.shouldAllowRequest(for: url)
        else {
            throw NetworkError.invalidURL
        }

        do {
            let (data, response) = try await sendWithRetries(
                finalRequest, maxRetries: NetworkConfig.maxRetryAttempts)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw NetworkError.unsupportedResponse
            }

            // Check for HTTP error codes
            guard (200...299).contains(httpResponse.statusCode) else {
                throw NetworkError.from(error: nil, response: httpResponse)
            }

            // Track successful completion
            markRequestCompleted(finalRequest, requestHash: requestHash)

            return (data, httpResponse)
        } catch {
            // Convert to standard NetworkError
            if let networkError = error as? NetworkError {
                throw networkError
            } else {
                throw NetworkError.from(error: error, response: nil)
            }
        }
    }

    /// Sends a URLRequest and automatically decodes the response to a Decodable type
    func sendRequest<T: Decodable>(
        _ request: URLRequest,
        responseType: T.Type
    ) async throws -> T {
        do {
            let (data, _) = try await send(request)

            // Attempt decoding with our standard decoder
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            decoder.dateDecodingStrategy = .iso8601

            do {
                return try decoder.decode(responseType, from: data)
            } catch {
                print("Decoding error: \(error)")
                if let dataString = String(data: data, encoding: .utf8)?.prefix(200) {
                    print("Response prefix: \(dataString)...")
                }
                throw NetworkError.decodingError
            }
        } catch {
            throw error  // Already converted to NetworkError in send method
        }
    }

    /// Called when a request completes to start the next one
    func requestCompleted() {
        serialQueue.async { [weak self] in
            guard let self = self else { return }

            self.activeConnections -= 1

            if !self.queue.isEmpty
                && self.activeConnections < NetworkConfig.maxConcurrentConnections
            {
                let nextRequest = self.queue.removeFirst()
                self.activeConnections += 1
                DispatchQueue.main.async {
                    nextRequest()
                }
            }

            // End background task if no active connections and no queued requests
            if self.activeConnections == 0 && self.queue.isEmpty {
                self.endBackgroundTaskIfNeeded()
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

            // End any background task
            self.endBackgroundTaskIfNeeded()
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

    // MARK: - Private Helper Methods

    /// Prepare request by setting common headers and configs if not already set
    private func prepareRequest(_ request: URLRequest) -> URLRequest {
        var finalRequest = request

        // Set timeout if not already set
        if finalRequest.timeoutInterval == 60 {  // Default URLRequest timeout
            finalRequest.timeoutInterval = NetworkConfig.defaultRequestTimeout
        }

        // Add common headers if not present
        for (header, value) in NetworkConfig.commonHeaders {
            if finalRequest.value(forHTTPHeaderField: header) == nil {
                finalRequest.setValue(value, forHTTPHeaderField: header)
            }
        }

        return finalRequest
    }

    /// Retry logic for network requests
    private func sendWithRetries(_ request: URLRequest, maxRetries: Int, attempt: Int = 0)
        async throws -> (Data, URLResponse)
    {
        do {
            return try await session.data(for: request)
        } catch {
            // Check if we should retry
            let networkError = NetworkError.from(error: error, response: nil)

            if networkError.isRetriable && attempt < maxRetries {
                // Calculate exponential backoff delay
                let delay =
                    NetworkConfig.retryDelay
                    * pow(NetworkConfig.exponentialBackoffMultiplier, Double(attempt))

                // Pause before retry
                try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))

                // Try again with incremented attempt count
                return try await sendWithRetries(
                    request, maxRetries: maxRetries, attempt: attempt + 1)
            } else {
                throw networkError
            }
        }
    }

    /// Track completed requests to avoid duplicates
    private func markRequestCompleted(_ request: URLRequest, requestHash: Int) {
        serialQueue.async { [weak self] in
            guard let self = self else { return }

            // Remove from pending requests
            self.pendingRequests[request] = nil

            // Add to completed hashes
            self.completedRequestHashes.insert(requestHash)

            // Clean up old completed hashes if needed
            if self.completedRequestHashes.count > 100 {
                self.completedRequestHashes = Set(self.completedRequestHashes.suffix(50))
            }

            // Signal completion to process next request
            self.requestCompleted()
        }
    }

    // MARK: - Background Task Management

    /// Begin a background task when needed
    private func beginBackgroundTaskIfNeeded() {
        if backgroundTaskIdentifier == .invalid {
            backgroundTaskIdentifier = UIApplication.shared.beginBackgroundTask { [weak self] in
                self?.endBackgroundTaskIfNeeded()
            }
        }
    }

    /// End background task when finished
    private func endBackgroundTaskIfNeeded() {
        if backgroundTaskIdentifier != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTaskIdentifier)
            backgroundTaskIdentifier = .invalid
        }
    }

    // MARK: - App State Handling

    @objc private func appDidEnterBackground() {
        // Begin background task for critical network operations
        beginBackgroundTaskIfNeeded()

        // Cancel low-priority requests to conserve resources
        serialQueue.async {
            // For now we don't have priority system, so we keep all requests
            // In a more sophisticated implementation, we could cancel non-essential requests here
        }
    }

    @objc private func appWillEnterForeground() {
        // End background task if we had one
        endBackgroundTaskIfNeeded()
    }

    @objc private func appWillTerminate() {
        // Cancel all pending requests
        cancelAllRequests()
    }
}
