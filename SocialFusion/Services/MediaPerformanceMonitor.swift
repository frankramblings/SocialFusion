import AVFoundation
import Foundation
import SwiftUI

/// Performance monitoring service for media components
@MainActor
class MediaPerformanceMonitor: ObservableObject {
    static let shared = MediaPerformanceMonitor()

    // MARK: - Performance Metrics

    @Published private(set) var metrics: PerformanceMetrics = PerformanceMetrics()

    private var loadStartTimes: [String: Date] = [:]
    private var bufferStartTimes: [String: Date] = [:]

    private init() {
        startPerformanceTracking()
    }

    // MARK: - Performance Tracking

    func trackMediaLoadStart(url: String) {
        loadStartTimes[url] = Date()
        print("📊 [MediaPerformanceMonitor] Started loading: \(url)")
    }

    func trackMediaLoadComplete(url: String, success: Bool) {
        guard let startTime = loadStartTimes[url] else { return }

        let loadTime = Date().timeIntervalSince(startTime)
        loadStartTimes.removeValue(forKey: url)

        if success {
            metrics.successfulLoads += 1
            metrics.totalLoadTime += loadTime
            metrics.averageLoadTime = metrics.totalLoadTime / Double(metrics.successfulLoads)
        } else {
            metrics.failedLoads += 1
        }

        print(
            "📊 [MediaPerformanceMonitor] Load completed: \(url) - Success: \(success) - Time: \(String(format: "%.2f", loadTime))s"
        )
    }

    func trackBufferStart(url: String) {
        bufferStartTimes[url] = Date()
        metrics.bufferEvents += 1
    }

    func trackBufferEnd(url: String) {
        guard let startTime = bufferStartTimes[url] else { return }

        let bufferTime = Date().timeIntervalSince(startTime)
        bufferStartTimes.removeValue(forKey: url)

        metrics.totalBufferTime += bufferTime
        metrics.averageBufferTime = metrics.totalBufferTime / Double(metrics.bufferEvents)

        print(
            "📊 [MediaPerformanceMonitor] Buffer completed: \(url) - Time: \(String(format: "%.2f", bufferTime))s"
        )
    }

    func trackMemoryUsage(_ usage: Float) {
        metrics.currentMemoryUsage = usage
        if usage > metrics.peakMemoryUsage {
            metrics.peakMemoryUsage = usage
        }
    }

    func trackPlayerCreation() {
        metrics.playersCreated += 1
    }

    func trackPlayerDestruction() {
        metrics.playersDestroyed += 1
    }

    // MARK: - Analytics

    func getPerformanceReport() -> String {
        let report = """
            📊 Media Performance Report
            ========================

            Load Statistics:
            • Successful loads: \(metrics.successfulLoads)
            • Failed loads: \(metrics.failedLoads)
            • Success rate: \(String(format: "%.1f", successRate))%
            • Average load time: \(String(format: "%.2f", metrics.averageLoadTime))s

            Buffer Statistics:
            • Buffer events: \(metrics.bufferEvents)
            • Average buffer time: \(String(format: "%.2f", metrics.averageBufferTime))s

            Memory Usage:
            • Current: \(String(format: "%.1f", metrics.currentMemoryUsage * 100))%
            • Peak: \(String(format: "%.1f", metrics.peakMemoryUsage * 100))%

            Player Management:
            • Players created: \(metrics.playersCreated)
            • Players destroyed: \(metrics.playersDestroyed)
            • Active players: \(metrics.playersCreated - metrics.playersDestroyed)
            """

        return report
    }

    private var successRate: Double {
        let total = metrics.successfulLoads + metrics.failedLoads
        return total > 0 ? (Double(metrics.successfulLoads) / Double(total)) * 100 : 0
    }

    private func startPerformanceTracking() {
        // Start periodic memory monitoring
        Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            Task { @MainActor in
                let memoryUsage = self.getCurrentMemoryUsage()
                self.trackMemoryUsage(memoryUsage)
            }
        }
    }

    private func getCurrentMemoryUsage() -> Float {
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
            let usedMemory = Float(info.resident_size) / (1024 * 1024)  // MB
            let totalMemory = Float(ProcessInfo.processInfo.physicalMemory) / (1024 * 1024)  // MB
            return usedMemory / totalMemory
        }

        return 0.0
    }

    // MARK: - Reset

    func resetMetrics() {
        metrics = PerformanceMetrics()
        loadStartTimes.removeAll()
        bufferStartTimes.removeAll()
        print("📊 [MediaPerformanceMonitor] Metrics reset")
    }
}

// MARK: - Performance Metrics Model

struct PerformanceMetrics {
    var successfulLoads: Int = 0
    var failedLoads: Int = 0
    var totalLoadTime: TimeInterval = 0
    var averageLoadTime: TimeInterval = 0

    var bufferEvents: Int = 0
    var totalBufferTime: TimeInterval = 0
    var averageBufferTime: TimeInterval = 0

    var currentMemoryUsage: Float = 0.0
    var peakMemoryUsage: Float = 0.0

    var playersCreated: Int = 0
    var playersDestroyed: Int = 0
}

// MARK: - SwiftUI Integration

struct MediaPerformanceView: View {
    @StateObject private var monitor = MediaPerformanceMonitor.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("📊 Media Performance")
                .font(.title2)
                .fontWeight(.bold)

            VStack(alignment: .leading, spacing: 8) {
                Text("Load Performance")
                    .font(.headline)

                HStack {
                    Text("Success Rate:")
                    Spacer()
                    Text("\(successRate, specifier: "%.1f")%")
                        .foregroundColor(
                            successRate > 90 ? .green : successRate > 70 ? .orange : .red)
                }

                HStack {
                    Text("Avg Load Time:")
                    Spacer()
                    Text("\(monitor.metrics.averageLoadTime, specifier: "%.2f")s")
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)

            VStack(alignment: .leading, spacing: 8) {
                Text("Memory Usage")
                    .font(.headline)

                HStack {
                    Text("Current:")
                    Spacer()
                    Text("\(monitor.metrics.currentMemoryUsage * 100, specifier: "%.1f")%")
                        .foregroundColor(monitor.metrics.currentMemoryUsage > 0.8 ? .red : .primary)
                }

                HStack {
                    Text("Peak:")
                    Spacer()
                    Text("\(monitor.metrics.peakMemoryUsage * 100, specifier: "%.1f")%")
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)

            Button("Reset Metrics") {
                monitor.resetMetrics()
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    private var successRate: Double {
        let total = monitor.metrics.successfulLoads + monitor.metrics.failedLoads
        return total > 0 ? (Double(monitor.metrics.successfulLoads) / Double(total)) * 100 : 0
    }
}

// MARK: - View Modifier

struct MediaPerformanceModifier: ViewModifier {
    let url: String?
    @StateObject private var monitor = MediaPerformanceMonitor.shared

    func body(content: Content) -> some View {
        content
            .onAppear {
                if let url = url {
                    monitor.trackMediaLoadStart(url: url)
                }
            }
    }
}

extension View {
    func trackMediaPerformance(url: String?) -> some View {
        self.modifier(MediaPerformanceModifier(url: url))
    }
}

