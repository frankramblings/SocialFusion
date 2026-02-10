import BackgroundTasks
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @ObservedObject private var featureFlagManager = FeatureFlagManager.shared
    @AppStorage("appearanceMode") private var appearanceMode = 0  // 0: System, 1: Light, 2: Dark
    @AppStorage("defaultPostVisibility") private var defaultPostVisibility = 0  // 0: Public, 1: Unlisted, 2: Followers Only
    @AppStorage("autoRefreshTimeline") private var autoRefreshTimeline = true
    @AppStorage("refreshInterval") private var refreshInterval = 2  // minutes
    @AppStorage("showContentWarnings") private var showContentWarnings = true
    @AppStorage("enableNotifications") private var enableNotifications = true

    @State private var showingAbout = false
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false
    @State private var showingDebugOptions = false
    @State private var showNotificationDeniedAlert = false

    var body: some View {
        NavigationStack {
            Form {
                Section(header: Text("Appearance")) {
                    Picker("Theme", selection: $appearanceMode) {
                        Text("System").tag(0)
                        Text("Light").tag(1)
                        Text("Dark").tag(2)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                }

                Section(header: Text("Timeline")) {
                    Toggle("Auto-refresh Timeline", isOn: $autoRefreshTimeline)

                    if autoRefreshTimeline {
                        Picker("Refresh Interval", selection: $refreshInterval) {
                            Text("1 minute").tag(1)
                            Text("2 minutes").tag(2)
                            Text("5 minutes").tag(5)
                            Text("10 minutes").tag(10)
                        }
                    }

                    Toggle("Show Content Warnings", isOn: $showContentWarnings)
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
                                // Trigger timeline refresh to apply the new filter setting
                                Task {
                                    try? await serviceManager.fetchTimeline(force: true)
                                }
                            }
                        ))

                    Text(
                        "Hide replies to people you don't follow. Shows replies from your timeline only when you follow the person being replied to."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                    NavigationLink(destination: MutedKeywordsView().environmentObject(serviceManager)) {
                        HStack {
                            Text("Muted Keywords")
                            Spacer()
                            Text("\(serviceManager.currentBlockedKeywords.count)")
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Section(header: Text("Posting")) {
                    Picker("Default Post Visibility", selection: $defaultPostVisibility) {
                        Text("Public").tag(0)
                        Text("Unlisted").tag(1)
                        Text("Followers Only").tag(2)
                    }
                }

                Section(header: Text("Notifications")) {
                    Toggle("Enable Notifications", isOn: $enableNotifications)
                        .onChange(of: enableNotifications) { _, enabled in
                            if enabled {
                                UNUserNotificationCenter.current().requestAuthorization(
                                    options: [.alert, .sound, .badge]
                                ) { granted, _ in
                                    DispatchQueue.main.async {
                                        if granted {
                                            NotificationManager.shared.setupNotificationCategories()
                                            NotificationManager.shared.scheduleBackgroundRefresh()
                                        } else {
                                            enableNotifications = false
                                            showNotificationDeniedAlert = true
                                        }
                                    }
                                }
                            } else {
                                BGTaskScheduler.shared.cancel(
                                    taskRequestWithIdentifier: NotificationManager.bgTaskIdentifier)
                                UNUserNotificationCenter.current()
                                    .removeAllDeliveredNotifications()
                                UNUserNotificationCenter.current()
                                    .removeAllPendingNotificationRequests()
                                UIApplication.shared.applicationIconBadgeNumber = 0
                            }
                        }

                    if enableNotifications {
                        Toggle(
                            "Mentions",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.object(forKey: "notifyMentions") as? Bool
                                        ?? true
                                },
                                set: { UserDefaults.standard.set($0, forKey: "notifyMentions") }
                            ))
                        Toggle(
                            "Likes",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.object(forKey: "notifyLikes") as? Bool
                                        ?? true
                                },
                                set: { UserDefaults.standard.set($0, forKey: "notifyLikes") }
                            ))
                        Toggle(
                            "Reposts",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.object(forKey: "notifyReposts") as? Bool
                                        ?? true
                                },
                                set: { UserDefaults.standard.set($0, forKey: "notifyReposts") }
                            ))
                        Toggle(
                            "New Followers",
                            isOn: Binding(
                                get: {
                                    UserDefaults.standard.object(forKey: "notifyFollows") as? Bool
                                        ?? true
                                },
                                set: { UserDefaults.standard.set($0, forKey: "notifyFollows") }
                            ))
                    }
                }

                Section(header: Text("About")) {
                    Button("About SocialFusion") {
                        showingAbout = true
                    }

                    Button("Privacy Policy") {
                        showingPrivacyPolicy = true
                    }

                    Button("Terms of Service") {
                        showingTermsOfService = true
                    }

                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }
                }

                #if DEBUG
                    Section(header: Text("Debug")) {
                        Button("Profile Image Diagnostics") {
                            showingDebugOptions = true
                        }
                        .foregroundColor(.primary)
                        
                        Toggle("Debug Refresh", isOn: Binding(
                            get: { UserDefaults.standard.bool(forKey: "debugRefresh") },
                            set: { UserDefaults.standard.set($0, forKey: "debugRefresh") }
                        ))
                    }
                #endif

                Section {
                    Button(action: {
                        Task {
                            await serviceManager.logout()
                        }
                    }) {
                        Text("Log Out All Accounts")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Settings")
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .sheet(isPresented: $showingAbout) {
                AboutView()
            }
            .sheet(isPresented: $showingPrivacyPolicy) {
                WebContentView(title: "Privacy Policy", content: privacyPolicyContent)
            }
            .sheet(isPresented: $showingTermsOfService) {
                WebContentView(title: "Terms of Service", content: termsOfServiceContent)
            }
            .sheet(isPresented: $showingDebugOptions) {
                NavigationStack {
                    ProfileImageDebugView()
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingDebugOptions = false
                                }
                            }
                        }
                }
            }
            .alert("Notifications Disabled", isPresented: $showNotificationDeniedAlert) {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    "Notifications are disabled in system settings. Open Settings to enable them.")
            }
        }
    }
}

