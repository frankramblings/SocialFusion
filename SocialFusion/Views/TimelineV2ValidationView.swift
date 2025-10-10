import SwiftUI

/// SwiftUI interface for Timeline v2 validation testing
/// Provides real-time progress monitoring and detailed results display
struct TimelineV2ValidationView: View {
    @StateObject private var validationRunner: TimelineV2ValidationRunner
    @Environment(\.dismiss) private var dismiss
    
    init(socialServiceManager: SocialServiceManager) {
        self._validationRunner = StateObject(wrappedValue: TimelineV2ValidationRunner(socialServiceManager: socialServiceManager))
    }
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Header Section
                    headerSection
                    
                    // Control Section
                    controlSection
                    
                    // Progress Section
                    if validationRunner.isRunning {
                        progressSection
                    }
                    
                    // Results Section
                    if !validationRunner.validationResults.isEmpty {
                        resultsSection
                    }
                    
                    // Console Output Section
                    if !validationRunner.consoleMessages.isEmpty {
                        consoleSection
                    }
                }
                .padding()
            }
            .navigationTitle("Timeline v2 Validation")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    // MARK: - Header Section
    
    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundColor(.blue)
                    .font(.title2)
                
                Text("Beta Readiness Validation")
                    .font(.title2)
                    .fontWeight(.semibold)
            }
            
            Text("Comprehensive testing of Timeline v2 architecture with 42 automated test cases across 6 categories.")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            // Status Badge
            HStack {
                statusBadge
                Spacer()
                if !validationRunner.validationResults.isEmpty {
                    summaryStats
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    private var statusBadge: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            Text(statusText)
                .font(.caption)
                .fontWeight(.medium)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.1))
        .cornerRadius(20)
    }
    
    private var statusColor: Color {
        switch validationRunner.overallStatus {
        case .notStarted: return .gray
        case .running: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
    
    private var statusText: String {
        switch validationRunner.overallStatus {
        case .notStarted: return "Ready to Start"
        case .running: return "Running Tests"
        case .completed: return "Validation Complete"
        case .failed: return "Validation Failed"
        }
    }
    
    private var summaryStats: some View {
        let totalTests = validationRunner.validationResults.count
        let passedTests = validationRunner.validationResults.filter { $0.status == .passed }.count
        let failedTests = validationRunner.validationResults.filter { $0.status == .failed }.count
        
        HStack(spacing: 16) {
            statItem(title: "Total", value: "\(totalTests)", color: .primary)
            statItem(title: "Passed", value: "\(passedTests)", color: .green)
            if failedTests > 0 {
                statItem(title: "Failed", value: "\(failedTests)", color: .red)
            }
        }
    }
    
    private func statItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    // MARK: - Control Section
    
    private var controlSection: some View {
        VStack(spacing: 16) {
            Button(action: {
                Task {
                    await validationRunner.runCompleteValidation()
                }
            }) {
                HStack {
                    if validationRunner.isRunning {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Image(systemName: "play.fill")
                    }
                    
                    Text(validationRunner.isRunning ? "Running Validation..." : "Start Complete Validation")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(validationRunner.isRunning ? Color.gray : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            .disabled(validationRunner.isRunning)
            
            if validationRunner.overallStatus == .completed || validationRunner.overallStatus == .failed {
                Button("Clear Results") {
                    validationRunner.validationResults.removeAll()
                    validationRunner.consoleMessages.removeAll()
                    validationRunner.overallStatus = .notStarted
                }
                .foregroundColor(.secondary)
            }
        }
    }
    
    // MARK: - Progress Section
    
    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gear")
                    .foregroundColor(.blue)
                Text("Current Test")
                    .font(.headline)
            }
            
            if !validationRunner.currentTest.isEmpty {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(validationRunner.currentTest)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
    
    // MARK: - Results Section
    
    private var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "list.clipboard")
                    .foregroundColor(.blue)
                Text("Test Results")
                    .font(.headline)
            }
            
            // Category breakdown
            ForEach(TimelineV2ValidationRunner.ValidationCategory.allCases, id: \.self) { category in
                categoryResultsView(for: category)
            }
        }
    }
    
    private func categoryResultsView(for category: TimelineV2ValidationRunner.ValidationCategory) -> some View {
        let categoryResults = validationRunner.validationResults.filter { $0.category == category }
        
        if categoryResults.isEmpty {
            return AnyView(EmptyView())
        }
        
        return AnyView(
            VStack(alignment: .leading, spacing: 8) {
                // Category Header
                HStack {
                    Text(category.rawValue)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    Spacer()
                    
                    let passed = categoryResults.filter { $0.status == .passed }.count
                    let total = categoryResults.count
                    
                    Text("\(passed)/\(total)")
                        .font(.caption)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(passed == total ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
                        .cornerRadius(8)
                }
                
                // Individual test results
                ForEach(categoryResults) { result in
                    testResultRow(result)
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
        )
    }
    
    private func testResultRow(_ result: TimelineV2ValidationRunner.ValidationResult) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Status Icon
            Image(systemName: statusIcon(for: result.status))
                .foregroundColor(statusColor(for: result.status))
                .font(.caption)
                .frame(width: 16)
            
            // Test Info
            VStack(alignment: .leading, spacing: 4) {
                Text(result.testName)
                    .font(.caption)
                    .fontWeight(.medium)
                
                Text(result.details)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
            }
            
            Spacer()
            
            // Timestamp
            Text(result.timestamp.formatted(date: .omitted, time: .shortened))
                .font(.caption2)
                .foregroundColor(.tertiary)
        }
        .padding(.vertical, 4)
    }
    
    private func statusIcon(for status: TimelineV2ValidationRunner.ValidationResult.TestStatus) -> String {
        switch status {
        case .pending: return "clock"
        case .running: return "arrow.clockwise"
        case .passed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .skipped: return "minus.circle.fill"
        }
    }
    
    private func statusColor(for status: TimelineV2ValidationRunner.ValidationResult.TestStatus) -> Color {
        switch status {
        case .pending: return .gray
        case .running: return .blue
        case .passed: return .green
        case .failed: return .red
        case .skipped: return .orange
        }
    }
    
    // MARK: - Console Section
    
    private var consoleSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "terminal")
                    .foregroundColor(.blue)
                Text("Console Output")
                    .font(.headline)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(Array(validationRunner.consoleMessages.enumerated()), id: \.offset) { index, message in
                        Text(message)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(8)
            }
            .frame(maxHeight: 200)
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

// MARK: - Preview

struct TimelineV2ValidationView_Previews: PreviewProvider {
    static var previews: some View {
        TimelineV2ValidationView(socialServiceManager: SocialServiceManager())
    }
}
