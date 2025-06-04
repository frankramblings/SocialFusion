import Combine
import XCTest

@testable import SocialFusion

final class MonitoringServiceTests: XCTestCase {
    var monitoringService: MonitoringService!
    var cancellables: Set<AnyCancellable>!

    override func setUp() {
        super.setUp()
        monitoringService = MonitoringService.shared
        cancellables = Set<AnyCancellable>()
        monitoringService.clearMetrics()
    }

    override func tearDown() {
        monitoringService.stopMonitoring()
        monitoringService.clearMetrics()
        cancellables.removeAll()
        super.tearDown()
    }

    // MARK: - Error Rate Tests

    func testErrorTracking() {
        // Track some errors
        monitoringService.trackError()
        monitoringService.trackError()
        monitoringService.trackError()

        // Verify error rate
        XCTAssertEqual(monitoringService.currentErrorRate, 3.0)
    }

    func testErrorRateDecay() {
        // Track some errors
        monitoringService.trackError()
        monitoringService.trackError()

        // Wait for more than a minute
        let expectation = expectation(description: "Wait for error rate decay")
        DispatchQueue.main.asyncAfter(deadline: .now() + 61) {
            expectation.fulfill()
        }

        waitForExpectations(timeout: 65)

        // Error rate should be 0 after a minute
        XCTAssertEqual(monitoringService.currentErrorRate, 0.0)
    }

    // MARK: - Response Time Tests

    func testResponseTimeTracking() {
        // Track some response times
        monitoringService.trackResponseTime("test_operation", duration: 0.1)
        monitoringService.trackResponseTime("test_operation", duration: 0.2)
        monitoringService.trackResponseTime("test_operation", duration: 0.3)

        // Verify average response time (in milliseconds)
        XCTAssertEqual(monitoringService.averageResponseTime, 200.0, accuracy: 0.1)
    }

    func testResponseTimeLimit() {
        // Add more than 1000 response times
        for i in 0..<1100 {
            monitoringService.trackResponseTime("test_operation", duration: Double(i) / 1000.0)
        }

        // Get metrics
        let metrics = monitoringService.getMetrics()
        if let responseTimes = metrics["responseTimes"] as? [String: [TimeInterval]],
            let times = responseTimes["test_operation"]
        {
            XCTAssertLessThanOrEqual(times.count, 1000)
            XCTAssertEqual(times.count, 1000)
        } else {
            XCTFail("Failed to get response times from metrics")
        }
    }

    // MARK: - Metrics Tests

    func testGetMetrics() {
        // Add some test data
        monitoringService.trackError()
        monitoringService.trackResponseTime("test_operation", duration: 0.1)

        // Get metrics
        let metrics = monitoringService.getMetrics()

        // Verify metrics structure
        XCTAssertNotNil(metrics["errorRate"])
        XCTAssertNotNil(metrics["averageResponseTime"])
        XCTAssertNotNil(metrics["memoryUsage"])
        XCTAssertNotNil(metrics["cpuUsage"])
        XCTAssertNotNil(metrics["errorCounts"])
        XCTAssertNotNil(metrics["responseTimes"])
    }

    func testClearMetrics() {
        // Add some test data
        monitoringService.trackError()
        monitoringService.trackResponseTime("test_operation", duration: 0.1)

        // Clear metrics
        monitoringService.clearMetrics()

        // Verify everything is cleared
        XCTAssertEqual(monitoringService.currentErrorRate, 0.0)
        XCTAssertEqual(monitoringService.averageResponseTime, 0.0)
        XCTAssertEqual(monitoringService.memoryUsage, 0.0)
        XCTAssertEqual(monitoringService.cpuUsage, 0.0)

        let metrics = monitoringService.getMetrics()
        if let errorCounts = metrics["errorCounts"] as? [Date: Int] {
            XCTAssertTrue(errorCounts.isEmpty)
        }
        if let responseTimes = metrics["responseTimes"] as? [String: [TimeInterval]] {
            XCTAssertTrue(responseTimes.isEmpty)
        }
    }

    // MARK: - Monitoring Control Tests

    func testStartStopMonitoring() {
        // Start monitoring
        monitoringService.startMonitoring()

        // Verify timer is running
        XCTAssertNotNil(monitoringService.getMetrics())

        // Stop monitoring
        monitoringService.stopMonitoring()

        // Add some test data
        monitoringService.trackError()
        monitoringService.trackResponseTime("test_operation", duration: 0.1)

        // Verify metrics are still tracked even when monitoring is stopped
        XCTAssertEqual(monitoringService.currentErrorRate, 1.0)
        XCTAssertEqual(monitoringService.averageResponseTime, 100.0, accuracy: 0.1)
    }

    // MARK: - Memory and CPU Tests

    func testMemoryUsage() {
        // Memory usage should be greater than 0
        XCTAssertGreaterThan(monitoringService.memoryUsage, 0.0)
    }

    func testCPUUsage() {
        // CPU usage should be between 0 and 100
        XCTAssertGreaterThanOrEqual(monitoringService.cpuUsage, 0.0)
        XCTAssertLessThanOrEqual(monitoringService.cpuUsage, 100.0)
    }
}
