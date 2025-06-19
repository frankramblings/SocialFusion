import SwiftUI

struct DebugOptionsView: View {
    @State private var testingEnabled = UserDefaults.standard.bool(
        forKey: "ArchitectureTestingEnabled")
    @State private var showingRestartAlert = false

    var body: some View {
        List {
            Section(header: Text("Architecture Testing")) {
                Toggle("Enable Architecture Testing", isOn: $testingEnabled)
                    .onChange(of: testingEnabled) { newValue in
                        UserDefaults.standard.set(newValue, forKey: "ArchitectureTestingEnabled")
                        if newValue {
                            showingRestartAlert = true
                        }
                    }

                if testingEnabled {
                    Text("⚠️ App will launch in testing mode after restart")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Section(header: Text("Instructions")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("1. Enable Architecture Testing above")
                    Text("2. Force close and relaunch the app")
                    Text("3. The app will open in testing mode")
                    Text("4. Run migration tests and compare architectures")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section(header: Text("Quick Actions")) {
                NavigationLink("Migration Control Panel") {
                    MigrationControlPanel()
                }

                Button("Run Tests Now") {
                    // This will navigate to testing view immediately
                    NotificationCenter.default.post(name: .showTestingView, object: nil)
                }

                Button("Reset Testing Settings") {
                    UserDefaults.standard.removeObject(forKey: "ArchitectureTestingEnabled")
                    testingEnabled = false
                }
                .foregroundColor(.red)
            }
        }
        .navigationTitle("Debug Options")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Restart Required", isPresented: $showingRestartAlert) {
            Button("OK") {}
        } message: {
            Text("Please force close and relaunch the app to enter testing mode.")
        }
    }
}

// MARK: - Notification Extension

extension Notification.Name {
    static let showTestingView = Notification.Name("showTestingView")
}

// MARK: - Preview

#if DEBUG
    struct DebugOptionsView_Previews: PreviewProvider {
        static var previews: some View {
            NavigationView {
                DebugOptionsView()
            }
        }
    }
#endif
