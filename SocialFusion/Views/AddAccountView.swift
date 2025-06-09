import Combine
import Foundation
import SwiftUI
import UIKit

struct AddAccountView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @EnvironmentObject private var oauthManager: OAuthManager
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedPlatform: SocialPlatform = .mastodon
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var accessToken = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var authMethod: AuthMethod = .oauth
    @State private var platformSelected = true
    @State private var isOAuthFlow = true
    @State private var isAuthCodeEntered = false
    @State private var showWebAuthFailure = false
    @State private var serverName = ""
    @State private var showError = false

    // App lifecycle persistence to prevent 1Password autofill from dismissing the view
    @State private var wasInBackground = false
    @State private var preserveFormState = false
    @State private var presentationStatePreserved = false

    // UserDefaults keys for form persistence
    private let formDataKey = "AddAccountView.FormData"
    private let presentationStateKey = "AddAccountView.WasPresented"

    private struct FormData: Codable {
        let selectedPlatform: SocialPlatform
        let server: String
        let username: String
        let password: String
        let accessToken: String
        let authMethod: AuthMethod
    }

    enum AuthMethod: String, CaseIterable, Identifiable, Codable {
        case oauth = "OAuth"
        case manual = "Access Token"

        var id: String { self.rawValue }
    }

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Platform")) {
                    HStack(spacing: 10) {
                        PlatformButton(
                            platform: .mastodon,
                            isSelected: selectedPlatform == .mastodon,
                            action: { selectedPlatform = .mastodon }
                        )

                        PlatformButton(
                            platform: .bluesky,
                            isSelected: selectedPlatform == .bluesky,
                            action: { selectedPlatform = .bluesky }
                        )
                    }
                    .onChange(of: selectedPlatform) { _ in
                        // Clear any error when platform changes
                        errorMessage = nil

                        // Set default server for Bluesky or clear for Mastodon
                        if selectedPlatform == .bluesky {
                            server = "bsky.social"
                            authMethod = .oauth  // Bluesky only uses username/password
                        } else {
                            server = ""
                        }
                    }
                }

                if selectedPlatform == .mastodon {
                    Section(header: Text("Authentication Method")) {
                        Picker("Auth Method", selection: $authMethod) {
                            ForEach(AuthMethod.allCases) { method in
                                Text(method.rawValue).tag(method)
                            }
                        }
                        .pickerStyle(SegmentedPickerStyle())
                    }
                }

                Section(header: Text("Account Information")) {
                    if selectedPlatform == .mastodon {
                        Text("Enter your Mastodon server address")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Server", text: $server)
                            .autocapitalization(.none)
                            .keyboardType(.URL)
                            .disableAutocorrection(true)
                            .submitLabel(.done)

                        if authMethod == .manual {
                            Text("Paste your access token from your Mastodon app settings")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 8)

                            SecureField("Access Token", text: $accessToken)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .autocorrectionDisabled(true)
                                .textInputAutocapitalization(.never)
                        }
                    } else {
                        Text("Enter your Bluesky credentials")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Email or Username", text: $username)
                            .autocapitalization(.none)
                            .keyboardType(.emailAddress)
                            .disableAutocorrection(true)
                            .submitLabel(.done)

                        SecureField("App Password", text: $password)
                            .submitLabel(.done)

                        Text(
                            "Use an app password from Bluesky settings. Go to Settings → App Passwords in your Bluesky account to create one."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    }
                }

                if let errorMessage = errorMessage, !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section {
                    if selectedPlatform == .mastodon {
                        Button(action: addMastodonAccount) {
                            if isLoading {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                    Spacer()
                                }
                            } else {
                                HStack {
                                    Spacer()
                                    Image("MastodonLogo")
                                        .resizable()
                                        .renderingMode(.template)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 20, height: 20)
                                        .foregroundColor(.white)
                                    Text("Sign in with Mastodon")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(platformColor(for: selectedPlatform))
                                )
                                .padding(.vertical, 4)
                            }
                        }
                        .disabled(
                            isLoading || server.isEmpty
                                || (authMethod == .manual && accessToken.isEmpty))
                    } else {
                        Button(action: addAccount) {
                            if isLoading {
                                HStack {
                                    Spacer()
                                    ProgressView()
                                        .progressViewStyle(CircularProgressViewStyle())
                                    Spacer()
                                }
                            } else {
                                HStack {
                                    Spacer()
                                    Image(systemName: "cloud.fill")
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundColor(.white)
                                    Text("Sign in with Bluesky")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Spacer()
                                }
                                .frame(height: 44)
                                .background(
                                    RoundedRectangle(cornerRadius: 10)
                                        .fill(platformColor(for: selectedPlatform))
                                )
                                .padding(.vertical, 4)
                            }
                        }
                        .disabled(isLoading || !isBlueskyFormValid)
                    }
                }
            }
            .navigationTitle("Add \(selectedPlatform.rawValue.capitalized) Account")
            .navigationBarBackButtonHidden(true)
            .navigationBarItems(
                leading:
                    Button("Cancel") {
                        if !preserveFormState {
                            dismiss()
                        }
                    }
            )
            .alert(isPresented: $showError) {
                Alert(
                    title: Text("Error"),
                    message: Text(errorMessage ?? "An unknown error occurred"),
                    dismissButton: .default(Text("OK"))
                )
            }
            .onAppear {
                // Restore form data if it was preserved
                restoreFormDataIfNeeded()
                // Set flag to indicate AddAccountView is presented
                UserDefaults.standard.set(
                    true, forKey: "AddAccountView.WasPresentedDuringBackground")
            }
            .onChange(of: scenePhase) { newPhase in
                handleScenePhaseChange(newPhase)
            }
            .onReceive(
                NotificationCenter.default.publisher(
                    for: Notification.Name("shouldRepresentAddAccount"))
            ) { notification in
                // Check if this is an autofill recovery and we should handle it
                if let userInfo = notification.userInfo,
                    let source = userInfo["source"] as? String,
                    source == "autofillRecovery"
                {

                    // Only handle if we're not already presented
                    guard !UserDefaults.standard.bool(forKey: "AddAccountView.RecoveryInProgress")
                    else {
                        return
                    }

                    print("🔐 [AddAccountView] Received autofill recovery notification")

                    // Mark recovery as in progress
                    UserDefaults.standard.set(true, forKey: "AddAccountView.RecoveryInProgress")

                    // Restore form data if needed
                    restoreFormDataIfNeeded()

                    // Clear recovery flag after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                        UserDefaults.standard.removeObject(
                            forKey: "AddAccountView.RecoveryInProgress")
                    }
                }
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.1))
                                .frame(width: 60, height: 60)
                        )
                }
            }
        }
    }

    private var isBlueskyFormValid: Bool {
        return !username.isEmpty && !password.isEmpty
    }

    private func addAccount() {
        isLoading = true
        errorMessage = nil

        if selectedPlatform == .mastodon {
            addMastodonAccount()
        } else if selectedPlatform == .bluesky {
            addBlueskyAccount()
        }
    }

    private func addMastodonAccount() {
        Task {
            do {
                // Handle test account creation
                if username == "test" && password == "test" {
                    createTestMastodonAccount()
                    return
                }

                // Check if the URL is valid
                guard
                    let url = URL(
                        string: server.hasPrefix("https://") ? server : "https://" + server),
                    url.scheme == "https",
                    url.host != nil
                else {
                    throw NSError(
                        domain: "AddAccountView", code: 400,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"]
                    )
                }

                if authMethod == .manual {
                    // Use access token authentication
                    _ = try await serviceManager.addMastodonAccountWithToken(
                        serverURL: url.absoluteString,
                        accessToken: accessToken
                    )
                } else {
                    // Use OAuth flow
                    let credentials = try await withCheckedThrowingContinuation { continuation in
                        oauthManager.authenticateMastodon(server: url.absoluteString) { result in
                            continuation.resume(with: result)
                        }
                    }

                    // Add account with proper OAuth credentials
                    _ = try await serviceManager.addMastodonAccountWithOAuth(
                        credentials: credentials)
                }

                // Update the UI
                DispatchQueue.main.async {
                    self.isLoading = false

                    // Clear the presentation flag since we're dismissing successfully
                    UserDefaults.standard.removeObject(
                        forKey: "AddAccountView.WasPresentedDuringBackground")

                    self.dismiss()

                    // Notify about the account change
                    NotificationCenter.default.post(name: .accountUpdated, object: nil)
                }

            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Error adding account: \(error.localizedDescription)"
                }
            }
        }
    }

    private func addBlueskyAccount() {
        Task {
            do {
                // Handle test account creation
                if username == "test" && password == "test" {
                    createTestBlueskyAccount()
                    return
                }

                // Make sure we have both username and password
                guard !username.isEmpty, !password.isEmpty else {
                    throw NSError(
                        domain: "AddAccountView", code: 400,
                        userInfo: [NSLocalizedDescriptionKey: "Username and password are required"]
                    )
                }

                // No need to create a URL here, the manager will handle it
                // Use the SocialServiceManager to add the Bluesky account
                _ = try await serviceManager.addBlueskyAccount(
                    username: username,
                    password: password
                )

                // Update the UI
                DispatchQueue.main.async {
                    self.isLoading = false

                    // Clear the presentation flag since we're dismissing successfully
                    UserDefaults.standard.removeObject(
                        forKey: "AddAccountView.WasPresentedDuringBackground")

                    self.dismiss()

                    // Notify about the account change
                    NotificationCenter.default.post(name: .accountUpdated, object: nil)
                }

            } catch {
                DispatchQueue.main.async {
                    self.isLoading = false
                    self.errorMessage = "Error adding account: \(error.localizedDescription)"
                }
            }
        }
    }

    // Test account creation methods
    private func createTestMastodonAccount() {
        // Create temporary account for testing
        let tempAccount = SocialAccount(
            id: UUID().uuidString,
            username: "test_user",
            displayName: "Test User",
            serverURL: "mastodon.social",
            platform: .mastodon
        )

        // Add the account to the service manager directly
        DispatchQueue.main.async {
            self.serviceManager.mastodonAccounts.append(tempAccount)
            print("Added test Mastodon account")
            self.isLoading = false

            // Set this account as selected
            self.serviceManager.selectedAccountIds = [tempAccount.id]

            // Notify and dismiss
            NotificationCenter.default.post(name: .accountUpdated, object: nil)
            self.dismiss()
        }
    }

    private func createTestBlueskyAccount() {
        // Create temporary account for testing
        let tempAccount = SocialAccount(
            id: UUID().uuidString,
            username: "test_user.bsky.social",
            displayName: "Test User",
            serverURL: "bsky.social",
            platform: .bluesky
        )

        // Add the account to the service manager directly
        DispatchQueue.main.async {
            self.serviceManager.blueskyAccounts.append(tempAccount)
            print("Added test Bluesky account")
            self.isLoading = false

            // Set this account as selected
            self.serviceManager.selectedAccountIds = [tempAccount.id]

            // Notify and dismiss
            NotificationCenter.default.post(name: .accountUpdated, object: nil)
            self.dismiss()
        }
    }

    private func getLogoSystemName(for platform: SocialPlatform) -> String {
        switch platform {
        case .mastodon:
            return "message.fill"
        case .bluesky:
            return "cloud.fill"
        }
    }

    // Get platform color for a specific platform
    private func platformColor(for platform: SocialPlatform) -> Color {
        switch platform {
        case .mastodon:
            return Color(hex: "6364FF")
        case .bluesky:
            return Color(hex: "0085FF")
        }
    }

    private func handleScenePhaseChange(_ newPhase: ScenePhase) {
        switch newPhase {
        case .inactive, .background:
            // App is going to background (1Password is appearing)
            // Preserve form state and mark that view was presented
            wasInBackground = true
            preserveFormState = true
            preserveFormData()
            UserDefaults.standard.set(true, forKey: presentationStateKey)
            UserDefaults.standard.set(true, forKey: "AddAccountView.WasPresentedDuringBackground")
            print(
                "🔐 [AddAccountView] App went to background - preserving form state and presentation flag"
            )

        case .active:
            // App returned to foreground
            if wasInBackground {
                print("🔐 [AddAccountView] App returned to foreground - checking for autofill")

                // Small delay to allow autofill to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // Re-enable normal navigation after autofill completes
                    preserveFormState = false
                    print("🔐 [AddAccountView] Form state preservation disabled")

                    // Clear the presentation state since we're still here
                    UserDefaults.standard.removeObject(forKey: presentationStateKey)
                    UserDefaults.standard.removeObject(
                        forKey: "AddAccountView.WasPresentedDuringBackground")
                }

                wasInBackground = false
            }

        @unknown default:
            break
        }
    }

    private func restoreFormDataIfNeeded() {
        guard let data = UserDefaults.standard.data(forKey: formDataKey),
            let formData = try? JSONDecoder().decode(FormData.self, from: data)
        else {
            print("🔐 [AddAccountView] No preserved form data found")
            return
        }

        // Restore form state
        selectedPlatform = formData.selectedPlatform
        server = formData.server
        username = formData.username
        password = formData.password
        accessToken = formData.accessToken
        authMethod = formData.authMethod

        print("🔐 [AddAccountView] Restored form data for platform: \\(formData.selectedPlatform)")

        // Clear the preserved data after restoration
        UserDefaults.standard.removeObject(forKey: formDataKey)
    }

    private func preserveFormData() {
        let formData = FormData(
            selectedPlatform: selectedPlatform,
            server: server,
            username: username,
            password: password,
            accessToken: accessToken,
            authMethod: authMethod
        )

        if let encoded = try? JSONEncoder().encode(formData) {
            UserDefaults.standard.set(encoded, forKey: formDataKey)
            print("🔐 [AddAccountView] Preserved form data for platform: \\(selectedPlatform)")
        }
    }
}

struct PlatformButton: View {
    let platform: SocialPlatform
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack {
                ZStack {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(isSelected ? platformColor(for: platform) : Color(.systemGray6))
                        .frame(height: 56)

                    HStack(spacing: 8) {
                        // Use system symbols for platform icons
                        Image(systemName: platform == .mastodon ? "message.fill" : "cloud.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundColor(isSelected ? .white : platformColor(for: platform))

                        Text(platform.rawValue.capitalized)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(isSelected ? .white : .primary)
                            .padding(.trailing, 4)
                    }
                    .padding(.horizontal)
                }
            }
        }
        .buttonStyle(PlainButtonStyle())
    }

    private func getLogoSystemName(for platform: SocialPlatform) -> String {
        switch platform {
        case .mastodon:
            return "message.fill"
        case .bluesky:
            return "cloud.fill"
        }
    }

    // Get platform color for a specific platform
    private func platformColor(for platform: SocialPlatform) -> Color {
        switch platform {
        case .mastodon:
            return Color(hex: "6364FF")
        case .bluesky:
            return Color(hex: "0085FF")
        }
    }
}

struct AddAccountView_Previews: PreviewProvider {
    static var previews: some View {
        AddAccountView().environmentObject(SocialServiceManager.shared)
    }
}
