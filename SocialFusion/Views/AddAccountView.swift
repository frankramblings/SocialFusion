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
                    Button("Add", action: addAccount)
                        .disabled(
                            (!platformSelected || isLoading)
                                || (selectedPlatform == .mastodon && isOAuthFlow
                                    && !isAuthCodeEntered)
                        )
                }

                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
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

        Task {
            do {
                switch selectedPlatform {
                case .mastodon:
                    errorMessage = "Please use the OAuth authentication flow"
                    isLoading = false
                    return

                case .bluesky:
                    let userInput = username.trimmingCharacters(in: .whitespacesAndNewlines)
                    let passwordInput = password.trimmingCharacters(in: .whitespacesAndNewlines)

                    // Basic validation
                    guard !userInput.isEmpty else {
                        throw NSError(
                            domain: "AddAccountView", code: 400,
                            userInfo: [
                                NSLocalizedDescriptionKey:
                                    "Please enter your Bluesky username or email."
                            ])
                    }

                    guard !passwordInput.isEmpty else {
                        throw NSError(
                            domain: "AddAccountView", code: 400,
                            userInfo: [
                                NSLocalizedDescriptionKey: "Please enter your Bluesky app password."
                            ])
                    }

                    // Now attempt to authenticate with Bluesky
                    do {
                        _ = try await serviceManager.addBlueskyAccount(
                            username: userInput,
                            password: passwordInput
                        )

                        print("Successfully authenticated with Bluesky")
                    } catch {
                        // Provide more specific error handling for Bluesky authentication issues
                        let nsError = error as NSError
                        if nsError.domain == "BlueskyService" {
                            throw NSError(
                                domain: "AddAccountView", code: nsError.code,
                                userInfo: [
                                    NSLocalizedDescriptionKey:
                                        "Authentication failed: \(nsError.localizedDescription). Please verify your credentials and try again."
                                ])
                        }
                        throw error
                    }
                }

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
