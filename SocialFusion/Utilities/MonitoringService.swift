import Combine
import Foundation

/// Service for monitoring app performance and error rates
final class MonitoringService {
    static let shared = MonitoringService()

    // MARK: - Published Properties

    /// Current error rate (errors per minute)
    @Published private(set) var currentErrorRate: Double = 0

    /// Average response time in milliseconds
    @Published private(set) var averageResponseTime: Double = 0

    /// Memory usage in MB
    @Published private(set) var memoryUsage: Double = 0

    /// CPU usage percentage
    @Published private(set) var cpuUsage: Double = 0

    // MARK: - Private Properties

    private var errorCounts: [Date: Int] = [:]
    private var responseTimes: [String: [TimeInterval]] = [:]
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var events: [[String: Any]] = []

    private init() {
        setupMonitoring()
    }

    // MARK: - Public Methods

    /// Start monitoring
    func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            self?.updateMetrics()
        }
        timer?.fire()
    }

    /// Stop monitoring
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    /// Track an error occurrence
    func trackError() {
        let now = Date()
        errorCounts[now, default: 0] += 1
        updateErrorRate()
    }

    /// Track a response time for a specific operation
    func trackResponseTime(_ operation: String, duration: TimeInterval) {
        responseTimes[operation, default: []].append(duration)
        updateResponseTime()
    }

    /// Get current metrics
    func getMetrics() -> [String: Any] {
        return [
            "errorRate": currentErrorRate,
            "averageResponseTime": averageResponseTime,
            "memoryUsage": memoryUsage,
            "cpuUsage": cpuUsage,
            "errorCounts": errorCounts.mapValues { $0 },
            "responseTimes": responseTimes.mapValues { $0 },
        ]
    }

    /// Clear all metrics
    func clearMetrics() {
        errorCounts.removeAll()
        responseTimes.removeAll()
        currentErrorRate = 0
        averageResponseTime = 0
        memoryUsage = 0
        cpuUsage = 0
    }

    /// Monitor profile image loading performance
    @MainActor
    public func trackProfileImageLoad(
        url: String, platform: SocialPlatform, success: Bool, loadTime: TimeInterval? = nil
    ) {
        let event =
            [
                "type": "profile_image_load",
                "url": url,
                "platform": platform.rawValue,
                "success": success,
                "load_time": loadTime ?? 0.0,
                "timestamp": Date().timeIntervalSince1970,
            ] as [String: Any]

        events.append(event)

        if success {
            print(
                "✅ [MonitoringService] Profile image loaded: \(platform.rawValue) in \(loadTime ?? 0.0)s"
            )
        } else {
            print("❌ [MonitoringService] Profile image failed: \(platform.rawValue) - \(url)")
        }

        // Keep only recent events
        if events.count > 200 {
            events.removeFirst(50)
        }
    }

    /// Get profile image loading statistics
    @MainActor
    public func getProfileImageStats() -> [String: Any] {
        let profileEvents = events.filter { ($0["type"] as? String) == "profile_image_load" }
        let successCount = profileEvents.filter { ($0["success"] as? Bool) == true }.count
        let failureCount = profileEvents.filter { ($0["success"] as? Bool) == false }.count
        let avgLoadTime =
            profileEvents.compactMap { $0["load_time"] as? TimeInterval }.reduce(0, +)
            / Double(max(1, profileEvents.count))

        return [
            "total_loads": profileEvents.count,
            "successes": successCount,
            "failures": failureCount,
            "success_rate": successCount > 0
                ? Double(successCount) / Double(profileEvents.count) : 0.0,
            "avg_load_time": avgLoadTime,
        ]
    }

    // MARK: - Private Methods

    private func setupMonitoring() {
        // Set up memory monitoring
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.updateMemoryUsage()
        }

        // Set up CPU monitoring
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.updateCPUUsage()
        }
    }

    private func updateMetrics() {
        updateErrorRate()
        updateResponseTime()
        updateMemoryUsage()
        updateCPUUsage()
    }

    private func updateErrorRate() {
        let oneMinuteAgo = Date().addingTimeInterval(-60)
        let recentErrors = errorCounts.filter { $0.key > oneMinuteAgo }
        let totalErrors = recentErrors.values.reduce(0, +)
        currentErrorRate = Double(totalErrors)

        // Clean up old error counts
        errorCounts = recentErrors
    }

    private func updateResponseTime() {
        var totalTime: TimeInterval = 0
        var totalCount = 0

        for times in responseTimes.values {
            totalTime += times.reduce(0, +)
            totalCount += times.count
        }

        if totalCount > 0 {
            averageResponseTime = (totalTime / Double(totalCount)) * 1000  // Convert to milliseconds
        }

        // Keep only last 1000 response times per operation
        for (operation, times) in responseTimes {
            if times.count > 1000 {
                responseTimes[operation] = Array(times.suffix(1000))
            }
        }
    }

    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let kerr: kern_return_t = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(MACH_TASK_BASIC_INFO),
                    $0,
                    &count)
            }
        }

        if kerr == KERN_SUCCESS {
            memoryUsage = Double(info.resident_size) / 1024.0 / 1024.0  // Convert to MB
        }
    }

    private func updateCPUUsage() {
        var totalUsage: Double = 0
        var numCPUs: natural_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &numCPUs,
            nil,
            nil)

        if result == KERN_SUCCESS {
            var cpuInfo: processor_info_array_t?
            var numCpuInfo: mach_msg_type_number_t = 0

            let result2 = host_processor_info(
                mach_host_self(),
                PROCESSOR_CPU_LOAD_INFO,
                &numCPUs,
                &cpuInfo,
                &numCpuInfo)

            if result2 == KERN_SUCCESS {
                for i in 0..<Int(numCPUs) {
                    let user = Double(cpuInfo![Int(CPU_STATE_USER) + i * Int(CPU_STATE_MAX)])
                    let system = Double(cpuInfo![Int(CPU_STATE_SYSTEM) + i * Int(CPU_STATE_MAX)])
                    let idle = Double(cpuInfo![Int(CPU_STATE_IDLE) + i * Int(CPU_STATE_MAX)])
                    let total = user + system + idle

                    if total > 0 {
                        totalUsage += (user + system) / total
                    }
                }

                cpuUsage = (totalUsage / Double(numCPUs)) * 100.0
            }

            if let cpuInfo = cpuInfo {
                vm_deallocate(
                    mach_task_self_,
                    vm_address_t(bitPattern: cpuInfo),
                    vm_size_t(numCpuInfo * Int32(MemoryLayout<integer_t>.stride)))
            }
        }
    }
}

// MARK: - SwiftUI View Extension

extension View {
    /// Monitor view performance
    func monitorPerformance(_ operation: String) -> some View {
        let startTime = Date()
        return self.onAppear {
            let duration = Date().timeIntervalSince(startTime)
            MonitoringService.shared.trackResponseTime(operation, duration: duration)
        }
    }
}
