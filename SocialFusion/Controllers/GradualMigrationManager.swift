import Combine
import Foundation
import SwiftUI
import UIKit

/// Manages gradual migration to the new architecture with monitoring and rollback capabilities
@MainActor
class GradualMigrationManager: ObservableObject {
    static let shared = GradualMigrationManager()

    // MARK: - Published Properties

    @Published var migrationPhase: MigrationPhase = .preparation
    @Published var isNewArchitectureEnabled: Bool = true  // TEMPORARILY ENABLED - Test new timeline
    @Published var migrationProgress: Double = 0.0
    @Published var performanceMetrics: PerformanceMetrics = PerformanceMetrics()
    @Published var errorLog: [MigrationError] = []

    // MARK: - Private Properties

    private let userDefaults = UserDefaults.standard
    private var performanceTimer: Timer?
    private var migrationStartTime: Date?
    private var cancellables = Set<AnyCancellable>()

    // Keys for UserDefaults
    private let kMigrationPhaseKey = "SocialFusion.MigrationPhase"
    private let kNewArchitectureEnabledKey = "SocialFusion.NewArchitectureEnabled"
    private let kMigrationMetricsKey = "SocialFusion.MigrationMetrics"
    private let kUserGroupKey = "SocialFusion.UserGroup"

    private init() {
        loadSavedState()
        setupPerformanceMonitoring()
    }

    // MARK: - Migration Phases

    enum MigrationPhase: String, CaseIterable {
        case preparation = "preparation"
        case testing = "testing"
        case pilotGroup = "pilotGroup"  // 10% of users
        case smallRollout = "smallRollout"  // 25% of users
        case majorRollout = "majorRollout"  // 75% of users
        case fullRollout = "fullRollout"  // 100% of users
        case completed = "completed"

        var description: String {
            switch self {
            case .preparation: return "Preparing new architecture"
            case .testing: return "Internal testing phase"
            case .pilotGroup: return "Pilot group (10% users)"
            case .smallRollout: return "Small rollout (25% users)"
            case .majorRollout: return "Major rollout (75% users)"
            case .fullRollout: return "Full rollout (100% users)"
            case .completed: return "Migration completed"
            }
        }

        var rolloutPercentage: Double {
            switch self {
            case .preparation, .testing: return 0.0
            case .pilotGroup: return 0.1
            case .smallRollout: return 0.25
            case .majorRollout: return 0.75
            case .fullRollout, .completed: return 1.0
            }
        }
    }

    // MARK: - User Groups

    enum UserGroup: String {
        case control = "control"  // Old architecture
        case treatment = "treatment"  // New architecture
        case developer = "developer"  // Always new architecture for testing
    }

    // MARK: - Performance Metrics

    struct PerformanceMetrics: Codable {
        var positionRestorationSuccessRate: Double = 0.0
        var averageRestorationTime: Double = 0.0
        var memoryUsageMB: Double = 0.0
        var crashCount: Int = 0
        var scrollPerformanceScore: Double = 0.0
        var userSatisfactionScore: Double = 0.0
        var totalSessions: Int = 0
        var successfulRestores: Int = 0
        var failedRestores: Int = 0

        mutating func recordPositionRestore(success: Bool, timeSeconds: Double) {
            totalSessions += 1
            if success {
                successfulRestores += 1
                averageRestorationTime =
                    (averageRestorationTime * Double(successfulRestores - 1) + timeSeconds)
                    / Double(successfulRestores)
            } else {
                failedRestores += 1
            }
            positionRestorationSuccessRate = Double(successfulRestores) / Double(totalSessions)
        }

        var summary: String {
            return """
                Success Rate: \(String(format: "%.1f", positionRestorationSuccessRate * 100))%
                Avg Restore Time: \(String(format: "%.2f", averageRestorationTime))s
                Memory Usage: \(String(format: "%.1f", memoryUsageMB))MB
                Sessions: \(totalSessions) (\(successfulRestores) success, \(failedRestores) failed)
                """
        }
    }

