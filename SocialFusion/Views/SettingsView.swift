import SwiftUI
import UIKit

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = 0  // 0: System, 1: Light, 2: Dark
    @AppStorage("defaultPostVisibility") private var defaultPostVisibility = 0  // 0: Public, 1: Unlisted, 2: Followers Only
    @AppStorage("autoRefreshTimeline") private var autoRefreshTimeline = true
    @AppStorage("refreshInterval") private var refreshInterval = 2  // minutes
    @AppStorage("showContentWarnings") private var showContentWarnings = true
    @AppStorage("enableNotifications") private var enableNotifications = true

    @State private var showingAbout = false
    @State private var showingPrivacyPolicy = false
    @State private var showingTermsOfService = false

    var body: some View {
        NavigationView {
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

                Section(header: Text("Posting")) {
                    Picker("Default Post Visibility", selection: $defaultPostVisibility) {
                        Text("Public").tag(0)
                        Text("Unlisted").tag(1)
                        Text("Followers Only").tag(2)
                    }
                }

                Section(header: Text("Notifications")) {
                    Toggle("Enable Notifications", isOn: $enableNotifications)
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

                Section {
                    Button(action: {
                        // Log out action
                    }) {
                        Text("Log Out")
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
        }
    }
}

struct AboutView: View {
    var body: some View {
        NavigationView {
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
            .navigationTitle("About")
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
        NavigationView {
            ScrollView {
                Text(content)
                    .padding()
            }
            .navigationTitle(title)
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
