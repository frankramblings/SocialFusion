import Foundation

/// Limits concurrent network requests
class ConnectionManager {
    static let shared = ConnectionManager()
    private let maxConcurrentConnections = 4
    private var activeConnections = 0
    private var queue = [() -> Void]()
    private let serialQueue = DispatchQueue(label: "com.socialfusion.connectionmanager")

    private init() {}

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

    func cancelAllRequests() {
        serialQueue.async { [weak self] in
            guard let self = self else { return }
            self.queue.removeAll()
        }
    }
}
