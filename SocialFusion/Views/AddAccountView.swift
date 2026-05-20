import Combine
import Foundation
import SwiftUI
import UIKit

struct AddAccountView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @EnvironmentObject private var oauthManager: OAuthManager
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedPlatform: SocialPlatform = .mastodon
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var platformSelected = true
    @State private var isOAuthFlow = true
    @State private var isAuthCodeEntered = false

    /// Focus targets for keyboard field-to-field navigation.
    private enum Field { case server, username, password }
    @FocusState private var focusedField: Field?
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
    }

    var body: some View {
        NavigationStack {
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
                    .onChange(of: selectedPlatform) {
                        // Clear any error when platform changes
                        errorMessage = nil

                        // Set default server for Bluesky or clear for Mastodon
                        if selectedPlatform == .bluesky {
                            server = "bsky.social"
                        } else {
                            server = ""
                        }
                    }
                }

                Section(header: Text("Account Information")) {
                    if selectedPlatform == .mastodon {
                        Text("Enter your Mastodon server address")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Server", text: $server)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            .autocorrectionDisabled(true)
                            .textContentType(.URL)
                            .submitLabel(.done)
                            .focused($focusedField, equals: .server)
                            .onSubmit { focusedField = nil }
                    } else {
                        Text("Enter your Bluesky credentials")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        TextField("Email or Username", text: $username)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.emailAddress)
                            .autocorrectionDisabled(true)
                            .textContentType(.username)
                            .submitLabel(.next)
                            .focused($focusedField, equals: .username)
                            .onSubmit { focusedField = .password }

                        SecureField("App Password", text: $password)
                            .textContentType(.password)
                            .submitLabel(.done)
                            .focused($focusedField, equals: .password)
                            .onSubmit { focusedField = nil }

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
                        Label {
                            Text(errorMessage)
                                .font(.footnote)
                                .fixedSize(horizontal: false, vertical: true)
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(Color.red.gradient)
                                .symbolRenderingMode(.hierarchical)
                        }
                        .foregroundColor(.red)
                        .multilineTextAlignment(.leading)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Error: \(errorMessage)")
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                Section {
                    if selectedPlatform == .mastodon {
                        signInButton(
                            title: "Sign in with Mastodon",
                            logo: "MastodonLogo",
                            disabled: isLoading || server.isEmpty
                        )
                    } else {
                        signInButton(
                            title: "Sign in with Bluesky",
                            logo: "BlueskyLogo",
                            disabled: isLoading || !isBlueskyFormValid
                        )
                    }
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
            }

            .navigationBarBackButtonHidden(true)
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        HapticEngine.tap.trigger()
                        if !preserveFormState {
                            dismiss()
                        }
                    }
                }
            }
            .alert(
                "Couldn't Add Account",
                isPresented: $showError,
                presenting: errorMessage
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.isEmpty ? "Something went wrong while signing in." : error)
            }
            .onAppear {
                // Restore form data if it was preserved
                restoreFormDataIfNeeded()
                // Set flag to indicate AddAccountView is presented
                UserDefaults.standard.set(
                    true, forKey: "AddAccountView.WasPresentedDuringBackground")
            }
            .onChange(of: scenePhase) { _, newPhase in
                handleScenePhaseChange(newPhase)
            }
            .overlay {
                if isLoading {
                    ProgressView()
                        .scaleEffect(1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color.black.opacity(0.1))
                                .frame(width: 60, height: 60)
                        )
                        .accessibilityLabel("Signing in")
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.25), value: errorMessage)
            .animation(.easeInOut(duration: 0.2), value: isLoading)
        }
    }

    private var isBlueskyFormValid: Bool {
        return !username.isEmpty && !password.isEmpty
    }

    /// Branded sign-in button — gradient-fill capsule with tinted shadow,
    /// matching the signature CTA treatment used elsewhere. Shows a
    /// progress spinner inline when isLoading.
    @ViewBuilder
    private func signInButton(title: String, logo: String, disabled: Bool) -> some View {
        let brandColor = platformColor(for: selectedPlatform)
        Button {
            HapticEngine.tap.trigger()
            addAccount()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView()
                        .progressViewStyle(CircularProgressViewStyle(tint: disabled ? .secondary : .white))
                        .scaleEffect(0.85)
                } else {
                    Image(logo)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .foregroundColor(disabled ? .secondary : .white)
                }
                Text(isLoading ? "Signing in…" : title)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(disabled ? .secondary : .white)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        disabled
                            ? AnyShapeStyle(Color(.systemGray5))
                            : AnyShapeStyle(brandColor.gradient)
                    )
                    .shadow(
                        color: disabled ? .clear : brandColor.opacity(0.28),
                        radius: 10,
                        x: 0,
                        y: 4
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(SignInButtonPressStyle())
        .disabled(disabled)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func addAccount() {
        NSLog("🔘 [AddAccountView] addAccount() called for platform: %@", selectedPlatform.rawValue)
        isLoading = true
        errorMessage = nil

        if selectedPlatform == .mastodon {
            addMastodonAccount()
        } else if selectedPlatform == .bluesky {
            addBlueskyAccount()
        }
    }

    private func addMastodonAccount() {
        NSLog("🐘 [AddAccountView] addMastodonAccount() called for server: \(server)")
        Task {
            do {
                // Handle test account creation
                #if DEBUG
                if username == "test" && password == "test" {
                    NSLog("🧪 [AddAccountView] Using test credentials")
                    createTestMastodonAccount()
                    return
                }
                #endif

                // Check if the URL is valid
                NSLog("🐘 [AddAccountView] Validating URL for: \(server)")
                guard
                    let url = URL(
                        string: server.hasPrefix("https://") ? server : "https://" + server),
                    url.scheme == "https",
                    url.host != nil
                else {
                    NSLog("❌ [AddAccountView] Invalid URL: \(server)")
                    throw NSError(
                        domain: "AddAccountView", code: 400,
                        userInfo: [NSLocalizedDescriptionKey: "Invalid server URL"]
                    )
                }

                NSLog("🐘 [AddAccountView] Requesting authentication from OAuthManager...")
                // Use OAuth flow
                let credentials = try await withCheckedThrowingContinuation { continuation in
                    oauthManager.authenticateMastodon(server: url.absoluteString) { result in
                        NSLog("🐘 [AddAccountView] Received result from OAuthManager: \(result)")
                        continuation.resume(with: result)
                    }
                }

                NSLog("✅ [AddAccountView] Authentication successful for: \(credentials.username)")
                // Add account with proper OAuth credentials
                _ = try await serviceManager.addMastodonAccountWithOAuth(
                    credentials: credentials)

                let welcomeName = "@\(credentials.username)"

                // Use proper async pattern without artificial delays
                await MainActor.run {
                    self.isLoading = false
                    HapticEngine.success.trigger()

                    // Clear the presentation flag since we're dismissing successfully
                    UserDefaults.standard.removeObject(
                        forKey: "AddAccountView.WasPresentedDuringBackground")

                    self.dismiss()

                    // Notify about the account change
                    NotificationCenter.default.post(name: .accountUpdated, object: nil)

                    // Welcome toast — confirms the account is signed in
                    // by name, after the sheet dismisses.
                    ToastManager.shared.show("Welcome, \(welcomeName)", severity: .success, duration: 1.8)
                }

            } catch {
                await MainActor.run {
                    self.isLoading = false
                    HapticEngine.error.trigger()
                    self.errorMessage = "Couldn't add account: \(error.localizedDescription)"
                    self.showError = true
                }
            }
        }
    }

    private func addBlueskyAccount() {
        Task {
            do {
                // Handle test account creation
                #if DEBUG
                if username == "test" && password == "test" {
                    createTestBlueskyAccount()
                    return
                }
                #endif

                // Make sure we have both username and password
                guard !username.isEmpty, !password.isEmpty else {
                    throw NSError(
                        domain: "AddAccountView", code: 400,
                        userInfo: [NSLocalizedDescriptionKey: "Username and password are required"]
                    )
                }

                // No need to create a URL here, the manager will handle it
                // Use the SocialServiceManager to add the Bluesky account
                let addedAccount = try await serviceManager.addBlueskyAccount(
                    username: username,
                    password: password
                )

                let welcomeName = "@\(addedAccount.username)"

                // Use proper async pattern without artificial delays
                await MainActor.run {
                    self.isLoading = false
                    HapticEngine.success.trigger()

                    // Clear the presentation flag since we're dismissing successfully
                    UserDefaults.standard.removeObject(
                        forKey: "AddAccountView.WasPresentedDuringBackground")

                    self.dismiss()

                    // Notify about the account change
                    NotificationCenter.default.post(name: .accountUpdated, object: nil)

                    // Welcome toast — confirms the account is signed in
                    // by name, after the sheet dismisses.
                    ToastManager.shared.show("Welcome, \(welcomeName)", severity: .success, duration: 1.8)
                }

            } catch {
                await MainActor.run {
                    self.isLoading = false
                    HapticEngine.error.trigger()
                    self.errorMessage = "Couldn't add account: \(error.localizedDescription)"
                    self.showError = true
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
            NSLog("Added test Mastodon account")
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
            NSLog("Added test Bluesky account")
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
            NSLog(
                "🔐 [AddAccountView] App went to background - preserving form state and presentation flag"
            )

        case .active:
            // App returned to foreground
            if wasInBackground {
                NSLog("🔐 [AddAccountView] App returned to foreground - checking for autofill")

                // Small delay to allow autofill to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    // Re-enable normal navigation after autofill completes
                    preserveFormState = false
                    NSLog("🔐 [AddAccountView] Form state preservation disabled")

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
            NSLog("🔐 [AddAccountView] No preserved form data found")
            return
        }

        // Restore form state
        selectedPlatform = formData.selectedPlatform
        server = formData.server
        username = formData.username
        password = formData.password

        NSLog("🔐 [AddAccountView] Restored form data for platform: \\(formData.selectedPlatform)")

        // Clear the preserved data after restoration
        UserDefaults.standard.removeObject(forKey: formDataKey)
    }

    private func preserveFormData() {
        let formData = FormData(
            selectedPlatform: selectedPlatform,
            server: server,
            username: username,
            password: password
        )

        if let encoded = try? JSONEncoder().encode(formData) {
            UserDefaults.standard.set(encoded, forKey: formDataKey)
            NSLog("🔐 [AddAccountView] Preserved form data for platform: \\(selectedPlatform)")
        }
    }
}

struct PlatformButton: View {
    let platform: SocialPlatform
    let isSelected: Bool
    let action: () -> Void

    private var brandColor: Color {
        switch platform {
        case .mastodon: return Color(hex: "6364FF")
        case .bluesky: return Color(hex: "0085FF")
        }
    }

    private var logoAsset: String {
        platform == .mastodon ? "MastodonLogo" : "BlueskyLogo"
    }

    var body: some View {
        Button {
            HapticEngine.selection.trigger()
            action()
        } label: {
            HStack(spacing: 10) {
                // Brand logo (template-rendered so it picks up foreground tint)
                Image(logoAsset)
                    .resizable()
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 22, height: 22)
                    .foregroundColor(isSelected ? .white : brandColor)

                Text(platform.rawValue.capitalized)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(isSelected ? .white : .primary)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(
                        isSelected
                            ? AnyShapeStyle(brandColor.gradient)
                            : AnyShapeStyle(Color(.systemGray6))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(
                                isSelected ? Color.clear : brandColor.opacity(0.18),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(
                        color: isSelected ? brandColor.opacity(0.28) : .clear,
                        radius: 10,
                        x: 0,
                        y: 4
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(PlatformButtonPressStyle())
        .accessibilityLabel(platform.rawValue.capitalized)
        .accessibilityHint(isSelected ? "Currently selected" : "Selects \(platform.rawValue.capitalized) to add an account")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private struct PlatformButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

/// Press feedback for the primary sign-in CTA — scales down + dims briefly.
private struct SignInButtonPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

struct AddAccountView_Previews: PreviewProvider {
    static var previews: some View {
        AddAccountView().environmentObject(SocialServiceManager())
    }
}
