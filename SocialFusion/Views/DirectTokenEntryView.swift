import SwiftUI

struct DirectTokenEntryView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @Environment(\.dismiss) var dismiss

    @State private var serverURL = ""
    @State private var accessToken = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil

    var body: some View {
        Form {
            Section(header: Text("Server Information")) {
                TextField("Server URL (e.g. mastodon.social)", text: $serverURL)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled(true)
            }

            Section(header: Text("Authentication")) {
                SecureField("Access Token", text: $accessToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)

                Text(
                    "You can obtain an access token from your Mastodon's instance settings page, under Development → Your applications."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section {
                Button {
                    HapticEngine.tap.trigger()
                    addAccount()
                } label: {
                    HStack(spacing: 8) {
                        if isLoading {
                            ProgressView()
                                .scaleEffect(0.85)
                                .tint(.white)
                        }
                        Text(isLoading ? "Adding…" : "Add Account")
                            .font(.headline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    // White text on accent gradient (enabled) reads correctly.
                    // When disabled, the gray background isn't dark enough for
                    // white text — use .secondary so the label retains contrast.
                    .foregroundColor(isFormValid ? .white : .secondary)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(
                                isFormValid
                                    ? AnyShapeStyle(Color.accentColor.gradient)
                                    : AnyShapeStyle(Color(.systemGray5))
                            )
                            .shadow(
                                color: isFormValid ? Color.accentColor.opacity(0.28) : .clear,
                                radius: 10,
                                x: 0,
                                y: 4
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isLoading || !isFormValid)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                .accessibilityHint(isFormValid ? "Adds this account to SocialFusion" : "Fill in the server and access token to continue")
            }

            if let error = errorMessage {
                Section {
                    Label {
                        Text(error)
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(Color.red.gradient)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .foregroundColor(.red)
                }
            }

            if let success = successMessage {
                Section {
                    Label {
                        Text(success)
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Color.green.gradient)
                            .symbolRenderingMode(.hierarchical)
                    }
                    .foregroundColor(.green)
                }
            }
        }
    }

    private var isFormValid: Bool {
        !serverURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !accessToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func addAccount() {
        isLoading = true
        errorMessage = nil
        successMessage = nil

        // Clean up the inputs
        let trimmedServer = serverURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedToken = accessToken.trimmingCharacters(in: .whitespacesAndNewlines)

        Task {
            do {
                let account = try await serviceManager.addMastodonAccountWithToken(
                    serverURL: trimmedServer,
                    accessToken: trimmedToken
                )

                await MainActor.run {
                    isLoading = false
                    successMessage = "Successfully added account: \(account.username)"
                    HapticEngine.success.trigger()

                    // Clear form after success
                    serverURL = ""
                    accessToken = ""

                    let welcomeName = "@\(account.username)"

                    // Dismiss after a short delay so the inline success
                    // message reads, then post the global welcome toast
                    // so the user gets a matching confirmation in the
                    // parent view (consistent with the OAuth/Bluesky
                    // add flows).
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        dismiss()
                        ToastManager.shared.show("Welcome, \(welcomeName)", severity: .success, duration: 1.8)
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Couldn't add account: \(error.localizedDescription)"
                    HapticEngine.error.trigger()
                }
            }
        }
    }
}

struct DirectTokenEntryView_Previews: PreviewProvider {
    static var previews: some View {
        DirectTokenEntryView()
            .environmentObject(SocialServiceManager())
    }
}
