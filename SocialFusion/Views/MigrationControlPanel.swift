import SwiftUI

/// Control panel for managing gradual architecture migration
struct MigrationControlPanel: View {
    @StateObject private var migrationManager = GradualMigrationManager.shared
    @State private var showingRollbackAlert = false
    @State private var rollbackReason = ""
    @State private var showingErrorDetails = false
    @State private var selectedError: GradualMigrationManager.MigrationError?

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Current Status Card
                    statusCard

                    // Performance Metrics Card
                    performanceCard

                    // Migration Controls
                    controlsCard

                    // Error Log
                    errorLogCard

                    // Testing Tools
                    testingCard
                }
                .padding()
            }
            .navigationTitle("Migration Control")
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                // Refresh metrics
                await refreshMetrics()
            }
        }
        .alert("Rollback Confirmation", isPresented: $showingRollbackAlert) {
            TextField("Reason for rollback", text: $rollbackReason)
            Button("Cancel", role: .cancel) {}
            Button("Rollback", role: .destructive) {
                migrationManager.rollbackToPreviousPhase(reason: rollbackReason)
                rollbackReason = ""
            }
        } message: {
            Text("Are you sure you want to rollback to the previous migration phase?")
        }
        .sheet(item: $selectedError) { error in
            errorDetailSheet(error: error)
        }
    }

    // MARK: - Status Card

    private var statusCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Migration Status", systemImage: "arrow.triangle.branch")
                        .font(.headline)
                    Spacer()
                    Text(migrationManager.migrationPhase.description)
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(phaseColor.opacity(0.2))
                        .foregroundColor(phaseColor)
                        .cornerRadius(6)
                }

                // Progress Bar
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Progress")
                        Spacer()
                        Text("\(Int(migrationManager.migrationProgress * 100))%")
                            .font(.caption)
                            .fontWeight(.medium)
                    }

                    ProgressView(value: migrationManager.migrationProgress)
                        .progressViewStyle(LinearProgressViewStyle(tint: phaseColor))
                }

                // Architecture Status
                HStack {
                    Label("Architecture", systemImage: "cpu")
                    Spacer()
                    Text(migrationManager.shouldUseNewArchitecture() ? "New" : "Legacy")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(
                            migrationManager.shouldUseNewArchitecture() ? .green : .orange)
                }

                // Rollout Percentage
                HStack {
                    Label("Rollout", systemImage: "chart.line.uptrend.xyaxis")
                    Spacer()
                    Text(
                        "\(Int(migrationManager.migrationPhase.rolloutPercentage * 100))% of users"
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Performance Card

    private var performanceCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Performance Metrics", systemImage: "speedometer")
                    .font(.headline)

                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible()),
                    ], spacing: 12
                ) {
                    metricItem(
                        title: "Success Rate",
                        value:
                            "\(String(format: "%.1f", migrationManager.performanceMetrics.positionRestorationSuccessRate * 100))%",
                        color: successRateColor
                    )

                    metricItem(
                        title: "Avg Restore Time",
                        value:
                            "\(String(format: "%.2f", migrationManager.performanceMetrics.averageRestorationTime))s",
                        color: .blue
                    )

                    metricItem(
                        title: "Memory Usage",
                        value:
                            "\(String(format: "%.1f", migrationManager.performanceMetrics.memoryUsageMB))MB",
                        color: memoryUsageColor
                    )

                    metricItem(
                        title: "Sessions",
                        value: "\(migrationManager.performanceMetrics.totalSessions)",
                        color: .purple
                    )
                }

                // Detailed summary
                Text(migrationManager.performanceMetrics.summary)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 8)
            }
        }
    }

    // MARK: - Controls Card

    private var controlsCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Migration Controls", systemImage: "gearshape.2")
                    .font(.headline)

                VStack(spacing: 8) {
                    // Proceed to Next Phase
                    Button(action: {
                        migrationManager.proceedToNextPhase()
                    }) {
                        HStack {
                            Image(systemName: "arrow.right.circle.fill")
                            Text("Proceed to Next Phase")
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(canProceed ? Color.green : Color.gray)
                        .cornerRadius(10)
                    }
                    .disabled(!canProceed)

                    // Rollback Button
                    Button(action: {
                        showingRollbackAlert = true
                    }) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                            Text("Rollback to Previous Phase")
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(canRollback ? Color.orange : Color.gray)
                        .cornerRadius(10)
                    }
                    .disabled(!canRollback)

                    // Emergency Stop
                    Button(action: {
                        migrationManager.disableNewArchitecture(reason: "Manual emergency stop")
                    }) {
                        HStack {
                            Image(systemName: "stop.circle.fill")
                            Text("Emergency Stop")
                            Spacer()
                        }
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(10)
                    }
                }
            }
        }
    }

    // MARK: - Error Log Card

    private var errorLogCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Error Log", systemImage: "exclamationmark.triangle")
                        .font(.headline)
                    Spacer()
                    if !migrationManager.errorLog.isEmpty {
                        Text("\(migrationManager.errorLog.count) errors")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if migrationManager.errorLog.isEmpty {
                    Text("No errors recorded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .italic()
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(migrationManager.errorLog.prefix(5)) { error in
                            errorRow(error: error)
                        }

                        if migrationManager.errorLog.count > 5 {
                            Button("View All Errors") {
                                // Show full error log
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Testing Card

    private var testingCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label("Testing Tools", systemImage: "testtube.2")
                    .font(.headline)

                VStack(spacing: 8) {
                    Button("Enable Testing Mode") {
                        migrationManager.enableNewArchitectureForTesting()
                    }
                    .buttonStyle(.bordered)

                    NavigationLink("Compare Architectures") {
                        ArchitectureComparisonView()
                    }
                    .buttonStyle(.bordered)

                    NavigationLink("Run Migration Tests") {
                        MigrationTestView()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Helper Views

    private func metricItem(title: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)
        }
        .padding(12)
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }

    private func errorRow(error: GradualMigrationManager.MigrationError) -> some View {
        HStack {
            Image(systemName: errorIcon(for: error.severity))
                .foregroundColor(errorColor(for: error.severity))
                .font(.caption)

            VStack(alignment: .leading, spacing: 2) {
                Text(error.error)
                    .font(.caption)
                    .fontWeight(.medium)
                Text(DateFormatter.timeOnly.string(from: error.timestamp))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button("Details") {
                selectedError = error
            }
            .font(.caption2)
            .buttonStyle(.bordered)
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }

    private func errorDetailSheet(error: GradualMigrationManager.MigrationError) -> some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Error Details")
                        .font(.title2)
                        .fontWeight(.bold)

                    Label(error.error, systemImage: errorIcon(for: error.severity))
                        .foregroundColor(errorColor(for: error.severity))
                }

                GroupBox("Information") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Timestamp:")
                            Spacer()
                            Text(DateFormatter.longDateTime.string(from: error.timestamp))
                        }
                        HStack {
                            Text("Phase:")
                            Spacer()
                            Text(error.phase)
                        }
                        HStack {
                            Text("Severity:")
                            Spacer()
                            Text(error.severity.rawValue.capitalized)
                                .foregroundColor(errorColor(for: error.severity))
                        }
                    }
                }

                GroupBox("Details") {
                    Text(error.details)
                        .font(.body)
                }

                Spacer()
            }
            .padding()
            .navigationTitle("Error Details")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    selectedError = nil
                })
        }
    }

    // MARK: - Computed Properties

    private var phaseColor: Color {
        switch migrationManager.migrationPhase {
        case .preparation: return .gray
        case .testing: return .blue
        case .pilotGroup: return .orange
        case .smallRollout: return .yellow
        case .majorRollout: return .purple
        case .fullRollout: return .green
        case .completed: return .mint
        }
    }

    private var successRateColor: Color {
        let rate = migrationManager.performanceMetrics.positionRestorationSuccessRate
        if rate >= 0.9 { return .green }
        if rate >= 0.7 { return .orange }
        return .red
    }

    private var memoryUsageColor: Color {
        let usage = migrationManager.performanceMetrics.memoryUsageMB
        if usage <= 100 { return .green }
        if usage <= 150 { return .orange }
        return .red
    }

    private var canProceed: Bool {
        migrationManager.migrationPhase != .completed
            && migrationManager.performanceMetrics.positionRestorationSuccessRate >= 0.8
    }

    private var canRollback: Bool {
        migrationManager.migrationPhase != .preparation
    }

    // MARK: - Helper Functions

    private func errorIcon(for severity: GradualMigrationManager.MigrationError.Severity) -> String
    {
        switch severity {
        case .low: return "info.circle"
        case .medium: return "exclamationmark.triangle"
        case .high: return "exclamationmark.triangle.fill"
        case .critical: return "exclamationmark.octagon.fill"
        }
    }

    private func errorColor(for severity: GradualMigrationManager.MigrationError.Severity) -> Color
    {
        switch severity {
        case .low: return .blue
        case .medium: return .orange
        case .high: return .red
        case .critical: return .red
        }
    }

    private func refreshMetrics() async {
        // Force refresh of current metrics
        await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds
    }
}

// MARK: - Supporting Views

struct ArchitectureComparisonView: View {
    var body: some View {
        Text("Architecture Comparison View")
            .navigationTitle("Compare Architectures")
    }
}

struct MigrationTestView: View {
    var body: some View {
        Text("Migration Test View")
            .navigationTitle("Migration Tests")
    }
}

// MARK: - Date Formatters

extension DateFormatter {
    static let longDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }()
}

// MARK: - Preview

#if DEBUG
    struct MigrationControlPanel_Previews: PreviewProvider {
        static var previews: some View {
            MigrationControlPanel()
        }
    }
#endif