    // MARK: - Migration Error

    struct MigrationError: Identifiable, Codable {
        let id = UUID()
        let timestamp: Date
        let phase: String
        let error: String
        let details: String
        let severity: Severity

        enum Severity: String, Codable {
            case low, medium, high, critical
        }
    }

    // MARK: - Public Interface

    /// Determine if user should see new architecture based on current phase and user group
    func shouldUseNewArchitecture() -> Bool {
        // Developer override
        if isDeveloperMode() {
            return true
        }

        // Check if explicitly disabled
        if !isNewArchitectureEnabled {
            return false
        }

        // Determine based on migration phase and user group
        let userGroup = getUserGroup()
        let rolloutPercentage = migrationPhase.rolloutPercentage

        switch userGroup {
        case .developer:
            return true
        case .treatment:
            return migrationPhase != .preparation
        case .control:
            return rolloutPercentage >= 1.0  // Only in full rollout
        }
    }

    /// Start migration to next phase
    func proceedToNextPhase() {
        guard let nextPhase = getNextPhase() else {
            print("📊 [Migration] Already at final phase: \(migrationPhase)")
            return
        }

        print("📊 [Migration] Proceeding from \(migrationPhase) to \(nextPhase)")

        migrationPhase = nextPhase
        migrationProgress =
            Double(MigrationPhase.allCases.firstIndex(of: migrationPhase) ?? 0)
            / Double(MigrationPhase.allCases.count - 1)

        saveState()
        logMigrationEvent("Phase transition to \(nextPhase)")
    }

    /// Rollback to previous phase if issues detected
    func rollbackToPreviousPhase(reason: String) {
        guard let previousPhase = getPreviousPhase() else {
            print("📊 [Migration] Cannot rollback from \(migrationPhase)")
            return
        }

        print(
            "📊 [Migration] Rolling back from \(migrationPhase) to \(previousPhase) - Reason: \(reason)"
        )

        migrationPhase = previousPhase
        migrationProgress =
            Double(MigrationPhase.allCases.firstIndex(of: migrationPhase) ?? 0)
            / Double(MigrationPhase.allCases.count - 1)

        recordError(
            phase: migrationPhase.rawValue, error: "Rollback triggered", details: reason,
            severity: .high)
        saveState()
    }

    /// Record position restoration attempt
    func recordPositionRestoration(success: Bool, timeSeconds: Double) {
        performanceMetrics.recordPositionRestore(success: success, timeSeconds: timeSeconds)
        saveMetrics()

        print(
            "📊 [Migration] Position restore: \(success ? "SUCCESS" : "FAILED") in \(String(format: "%.2f", timeSeconds))s"
        )

        // Auto-rollback if success rate drops below 50%
        if performanceMetrics.totalSessions >= 10
            && performanceMetrics.positionRestorationSuccessRate < 0.5
        {
            rollbackToPreviousPhase(
                reason:
                    "Success rate below 50%: \(String(format: "%.1f", performanceMetrics.positionRestorationSuccessRate * 100))%"
            )
        }
    }

    /// Record memory usage
    func updateMemoryUsage(_ memoryMB: Double) {
        performanceMetrics.memoryUsageMB = memoryMB

        // Auto-rollback if memory usage is excessive (>200MB increase)
        if memoryMB > 200.0 {
            rollbackToPreviousPhase(
                reason: "Excessive memory usage: \(String(format: "%.1f", memoryMB))MB")
        }
    }

    /// Record error
    func recordError(
        phase: String, error: String, details: String, severity: MigrationError.Severity
    ) {
        let migrationError = MigrationError(
            timestamp: Date(), phase: phase, error: error, details: details, severity: severity)
        errorLog.append(migrationError)

        // Keep only last 50 errors
        if errorLog.count > 50 {
            errorLog.removeFirst(errorLog.count - 50)
        }

        print("📊 [Migration] Error recorded: \(error) - \(details)")

        // Auto-rollback on critical errors
        if severity == .critical {
            rollbackToPreviousPhase(reason: "Critical error: \(error)")
        }
    }

