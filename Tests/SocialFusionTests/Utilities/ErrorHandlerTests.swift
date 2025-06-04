import Combine
import XCTest

@testable import SocialFusion

final class ErrorHandlerTests: XCTestCase {
    var errorHandler: ErrorHandler!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        errorHandler = ErrorHandler.shared
        cancellables = Set<AnyCancellable>()
    }

    override func tearDown() {
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Error Creation Tests

    func testCreateNetworkError() {
        let error = AppError(
            type: .network,
            message: "Network error",
            isRetryable: true
        )

        XCTAssertEqual(error.type, .network)
        XCTAssertEqual(error.message, "Network error")
        XCTAssertTrue(error.isRetryable)
        XCTAssertEqual(error.severity, .high)
    }

    func testCreateAuthenticationError() {
        let error = AppError(
            type: .authentication,
            message: "Auth error",
            isRetryable: true
        )

        XCTAssertEqual(error.type, .authentication)
        XCTAssertEqual(error.message, "Auth error")
        XCTAssertTrue(error.isRetryable)
        XCTAssertEqual(error.severity, .high)
    }

    func testCreateErrorWithContext() {
        let context = ["key": "value", "source": "test"]
        let error = AppError(
            type: .data,
            message: "Data error",
            isRetryable: false,
            context: context
        )

        XCTAssertEqual(error.context, context)
        XCTAssertEqual(error.context["key"], "value")
        XCTAssertEqual(error.context["source"], "test")
    }

    // MARK: - Error Handling Tests

    func testHandleError() {
        let expectation = expectation(description: "Error published")
        let testError = AppError(type: .network, message: "Test error")

        errorHandler.errorPublisher
            .sink { error in
                XCTAssertEqual(error.message, testError.message)
                expectation.fulfill()
            }
            .store(in: &cancellables)

        errorHandler.handleError(testError)

        waitForExpectations(timeout: 1.0)
    }

    func testErrorHistory() {
        let error1 = AppError(type: .network, message: "Error 1")
        let error2 = AppError(type: .data, message: "Error 2")

        errorHandler.handleError(error1)
        errorHandler.handleError(error2)

        let history = errorHandler.errorHistory
        XCTAssertEqual(history.count, 2)
        XCTAssertEqual(history[0].message, error1.message)
        XCTAssertEqual(history[1].message, error2.message)
    }

    func testErrorHistoryLimit() {
        // Add more than maxErrorHistory errors
        for i in 0..<110 {
            let error = AppError(type: .network, message: "Error \(i)")
            errorHandler.handleError(error)
        }

        let history = errorHandler.errorHistory
        XCTAssertLessThanOrEqual(history.count, 100)
    }

    // MARK: - Error Mapping Tests

    func testMapNetworkError() {
        let networkError = NetworkError.connectionFailed
        let context = ["source": "test"]

        let appError = errorHandler.mapToAppError(networkError, context: context)

        XCTAssertEqual(appError.type, .network)
        XCTAssertTrue(appError.isRetryable)
        XCTAssertEqual(appError.context, context)
    }

    func testMapServiceError() {
        let serviceError = ServiceError.authenticationFailed
        let context = ["source": "test"]

        let appError = errorHandler.mapToAppError(serviceError, context: context)

        XCTAssertEqual(appError.type, .authentication)
        XCTAssertTrue(appError.isRetryable)
        XCTAssertEqual(appError.context, context)
    }

    // MARK: - Error Title Tests

    func testErrorTitles() {
        XCTAssertEqual(errorHandler.errorTitle(for: .network), "Connection Error")
        XCTAssertEqual(errorHandler.errorTitle(for: .authentication), "Authentication Error")
        XCTAssertEqual(errorHandler.errorTitle(for: .data), "Data Error")
        XCTAssertEqual(errorHandler.errorTitle(for: .permission), "Permission Required")
        XCTAssertEqual(errorHandler.errorTitle(for: .account), "Account Error")
        XCTAssertEqual(errorHandler.errorTitle(for: .general), "Error")
    }

    // MARK: - Codable Tests

    func testErrorCodable() {
        let originalError = AppError(
            type: .network,
            message: "Test error",
            isRetryable: true,
            context: ["key": "value"]
        )

        do {
            let encoder = JSONEncoder()
            let data = try encoder.encode(originalError)

            let decoder = JSONDecoder()
            let decodedError = try decoder.decode(AppError.self, from: data)

            XCTAssertEqual(decodedError.type, originalError.type)
            XCTAssertEqual(decodedError.message, originalError.message)
            XCTAssertEqual(decodedError.isRetryable, originalError.isRetryable)
            XCTAssertEqual(decodedError.context, originalError.context)
        } catch {
            XCTFail("Failed to encode/decode error: \(error)")
        }
    }

    // MARK: - Notification Tests

    func testErrorNotification() {
        let expectation = expectation(description: "Error notification received")
        let testError = AppError(type: .network, message: "Test error")

        NotificationCenter.default.addObserver(
            forName: .appErrorOccurred,
            object: nil,
            queue: .main
        ) { notification in
            if let error = notification.userInfo?["error"] as? AppError {
                XCTAssertEqual(error.message, testError.message)
                expectation.fulfill()
            }
        }

        errorHandler.handleError(testError)

        waitForExpectations(timeout: 1.0)
    }
}
