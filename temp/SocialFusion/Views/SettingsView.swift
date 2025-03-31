import SwiftUI

struct SettingsView: View {
    @AppStorage("appearanceMode") private var appearanceMode = 0 // 0: System, 1: Light, 2: Dark
    @AppStorage("defaultPostVisibility") private var defaultPostVisibility = 0 // 0: Public, 1: Unlisted, 2: Followers Only
    @AppStorage("autoRefreshTimeline") private var autoRefreshTimeline = true
    @AppStorage("refreshInterval") private var refreshInterval = 2 // minutes
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
                    Image(systemName: "bubble.left.and.bubble.right.fill")
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
                    
                    Text("A streamlined, modern native iOS social media aggregator that seamlessly integrates content from Mastodon (ActivityPub) and Bluesky (AT Protocol) into one intuitive interface.")
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
            .navigationBarItems(trailing: Button("Done") {
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
            .navigationBarItems(trailing: Button("Done") {
                // Dismiss the sheet
            })
        }
    }
}

// Sample content for privacy policy and terms of service
let privacyPolicyContent = """
Privacy Policy

Last updated: January 1, 2023

This Privacy Policy describes how SocialFusion ("we," "us," or "our") collects, uses, and discloses your information when you use our mobile application (the "App").

Information We Collect

We collect information that you provide directly to us, such as when you create an account, update your profile, or communicate with us. This may include your name, email address, username, password, profile picture, and any other information you choose to provide.

We also collect information automatically when you use the App, such as your IP address, device information, operating system, and usage data.

How We Use Your Information

We use the information we collect to:
- Provide, maintain, and improve the App
- Create and manage your account
- Communicate with you about the App
- Monitor and analyze trends, usage, and activities in connection with the App
- Detect, investigate, and prevent fraudulent transactions and other illegal activities

Sharing of Information

We may share your information with:
- Third-party service providers who perform services on our behalf
- In response to a request for information if we believe disclosure is in accordance with any applicable law, regulation, or legal process
- If we believe your actions are inconsistent with our user agreements or policies, or to protect the rights, property, and safety of us or others

Your Choices

You can update your account information and preferences at any time by logging into your account settings. You may also opt out of receiving promotional communications from us by following the instructions in those communications.

Contact Us

I