struct AboutView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    Image(systemName: "globe.americas.fill")
                        .font(.system(size: 80))
                        .foregroundColor(Color("PrimaryColor"))
                        .padding(.top, 40)

                    Text("SocialFusion")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("Version 1.0.0")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    Divider()
                        .padding(.horizontal, 40)

                    Text(
                        "A streamlined, modern native iOS social media aggregator that seamlessly integrates content from Mastodon (ActivityPub) and Bluesky (AT Protocol) into one intuitive interface."
                    )
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)

                    Spacer()

                    Text("© 2023 SocialFusion Team")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 20)
                }
                .padding()
            }

            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarItems(
                trailing: Button("Done") {
                    // Dismiss the sheet
                })
        }
    }
}

struct WebContentView: View {
    let title: String
    let content: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content)
                    .padding()
            }

            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationBarItems(
                trailing: Button("Done") {
                    // Dismiss the sheet
                })
        }
    }
}

// Sample content for privacy policy and terms of service
let termsOfServiceContent = """
    Terms of Service

    Last updated: January 1, 2024

    Welcome to SocialFusion. By accessing or using our mobile application (the "App"), you agree to be bound by these Terms of Service ("Terms"). Please read them carefully.

    1. Acceptance of Terms

    By using SocialFusion, you agree to these Terms and our Privacy Policy. If you do not agree, do not use the App.

    2. Account Registration

    You must create an account to use certain features. You agree to:
    - Provide accurate information
    - Maintain account security
    - Accept responsibility for account activity
    - Not share your account credentials

    3. User Content

    You retain rights to content you post but grant us license to use it within the App. You agree not to post content that:
    - Violates laws or rights of others
    - Is harmful, abusive, or inappropriate
    - Contains malware or spam
    - Infringes intellectual property rights

    4. Acceptable Use

    You agree to use the App only for lawful purposes and not to:
    - Interfere with App functionality
    - Attempt unauthorized access
    - Harass or harm other users
    - Collect user data without permission

    5. Service Modifications

    We may:
    - Modify or discontinue features
    - Update these Terms
    - Terminate accounts for violations

    6. Disclaimer of Warranties

    The App is provided "as is" without warranties of any kind, express or implied.

    7. Limitation of Liability

    We are not liable for indirect, incidental, or consequential damages arising from your use of the App.

    8. Governing Law

    These Terms are governed by the laws of the jurisdiction in which we operate.

    Contact Us

    // ...
    """
let privacyPolicyContent = """
    Privacy Policy

    Last updated: January 1, 2024

    This Privacy Policy describes how SocialFusion ("we," "us," or "our") collects, uses, and discloses your information when you use our mobile application (the "App").

    Information We Collect

    We collect information that you provide directly to us when you create an account, update your profile, or communicate with us. This includes:
    - Username and password for authentication
    - Profile information you choose to provide
    - Content you post or share through the App
    - Communications with our support team

    We also automatically collect certain technical information when you use the App:
    - Device information (model, OS version)
    - App usage data and analytics
    - Crash reports and performance data

    How We Use Your Information

    We use the information we collect to:
    - Provide and maintain the App's core functionality
    - Authenticate your account and keep it secure
    - Display your content and profile to other users
    - Send important service updates and notifications
    - Improve the App through analytics and debugging

    Sharing of Information

    We only share your information in limited circumstances:
    - With third-party services essential to app functionality (e.g. hosting providers)
    - When required by law or valid legal process
    - To protect the security of the App and its users

    Your Rights and Choices

    You can:
    - Access and update your account information anytime
    - Request deletion of your account and data
    - Control your content visibility settings
    - Opt out of optional communications

    Data Security

    We implement industry-standard security measures to protect your information. However, no method of transmission over the internet is 100% secure.

    Contact Us

    Questions about this Privacy Policy? Contact us at:
    privacy@socialfusion.com

    Last modified: January 1, 2024
    """