    /// Enable new architecture for testing
    func enableNewArchitectureForTesting() {
        isNewArchitectureEnabled = true
        migrationPhase = .testing
        saveState()
        logMigrationEvent("New architecture enabled for testing")
    }

    /// Disable new architecture (emergency rollback)
    func disableNewArchitecture(reason: String) {
        isNewArchitectureEnabled = false
        saveState()
        recordError(
            phase: migrationPhase.rawValue, error: "Architecture disabled", details: reason,
            severity: .critical)
        print("📊 [Migration] New architecture DISABLED - Reason: \(reason)")
    }

    // MARK: - Private Methods

    private func loadSavedState() {
        if let phaseString = userDefaults.string(forKey: kMigrationPhaseKey),
            let phase = MigrationPhase(rawValue: phaseString)
        {
            migrationPhase = phase
        }

        isNewArchitectureEnabled = userDefaults.bool(forKey: kNewArchitectureEnabledKey)

        if let metricsData = userDefaults.data(forKey: kMigrationMetricsKey),
            let metrics = try? JSONDecoder().decode(PerformanceMetrics.self, from: metricsData)
        {
            performanceMetrics = metrics
        }

        migrationProgress =
            Double(MigrationPhase.allCases.firstIndex(of: migrationPhase) ?? 0)
            / Double(MigrationPhase.allCases.count - 1)
    }

    private func saveState() {
        userDefaults.set(migrationPhase.rawValue, forKey: kMigrationPhaseKey)
        userDefaults.set(isNewArchitectureEnabled, forKey: kNewArchitectureEnabledKey)
    }

    private func saveMetrics() {
        if let metricsData = try? JSONEncoder().encode(performanceMetrics) {
            userDefaults.set(metricsData, forKey: kMigrationMetricsKey)
        }
    }

    private func getUserGroup() -> UserGroup {
        if isDeveloperMode() {
            return .developer
        }

        // Get or assign user group based on device ID hash
        if let savedGroup = userDefaults.string(forKey: kUserGroupKey),
            let group = UserGroup(rawValue: savedGroup)
        {
            return group
        }

        // Assign new user to group based on hash of device ID
        let deviceID = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        let hash = abs(deviceID.hashValue)
        let group: UserGroup = (hash % 2 == 0) ? .control : .treatment

        userDefaults.set(group.rawValue, forKey: kUserGroupKey)
        return group
    }

    private func isDeveloperMode() -> Bool {
        #if DEBUG
            return true
        #else
            return userDefaults.bool(forKey: "DeveloperModeEnabled")
        #endif
    }

    private func getNextPhase() -> MigrationPhase? {
        guard let currentIndex = MigrationPhase.allCases.firstIndex(of: migrationPhase),
            currentIndex < MigrationPhase.allCases.count - 1
        else {
            return nil
        }
        return MigrationPhase.allCases[currentIndex + 1]
    }

    private func getPreviousPhase() -> MigrationPhase? {
        guard let currentIndex = MigrationPhase.allCases.firstIndex(of: migrationPhase),
            currentIndex > 0
        else {
            return nil
        }
        return MigrationPhase.allCases[currentIndex - 1]
    }

    private func setupPerformanceMonitoring() {
        // Monitor memory usage every 30 seconds
        performanceTimer = Timer.scheduledTimer(withTimeInterval: 30.0, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                self?.updateMemoryMetrics()
            }
        }
    }

    private func updateMemoryMetrics() {
        let memoryUsage = getMemoryUsage()
        updateMemoryUsage(memoryUsage)
    }

    private func getMemoryUsage() -> Double {
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
            return Double(info.resident_size) / 1024.0 / 1024.0  // Convert to MB
        }
        return 0.0
    }

    private func logMigrationEvent(_ event: String) {
        print("📊 [Migration] \(event) at \(Date())")
        // Here you could send to analytics service
    }
}
