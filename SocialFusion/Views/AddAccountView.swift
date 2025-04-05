import Combine
import Foundation
import SwiftUI
import UIKit

struct AddAccountView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @Environment(\.presentationMode) var presentationMode

    @State private var selectedPlatform: SocialPlatform = .mastodon
    @State private var server = ""
    @State private var username = ""
    @State private var password = ""
    @State private var accessToken = ""
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var authMethod: AuthMethod = .oauth
    @State private var platformSelected = true
    @State private var isOAuthFlow = true
    @State private var isAuthCodeEntered = false
    @State private var showWebAuthFailure = false

    enum AuthMethod: String, CaseIterable, Identifiable {
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
                        errorMessage = ""

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
                            .toolbar(content: {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") {
                                        UIApplication.shared.sendAction(
                                            #selector(UIResponder.resignFirstResponder), to: nil,
                                            from: nil, for: nil)
                                    }
                                }
                            })

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
                            .toolbar(content: {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") {
                                        UIApplication.shared.sendAction(
                                            #selector(UIResponder.resignFirstResponder), to: nil,
                                            from: nil, for: nil)
                                    }
                                }
                            })

                        SecureField("App Password", text: $password)
                            .toolbar(content: {
                                ToolbarItemGroup(placement: .keyboard) {
                                    Spacer()
                                    Button("Done") {
                                        UIApplication.shared.sendAction(
                                            #selector(UIResponder.resignFirstResponder), to: nil,
                                            from: nil, for: nil)
                                    }
                                }
                            })

                        Text(
                            "Use an app password from Bluesky settings. Go to Settings → App Passwords in your Bluesky account to create one."
                        )
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                    }
                }

                if !errorMessage.isEmpty {
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
                                    Image("BlueskyLogo")
                                        .resizable()
                                        .renderingMode(.template)
                                        .aspectRatio(contentMode: .fit)
                                        .frame(width: 20, height: 20)
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
            .navigationTitle("Add Account")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    // Only show this button for Mastodon OAuth flow if needed
                    if selectedPlatform == .mastodon && authMethod == .oauth && isOAuthFlow
                        && isAuthCodeEntered
                    {
                        Button("Add") {
                            addAccount()
                        }
                        .disabled(isLoading)
                    }
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            }
            // Add an onAppear to debug account setup
            .onAppear {
                print("AddAccountView appeared")
                // Set defaults
                if selectedPlatform == .bluesky {
                    authMethod = .oauth
                    server = "bsky.social"
                }
            }
            .alert(isPresented: $showWebAuthFailure) {
                Alert(
                    title: Text("Authentication Failed"),
                    message: Text(
                        "Could not authenticate with \(selectedPlatform.rawValue). Please try again or use a different method."
                    ),
                    dismissButton: .default(Text("OK"))
                )
            }
        }
    }

    private var isBlueskyFormValid: Bool {
        return !username.isEmpty && !password.isEmpty
    }

    private func addMastodonAccount() {
        isLoading = true
        errorMessage = ""

        // Get the trimmed server value
        let trimmedServer = server.trimmingCharacters(in: .whitespacesAndNewlines)

        // Validate the server input
        guard !trimmedServer.isEmpty else {
            errorMessage = "Please enter a server address"
            isLoading = false
            return
        }

        // Check if we're using OAuth or manual token
        if authMethod == .manual {
            // Validate access token
            let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedToken.isEmpty else {
                errorMessage = "Please enter an access token"
                isLoading = false
                return
            }

            // Use the manual token method
            Task {
                do {
                    let _ = try await serviceManager.addMastodonAccountWithToken(
                        serverURL: trimmedServer,
                        accessToken: trimmedToken
                    )

                    await MainActor.run {
                        isLoading = false
                        presentationMode.wrappedValue.dismiss()
                    }
                } catch {
                    await MainActor.run {
                        isLoading = false
                        handleError(error)
                    }
                }
            }
        } else {
            // Use the OAuth method from the service manager
            Task {
                do {
                    let _ = try await serviceManager.addMastodonAccountWithOAuth(
                        server: trimmedServer)

                    // Update the UI on the main thread
                    await MainActor.run {
                        isLoading = false
                        presentationMode.wrappedValue.dismiss()
                    }
                } catch {
                    // Handle errors and update the UI on the main thread
                    await MainActor.run {
                        isLoading = false
                        handleError(error)
                    }
                }
            }
        }
    }

    private func handleError(_ error: Error) {
        // Check the error details
        if let serviceError = error as? ServiceError {
            // Handle specific service errors with better messages
            errorMessage = serviceError.localizedDescription
        } else {
            // For general errors (including network issues)
            let nsError = error as NSError
            if nsError.domain.contains("URLError") {
                errorMessage =
                    "Network error: Please check your internet connection and try again later."
            } else {
                errorMessage = "Failed to add account: \(error.localizedDescription)"
            }
        }
    }

    private func addAccount() {
        isLoading = true
        errorMessage = ""

        // Add debugging output
        print("Adding \(selectedPlatform.rawValue) account")
        print("Server: \(server)")
        print("Username: \(username)")

        if selectedPlatform == .mastodon {
            addMastodonAccount()
        } else {
            addBlueskyAccount()
        }
    }

    private func addBlueskyAccount() {
        guard !username.isEmpty && !password.isEmpty else {
            errorMessage = "Please enter both username and password."
            isLoading = false
            return
        }

        Task {
            do {
                print("Starting Bluesky authentication...")

                // Create a temporary dummy account if needed for testing
                if username == "test" && password == "test" {
                    let tempAccount = SocialAccount(
                        id: "test-bluesky-\(Date().timeIntervalSince1970)",
                        username: "test_user",
                        displayName: "Test User",
                        serverURL: "bsky.social",
                        platform: .bluesky,
                        accessToken: "test-token",
                        refreshToken: nil
                    )

                    DispatchQueue.main.async {
                        // Always add account to the correct platform array based on its platform property
                        if tempAccount.platform == .bluesky {
                            self.serviceManager.blueskyAccounts.append(tempAccount)
                            print("Added test Bluesky account to blueskyAccounts array")
                        } else {
                            self.serviceManager.mastodonAccounts.append(tempAccount)
                            print("Added test Mastodon account to mastodonAccounts array")
                        }

                        // Save all accounts to persistent storage
                        Task {
                            await self.serviceManager.saveAllAccounts()
                        }

                        // Also select this account for immediate use
                        self.serviceManager.selectedAccountIds = [tempAccount.id]
                        UserDefaults.standard.set([tempAccount.id], forKey: "selectedAccountIds")

                        print(
                            "Created account: \(tempAccount.username) with profile image URL: \(String(describing: tempAccount.profileImageURL))"
                        )

                        self.isLoading = false
                        self.presentationMode.wrappedValue.dismiss()

                        // Post a notification that accounts changed
                        NotificationCenter.default.post(
                            name: Notification.Name("accountsChanged"), object: nil)
                    }
                    return
                }

                let account = try await serviceManager.addBlueskyAccount(
                    username: username,
                    password: password
                )

                DispatchQueue.main.async {
                    print("Successfully added Bluesky account: \(account.username)")

                    // Post a notification that accounts changed
                    NotificationCenter.default.post(
                        name: Notification.Name("accountsChanged"), object: nil)

                    self.isLoading = false
                    self.presentationMode.wrappedValue.dismiss()
                }
            } catch {
                DispatchQueue.main.async {
                    print("Error adding Bluesky account: \(error.localizedDescription)")
                    self.errorMessage = "Authentication failed: \(error.localizedDescription)"
                    self.isLoading = false
                }
            }
        }
    }

    private func getLogoName(for platform: SocialPlatform) -> String {
        switch platform {
        case .mastodon:
            return "MastodonLogo"
        case .bluesky:
            return "BlueskyLogo"
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
                        // Use the SVG logo image with appropriate sizing
                        Image(getLogoName(for: platform))
                            .resizable()
                            .renderingMode(.template)
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
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

    private func getLogoName(for platform: SocialPlatform) -> String {
        switch platform {
        case .mastodon:
            return "MastodonLogo"
        case .bluesky:
            return "BlueskyLogo"
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
        let manager = SocialServiceManager()
        AddAccountView().environmentObject(manager)
    }
}
