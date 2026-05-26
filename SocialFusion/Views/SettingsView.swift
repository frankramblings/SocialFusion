import BackgroundTasks
import SwiftUI
import UIKit
import UserNotifications

struct SettingsView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @EnvironmentObject private var echoPolicyStore: EchoPolicyStore
    @EnvironmentObject private var pinnedTimelineStore: PinnedTimelineStore
    @EnvironmentObject private var accessibilityPreferences: AccessibilityPreferences
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var featureFlagManager = FeatureFlagManager.shared
    @AppStorage("appearanceMode") private var appearanceMode = 0  // 0: System, 1: Light, 2: Dark
    @AppStorage("defaultPostVisibility") private var defaultPostVisibility = 0  // 0: Public, 1: Unlisted, 2: Followers Only
    @AppStorage("autoRefreshTimeline") private var autoRefreshTimeline = true
    @AppStorage("refreshInterval") private var refreshInterval = 2  // minutes
    @AppStorage("showContentWarnings") private var showContentWarnings = true
    @AppStorage("enableNotifications") private var enableNotifications = true
    @AppStorage("showSensitiveTrending") private var showSensitiveTrending = false

    @State private var showingAbout = false
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false
    @State private var showingDebugOptions = false
    @State private var showingPinEditor = false
    @State private var showNotificationDeniedAlert = false
    @State private var totalCacheSize: Int64 = 0
    @State private var isCalculatingSize = false
    @State private var showClearImageAlert = false
    @State private var showClearDatabaseAlert = false
    @State private var showClearOtherAlert = false
    @State private var clearingInProgress = false
    @State private var showLogoutConfirmation = false

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
                    Button {
                        HapticEngine.tap.trigger()
                        showingPinEditor = true
                    } label: {
                        HStack(spacing: 12) {
                            Label("Pinned Timelines", systemImage: "pin.fill")
                                .foregroundStyle(.primary)
                            Spacer()
                            if !pinnedTimelineStore.pins.isEmpty {
                                Text("\(pinnedTimelineStore.pins.count)")
                                    .foregroundStyle(.secondary)
                            }
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.tertiary)
                                .font(.caption.weight(.semibold))
                        }
                    }
                    .accessibilityHint(pinnedTimelineStore.pins.isEmpty
                        ? "Create and manage pinned timelines"
                        : "Manage your \(pinnedTimelineStore.pins.count) pinned timeline\(pinnedTimelineStore.pins.count == 1 ? "" : "s")")

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
                        HStack(spacing: 12) {
                            SettingsIcon(symbol: "eye.slash", tint: .orange)
                            Text("Muted Keywords")
                            Spacer()
                            Text("\(serviceManager.currentBlockedKeywords.count)")
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                                .contentTransition(.numericText(value: Double(serviceManager.currentBlockedKeywords.count)))
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: serviceManager.currentBlockedKeywords.count)
                        }
                        // Combine the row's title and count so VoiceOver
                        // hears "Muted Keywords, 7" as a single
                        // announcement instead of two stops. Pluralizes
                        // the count for natural reading.
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel({
                            let n = serviceManager.currentBlockedKeywords.count
                            return n == 1
                                ? "Muted Keywords, 1 keyword"
                                : "Muted Keywords, \(n) keywords"
                        }())
                    }

                    Toggle("Show Sensitive Trending Tags", isOn: $showSensitiveTrending)

                    Text(
                        "When disabled, adult content is filtered from trending tags on the Search screen."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
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
                                UNUserNotificationCenter.current().setBadgeCount(0)
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

                Section(header: Text("Identity")) {
                    NavigationLink(destination: MergedIdentitiesManagementView()) {
                        Label("Merged identities", systemImage: "person.2.circle")
                    }
                }

                Section {
                    Picker("Echo replies on Fused posts", selection: $echoPolicyStore.policy) {
                        Text("Echo on by default").tag(EchoPolicy.echoOn)
                        Text("Echo off by default").tag(EchoPolicy.echoOff)
                        Text("Ask each time").tag(EchoPolicy.askEachTime)
                    }
                    .pickerStyle(.inline)
                    // Inline pickers don't fire UISegmentedControl's stock
                    // selection haptic, so changing the Echo policy felt
                    // dead compared to every other iOS setting toggle.
                    // The onChange fires once per real user pick (and
                    // also once on initial load — `oldValue != newValue`
                    // gates that out so the haptic doesn't fire on appear).
                    .onChange(of: echoPolicyStore.policy) { oldValue, newValue in
                        if oldValue != newValue {
                            HapticEngine.selection.trigger()
                        }
                    }
                } header: {
                    Text("Composer")
                } footer: {
                    Text("Controls the default state of the reply target toggles when you reply to a Fused conversation.")
                }

                Section(header: Text("Conversations")) {
                    NavigationLink(destination: WatchedConversationsView()) {
                        Label("Watching", systemImage: "bell")
                    }
                }

                Section(header: Text("Accessibility")) {
                    Toggle(
                        "High-Contrast Network Indicators",
                        isOn: $accessibilityPreferences.highContrastNetworkIndicators
                    )

                    // Live preview row — flips alongside the toggle so the
                    // user can see exactly what the choice changes before
                    // committing to it across the app.
                    HStack(spacing: 16) {
                        VStack(spacing: 6) {
                            PlatformLogoBadge(
                                platform: .bluesky,
                                size: 28,
                                highContrast: accessibilityPreferences.highContrastNetworkIndicators
                            )
                            Text("Bluesky").font(.caption2)
                        }
                        VStack(spacing: 6) {
                            PlatformLogoBadge(
                                platform: .mastodon,
                                size: 28,
                                highContrast: accessibilityPreferences.highContrastNetworkIndicators
                            )
                            Text("Mastodon").font(.caption2)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Preview of current network indicator style")

                    Text(
                        "Switches network indicators to a filled-vs-outlined scheme that stays distinguishable for colorblind readers. Shape-coded logos are always used, regardless of this setting."
                    )
                    .font(.caption)
                    .foregroundColor(.secondary)
                }

                Section(header: Text("About")) {
                    Button {
                        HapticEngine.tap.trigger()
                        showingAbout = true
                    } label: {
                        settingsRow(symbol: "info.circle", tint: .accentColor, title: "About SocialFusion")
                    }

                    Button {
                        HapticEngine.tap.trigger()
                        showingPrivacyPolicy = true
                    } label: {
                        settingsRow(symbol: "hand.raised", tint: .blue, title: "Privacy Policy")
                    }

                    Button {
                        HapticEngine.tap.trigger()
                        showingTermsOfService = true
                    } label: {
                        settingsRow(symbol: "doc.text", tint: .gray, title: "Terms of Service")
                    }

                    HStack(spacing: 12) {
                        SettingsIcon(symbol: "tag", tint: .secondary)
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                            .monospacedDigit()
                    }
                }

                Section(header: Text("Storage")) {
                    HStack(spacing: 12) {
                        SettingsIcon(symbol: "internaldrive", tint: .indigo)
                        Text("Cache Size")
                        Spacer()
                        if isCalculatingSize {
                            ProgressView()
                                .scaleEffect(0.8)
                                .accessibilityLabel("Calculating cache size")
                        } else {
                            Text(formattedSize(totalCacheSize))
                                .foregroundColor(.secondary)
                                .monospacedDigit()
                                // Cache size morphs as bytes change after
                                // a clear — smooth the digit transition.
                                .contentTransition(.numericText())
                                .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: totalCacheSize)
                        }
                    }
                    .onAppear {
                        Task { await calculateTotalCacheSize() }
                    }

                    Button {
                        HapticEngine.tap.trigger()
                        showClearImageAlert = true
                    } label: {
                        settingsRow(symbol: "photo.stack", tint: .orange, title: "Clear Image Cache")
                    }
                    .disabled(clearingInProgress)
                    .accessibilityHint("Opens a confirmation to clear cached images")

                    Button {
                        HapticEngine.tap.trigger()
                        showClearDatabaseAlert = true
                    } label: {
                        settingsRow(symbol: "arrow.counterclockwise.circle", tint: .orange, title: "Reset Post Database")
                    }
                    .disabled(clearingInProgress)
                    .accessibilityHint("Opens a confirmation to reset the offline post cache")

                    Button {
                        HapticEngine.tap.trigger()
                        showClearOtherAlert = true
                    } label: {
                        settingsRow(symbol: "trash", tint: .orange, title: "Clear Other Caches")
                    }
                    .disabled(clearingInProgress)
                    .accessibilityHint("Opens a confirmation to clear link, emoji, and search caches")
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
                    Button {
                        HapticEngine.warning.trigger()
                        showLogoutConfirmation = true
                    } label: {
                        settingsRow(
                            symbol: "rectangle.portrait.and.arrow.right",
                            tint: .red,
                            title: "Log Out All Accounts",
                            titleColor: .red
                        )
                    }
                    .accessibilityHint("Opens a confirmation to sign out of every connected account")
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
            .sheet(isPresented: $showingPinEditor) {
                PinnedTimelinesEditorView(
                    viewModel: PinnedTimelineEditorViewModel(store: pinnedTimelineStore)
                )
                .environmentObject(serviceManager)
            }
            .sheet(isPresented: $showingDebugOptions) {
                NavigationStack {
                    ProfileImageDebugView()
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") {
                                    HapticEngine.tap.trigger()
                                    showingDebugOptions = false
                                }
                                .fontWeight(.semibold)
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
            .alert("Clear Image Cache", isPresented: $showClearImageAlert) {
                Button("Clear", role: .destructive) {
                    HapticEngine.warning.trigger()
                    Task { await clearImageCache() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will remove all cached images. They will be re-downloaded as needed.")
            }
            .alert("Reset Post Database", isPresented: $showClearDatabaseAlert) {
                Button("Reset", role: .destructive) {
                    HapticEngine.warning.trigger()
                    Task { await clearPostDatabase() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will clear the offline post cache. Your timeline will refresh from the network.")
            }
            .alert("Clear Other Caches", isPresented: $showClearOtherAlert) {
                Button("Clear", role: .destructive) {
                    HapticEngine.warning.trigger()
                    Task { await clearOtherCaches() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This will clear link preview, emoji, media dimension, and search caches.")
            }
            // Sign out is an irreversible, multi-account-affecting
            // action — accidental taps were one tap away from
            // removing every credential. Confirm before logout.
            .alert("Log Out All Accounts?", isPresented: $showLogoutConfirmation) {
                Button("Log Out", role: .destructive) {
                    HapticEngine.warning.trigger()
                    Task { await serviceManager.logout() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll need to sign back in to use SocialFusion. Drafts and timeline state will be cleared.")
            }
        }
    }

    // MARK: - Storage Helpers

    private func formattedSize(_ bytes: Int64) -> String {
        SharedFormatters.byteCount.string(fromByteCount: bytes)
    }

    private func calculateTotalCacheSize() async {
        isCalculatingSize = true
        defer { isCalculatingSize = false }

        var total: Int64 = 0

        // Image cache (URLCache disk usage)
        let imageInfo = ImageCache.shared.getCacheInfo()
        total += Int64(imageInfo.diskSize)

        // Emoji cache (URLCache disk usage)
        let emojiDiskUsage = await CustomEmojiCache.shared.getDiskUsage()
        total += Int64(emojiDiskUsage)

        // SwiftData store files
        let storeSize = await TimelineSwiftDataStore.shared.getStoreSize()
        total += storeSize

        totalCacheSize = total
    }

    private func clearImageCache() async {
        clearingInProgress = true
        defer { clearingInProgress = false }

        ImageCache.shared.clearCache()
        await calculateTotalCacheSize()
        await MainActor.run {
            ToastManager.shared.show("Image cache cleared", severity: .success, duration: 1.6)
        }
    }

    private func clearPostDatabase() async {
        clearingInProgress = true
        defer { clearingInProgress = false }

        await TimelineSwiftDataStore.shared.clearAll()
        try? await serviceManager.fetchTimeline(force: true)
        await calculateTotalCacheSize()
        await MainActor.run {
            ToastManager.shared.show("Post database reset", severity: .success, duration: 1.6)
        }
    }

    private func clearOtherCaches() async {
        clearingInProgress = true
        defer { clearingInProgress = false }

        LinkPreviewCache.shared.clearCache()
        await CustomEmojiCache.shared.clearCache()
        MediaDimensionCache.shared.clearAll()
        SearchCache.shared.clear()
        await calculateTotalCacheSize()
        await MainActor.run {
            ToastManager.shared.show("Other caches cleared", severity: .success, duration: 1.6)
        }
    }

    /// Standard settings row with a leading tinted icon tile + title.
    /// Matches the iOS Settings app convention so each row has a colored
    /// anchor on the leading edge, making the form quicker to scan.
    @ViewBuilder
    fileprivate func settingsRow(
        symbol: String,
        tint: Color,
        title: String,
        titleColor: Color = .primary
    ) -> some View {
        HStack(spacing: 12) {
            SettingsIcon(symbol: symbol, tint: tint)
            Text(title)
                .foregroundColor(titleColor)
            Spacer()
        }
        .contentShape(Rectangle())
    }
}

/// A 28pt tinted rounded square containing an SF Symbol — the visual
/// language Apple's own Settings app uses for row leading icons.
private struct SettingsIcon: View {
    let symbol: String
    let tint: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundColor(.white)
            .frame(width: 28, height: 28)
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(tint.gradient)
            )
            .accessibilityHidden(true)
    }
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    private var bundleVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    private var copyrightYear: String {
        String(Calendar.current.component(.year, from: Date()))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Logo composition — the brand purple + blue circles fusing,
                    // mirroring the launch animation. Static here since it's a
                    // header element rather than a moment.
                    ZStack {
                        // Outer glow
                        Circle()
                            .fill(
                                RadialGradient(
                                    colors: [
                                        Color(red: 0.54, green: 0.39, blue: 1.00).opacity(0.22),
                                        Color.clear,
                                    ],
                                    center: .center,
                                    startRadius: 4,
                                    endRadius: 90
                                )
                            )
                            .frame(width: 180, height: 180)

                        // Mastodon purple
                        Circle()
                            .fill(Color(red: 0.54, green: 0.39, blue: 1.00))
                            .frame(width: 64, height: 64)
                            .offset(x: -16)
                            .blendMode(.plusLighter)

                        // Bluesky blue
                        Circle()
                            .fill(Color(red: 0.00, green: 0.59, blue: 1.00))
                            .frame(width: 64, height: 64)
                            .offset(x: 16)
                            .blendMode(.plusLighter)

                        // Center fusion lens
                        Circle()
                            .fill(Color(red: 0.11, green: 0.91, blue: 1.00))
                            .frame(width: 24, height: 24)
                            .blur(radius: 4)
                    }
                    .padding(.top, 36)
                    .accessibilityHidden(true)

                    VStack(spacing: 6) {
                        Text("SocialFusion")
                            .font(.largeTitle.weight(.bold))
                            .accessibilityAddTraits(.isHeader)

                        Text(bundleVersion)
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(.secondary)
                    }

                    Text(
                        "A streamlined, modern native iOS social media aggregator that seamlessly integrates content from Mastodon (ActivityPub) and Bluesky (AT Protocol) into one intuitive interface."
                    )
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.primary.opacity(0.85))
                    .padding(.horizontal, 28)
                    .padding(.top, 8)

                    Spacer(minLength: 24)

                    Text("© \(copyrightYear) SocialFusion")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.bottom, 24)
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        HapticEngine.tap.trigger()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

struct WebContentView: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let content: String

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(content)
                    .font(.body)
                    .foregroundColor(.primary.opacity(0.9))
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        HapticEngine.tap.trigger()
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
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
                    #if DEBUG
                    print("🗑️ [Debug] Cleared image cache")
                    #endif
                }

                Button("Show Cache Stats") {
                    let stats = ImageCache.shared.getCacheInfo()
                    cacheStats = "Memory: \(stats.memoryCount) items, Disk: \(stats.diskSize) bytes"
                    #if DEBUG
                    print("📊 [Debug] Cache stats: \(cacheStats)")
                    #endif
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
                    #if DEBUG
                    print(
                        "🧪 [Debug] Test load \(urlString.suffix(30)): \(success ? "✅" : "❌") (\(String(format: "%.2f", loadTime))s)"
                    )
                    #endif
                } catch {
                    let loadTime = Date().timeIntervalSince(startTime)
                    results.append(
                        "❌ \(url.host ?? "unknown"): Error (\(String(format: "%.2f", loadTime))s)")
                    #if DEBUG
                    print("🧪 [Debug] Test load \(urlString.suffix(30)): ❌ Error: \(error)")
                    #endif
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
                #if DEBUG
                print(
                    "🔴 [Live Monitor] \(status) \(url.suffix(30)) (\(String(format: "%.2f", loadTime))s)"
                )
                #endif
            }
        }

        // Auto-disable after 5 minutes to avoid log spam
        DispatchQueue.main.asyncAfter(deadline: .now() + 300) {
            self.liveMonitoringActive = false
            NotificationCenter.default.removeObserver(
                self, name: NSNotification.Name("ProfileImageLoadAttempt"), object: nil)
            #if DEBUG
            print("🔴 [Live Monitor] Auto-disabled after 5 minutes")
            #endif
        }

        #if DEBUG
        print("🔴 [Live Monitor] Started - will track all profile image loads for 5 minutes")
        #endif
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

/// Lists all user-confirmed cross-network identity merges and lets the user
/// remove any of them. Heuristic / unconfirmed merges live only in-memory
/// for the session and are not surfaced here.
private struct MergedIdentitiesManagementView: View {
    @EnvironmentObject private var mergedIdentityStore: MergedIdentityStore

    var body: some View {
        List {
            let merges = mergedIdentityStore.userConfirmedMerges()
            if merges.isEmpty {
                Section {
                    Text("You haven't merged any cross-network identities yet.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } else {
                Section {
                    ForEach(merges) { merge in
                        mergeRow(merge)
                    }
                } footer: {
                    Text("Merged identities show profiles from both networks as a single card with both handles visible.")
                }
            }
        }
        .navigationTitle("Merged identities")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func mergeRow(_ merge: MergedIdentity) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    PlatformLogoBadge(platform: .mastodon, size: 14, shadowEnabled: false)
                    Text("@\(merge.mastodon.handle)")
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                HStack(spacing: 6) {
                    PlatformLogoBadge(platform: .bluesky, size: 14, shadowEnabled: false)
                    Text("@\(merge.bluesky.handle)")
                        .font(.subheadline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            Spacer()
            Button(role: .destructive) {
                HapticEngine.selection.trigger()
                mergedIdentityStore.unmerge(id: merge.id)
            } label: {
                Text("Unmerge")
                    .font(.subheadline.weight(.semibold))
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
        // `.contain` keeps the destructive Unmerge button independently
        // focusable (the previous `.combine` collapsed it into the row's
        // label so VoiceOver users heard "double-tap Unmerge" but
        // couldn't actually reach the button). The custom rotor action
        // also exposes Unmerge through swipe-actions.
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Merged identity: at \(merge.mastodon.handle) on Mastodon, at \(merge.bluesky.handle) on Bluesky")
        .accessibilityAction(named: "Unmerge") {
            HapticEngine.selection.trigger()
            mergedIdentityStore.unmerge(id: merge.id)
        }
    }
}
