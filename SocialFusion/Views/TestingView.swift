import SwiftUI

/// Testing view to validate the new architecture
struct TestingView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @StateObject private var migrationController: MigrationTestController
    @State private var showingNewArchitecture = false
    @State private var testCompleted = false
    
    init() {
        let serviceManager = SocialServiceManager.shared
        self._migrationController = StateObject(wrappedValue: MigrationTestController(serviceManager: serviceManager))
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                // Test Status Card
                VStack(alignment: .leading, spacing: 12) {
                    Text("Architecture Migration Testing")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("Current Status: \(migrationController.migrationState.description)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    // Test Button
                    Button(action: {
                        Task {
                            await migrationController.runMigrationTests()
                            testCompleted = true
                        }
                    }) {
                        HStack {
                            if migrationController.isRunningTests {
                                ProgressView()
                                    .scaleEffect(0.8)
                                Text("Running Tests...")
                            } else {
                                Image(systemName: "play.circle.fill")
                                Text("Run Migration Tests")
                            }
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                        .background(migrationController.isRunningTests ? Color.gray : Color.blue)
                        .cornerRadius(10)
                    }
                    .disabled(migrationController.isRunningTests)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
                
                // Test Results
                if !migrationController.testResults.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Test Results")
                                .font(.headline)
                                .padding(.horizontal)
                            
                            ForEach(migrationController.testResults) { result in
                                HStack {
                                    Image(systemName: result.success ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundColor(result.success ? .green : .red)
                                        .font(.title3)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        
                                        Text(result.details)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                    
                                    Spacer()
                                    
                                    Text(DateFormatter.timeOnly.string(from: result.timestamp))
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                                .padding()
                                .background(Color(.systemBackground))
                                .cornerRadius(8)
                                .padding(.horizontal)
                            }
                        }
                    }
                    .frame(maxHeight: 300)
                }
                
                // Architecture Comparison Buttons
                if testCompleted {
                    VStack(spacing: 12) {
                        Text("Compare Architectures")
                            .font(.headline)
                        
                        HStack(spacing: 16) {
                            NavigationLink(destination: oldArchitectureView) {
                                VStack {
                                    Image(systemName: "doc.text")
                                        .font(.title2)
                                    Text("Old Architecture")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.orange.opacity(0.2))
                                .cornerRadius(10)
                            }
                            
                            NavigationLink(destination: newArchitectureView) {
                                VStack {
                                    Image(systemName: "doc.badge.plus")
                                        .font(.title2)
                                    Text("New Architecture")
                                        .font(.caption)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.green.opacity(0.2))
                                .cornerRadius(10)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("Architecture Testing")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    // MARK: - Architecture Views
    
    private var oldArchitectureView: some View {
        VStack {
            Text("Original Timeline Implementation")
                .font(.title2)
                .padding()
            
            UnifiedTimelineView(accounts: serviceManager.accounts)
                .environmentObject(serviceManager)
        }
        .navigationTitle("Old Architecture")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var newArchitectureView: some View {
        VStack {
            Text("New Timeline Implementation")
                .font(.title2)
                .padding()
            
            UnifiedTimelineViewV2(serviceManager: serviceManager)
                .environmentObject(serviceManager)
        }
        .navigationTitle("New Architecture")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Helper Extensions

extension DateFormatter {
    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()
}

// MARK: - Preview

#if DEBUG
struct TestingView_Previews: PreviewProvider {
    static var previews: some View {
        TestingView()
            .environmentObject(SocialServiceManager.shared)
    }
}
#endif 