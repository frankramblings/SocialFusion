import Combine
import SwiftUI

struct DebugOptionsView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @State private var testingEnabled = UserDefaults.standard.bool(
        forKey: "ArchitectureTestingEnabled")
    @State private var showingRestartAlert = false
    @ObservedObject private var featureFlagManager = FeatureFlagManager.shared

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

            Section(header: Text("Feature Flags")) {
                Toggle(
                    "GIF Unfurling",
                    isOn: Binding(
                        get: { featureFlagManager.enableGIFUnfurling },
                        set: { enabled in
                            if enabled {
                                featureFlagManager.enableFeature(FeatureFlag.gifUnfurling)
                            } else {
                                featureFlagManager.disableFeature(FeatureFlag.gifUnfurling)
                            }
                        }
                    ))

                if featureFlagManager.enableGIFUnfurling {
                    Text("✅ GIF unfurling is enabled - GIFs will be processed for better loading")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("⚠️ GIF unfurling is disabled - using fallback GIF rendering")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }

            Section(header: Text("Feed Filtering")) {
                Toggle(
                    "Enable Reply Filtering",
                    isOn: Binding(
                        get: { featureFlagManager.enableReplyFiltering },
                        set: { enabled in
                            if enabled {
                                featureFlagManager.enableFeature(.replyFiltering)
                            } else {
                                featureFlagManager.disableFeature(.replyFiltering)
                            }
                        }
                    ))

                Text(
                    "Only show replies if at least 2 participants in the thread are followed accounts (Bluesky style)."
                )
                .font(.caption)
                .foregroundColor(.secondary)
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

            Section("Profile Image Diagnostics") {
                Button("Clear Image Cache") {
                    ImageCache.shared.clearCache()
                    print("🗑️ [Debug] Cleared image cache")
                }

                Button("Show Cache Stats") {
                    let stats = ImageCache.shared.getCacheInfo()
                    print(
                        "📊 [Debug] Cache stats - Memory count: \(stats.memoryCount), Disk size: \(stats.diskSize) bytes"
                    )
                }

                Button("Test Profile Image Loading") {
                    Task {
                        await testProfileImageLoading()
                    }
                }

                if let profileStats = getProfileImageStats() {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Profile Image Stats:")
                            .font(.headline)
                        Text("Total loads: \(String(describing: profileStats["total_loads"] ?? 0))")
                        Text(
                            "Success rate: \(String(format: "%.1f%%", (profileStats["success_rate"] as? Double ?? 0.0) * 100))"
                        )
                        Text(
                            "Avg load time: \(String(format: "%.2fs", profileStats["avg_load_time"] as? Double ?? 0.0))"
                        )
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                }
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

    @MainActor
    private func testProfileImageLoading() async {
        print("🧪 [Debug] Testing profile image loading...")

        let testURLs = [
            "https://cdn.bsky.app/img/avatar/plain/did:plc:ewrirxeyw2neruusvce6pjif/bafkreia63tbca42zazhy7a7oau6oxl3fgfbggvf3yh3qs4ony4hge3oa4i@jpeg",
            "https://ramblings.social/system/accounts/avatars/113/617/938/735/996/406/original/e4dad69f2b79e320.png",
            "https://invalid-url-test.com/avatar.jpg",
        ]

        for urlString in testURLs {
            if let url = URL(string: urlString) {
                let startTime = Date()

                let publisher = ImageCache.shared.loadImage(from: url)
                let image = await withCheckedContinuation { continuation in
                    var cancellable: AnyCancellable?
                    cancellable =
                        publisher
                        .sink { result in
                            continuation.resume(returning: result)
                            cancellable?.cancel()
                        }
                }

                let loadTime = Date().timeIntervalSince(startTime)
                let success = image != nil

                MonitoringService.shared.trackProfileImageLoad(
                    url: urlString,
                    platform: urlString.contains("bsky") ? .bluesky : .mastodon,
                    success: success,
                    loadTime: loadTime
                )

                print(
                    "🧪 [Debug] Test load \(urlString.suffix(30)): \(success ? "✅" : "❌") (\(String(format: "%.2f", loadTime))s)"
                )
            }
        }
    }

    private func getProfileImageStats() -> [String: Any]? {
        return MonitoringService.shared.getProfileImageStats()
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