// Simple integrated debug view for profile images
struct ProfileImageDebugView: View {
    @State private var cacheStats: String = "Loading..."
    @State private var testResults: String = "Ready to test"
    @State private var liveMonitoringActive: Bool = false

    var body: some View {
        Form {
            Section("Image Cache") {
                Button("Clear Image Cache") {
                    ImageCache.shared.clearCache()
                    cacheStats = "Cache cleared"
                    print("🗑️ [Debug] Cleared image cache")
                }

                Button("Show Cache Stats") {
                    let stats = ImageCache.shared.getCacheInfo()
                    cacheStats = "Memory: \(stats.memoryCount) items, Disk: \(stats.diskSize) bytes"
                    print("📊 [Debug] Cache stats: \(cacheStats)")
                }

                Text(cacheStats)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Section("Profile Image Testing") {
                Button("Test Profile Image Loading") {
                    Task {
                        await testProfileImageLoading()
                    }
                }

                Button("Monitor Live Profile Loads") {
                    startLiveProfileMonitoring()
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

                        if let recentFailures = profileStats["recent_failures"] as? [String],
                            !recentFailures.isEmpty
                        {
                            Text("Recent failures:")
                                .font(.caption)
                                .foregroundColor(.red)
                            ForEach(recentFailures.prefix(3), id: \.self) { failure in
                                Text("• \(failure)")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }
                        }
                    }
                    .font(.caption)
                    .padding(.vertical, 4)
                }

                if liveMonitoringActive {
                    Text("🔴 Live monitoring active")
                        .font(.caption)
                        .foregroundColor(.red)
                        .padding(.vertical, 2)
                }
            }
        }
        .navigationTitle("Profile Image Debug")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            let stats = ImageCache.shared.getCacheInfo()
            cacheStats = "Memory: \(stats.memoryCount) items, Disk: \(stats.diskSize) bytes"
        }
    }

    @MainActor
    private func testProfileImageLoading() async {
        testResults = "Testing profile image loading..."

        // Test URLs from different platforms
        let testURLs = [
            "https://cdn.bsky.app/img/avatar/plain/did:plc:ewrirxeyw2neruusvce6pjif/bafkreia63tbca42zazhy7a7oau6oxl3fgfbggvf3yh3qs4ony4hge3oa4i@jpeg",
            "https://ramblings.social/system/accounts/avatars/113/617/938/735/996/406/original/e4dad69f2b79e320.png",
        ]

        var results: [String] = []

        for urlString in testURLs {
            if let url = URL(string: urlString) {
                let startTime = Date()
                do {
                    let (data, _) = try await URLSession.shared.data(from: url)
                    let loadTime = Date().timeIntervalSince(startTime)
                    let success = !data.isEmpty
                    results.append(
                        "✅ \(url.host ?? "unknown"): \(String(format: "%.2f", loadTime))s")
                    print(
                        "🧪 [Debug] Test load \(urlString.suffix(30)): \(success ? "✅" : "❌") (\(String(format: "%.2f", loadTime))s)"
                    )
                } catch {
                    let loadTime = Date().timeIntervalSince(startTime)
                    results.append(
                        "❌ \(url.host ?? "unknown"): Error (\(String(format: "%.2f", loadTime))s)")
                    print("🧪 [Debug] Test load \(urlString.suffix(30)): ❌ Error: \(error)")
                }
            }
        }

        testResults = results.joined(separator: "\n")
    }

    private func startLiveProfileMonitoring() {
        liveMonitoringActive = true

        // Subscribe to profile image loading notifications
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ProfileImageLoadAttempt"),
            object: nil,
            queue: .main
        ) { notification in
            if let userInfo = notification.userInfo,
                let url = userInfo["url"] as? String,
                let success = userInfo["success"] as? Bool,
                let loadTime = userInfo["loadTime"] as? Double
            {

                let status = success ? "✅" : "❌"
                print(
                    "🔴 [Live Monitor] \(status) \(url.suffix(30)) (\(String(format: "%.2f", loadTime))s)"
                )
            }
        }

        // Auto-disable after 5 minutes to avoid log spam
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
            self.liveMonitoringActive = false
            NotificationCenter.default.removeObserver(
                self, name: NSNotification.Name("ProfileImageLoadAttempt"), object: nil)
            print("🔴 [Live Monitor] Auto-disabled after 5 minutes")
        }

        print("🔴 [Live Monitor] Started - will track all profile image loads for 5 minutes")
    }

    private func getProfileImageStats() -> [String: Any]? {
        // This would integrate with MonitoringService if available
        // For now, return mock data to show the UI structure
        return [
            "total_loads": 42,
            "success_rate": 0.857,  // 85.7%
            "avg_load_time": 0.34,
            "recent_failures": [
                "cdn.bsky.app/invalid.jpg",
                "mastodon.social/timeout.png",
            ],
        ]
    }
}
