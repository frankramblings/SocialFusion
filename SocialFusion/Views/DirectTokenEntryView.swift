import SwiftUI

struct DirectTokenEntryView: View {
    @EnvironmentObject private var serviceManager: SocialServiceManager
    @Environment(\.presentationMode) var presentationMode

    @State private var serverURL = ""
    @State private var accessToken = ""
    @State private var isLoading = false
    @State private var errorMessage: String? = nil
    @State private var successMessage: String? = nil
    @FocusState private var focusedField: Field?

    private enum Field { case serverURL, accessToken }

    var body: some View {
        Form {
            Section(header: Text("Server Information")) {
                TextField("Server URL (e.g. mastodon.social)", text: $serverURL)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .serverURL)
                    .onSubmit { focusedField = .accessToken }
                    .submitLabel(.next)
            }

            Section(header: Text("Authentication")) {
                SecureField("Access Token", text: $accessToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .accessToken)
                    .submitLabel(.done)
                    .onSubmit { if isFormValid { addAccount() } }

                Text(
                    "You can obtain an access token from your Mastodon's instance settings page, under Development → Your applications."
                )
                .font(.caption)
                .foregroundColor(.secondary)
            }

            Section {
                Button(action: addAccount) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                    } else {
                        Text("Add Account")
                            .frame(maxWidth: .infinity)
                            .foregroundColor(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(isFormValid ? Color.blue : Color.gray)
                .cornerRadius(10)
                .disabled(isLoading || !isFormValid)
            }

            if let error = errorMessage {
                Section {
                    Text(error)
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }

            if let success = successMessage {
                Section {
                    Text(success)
                        .foregroundColor(.green)
                        .font(.footnote)
                }
            }
        }
        .onAppear {
            // Auto-focus the server field — the only reason a user is on
            // this sheet is to type a URL and a token. One less tap to
            // start the flow.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                focusedField = .serverURL
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

                    // Clear form after success
                    serverURL = ""
                    accessToken = ""

                    // Dismiss after a short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        presentationMode.wrappedValue.dismiss()
                    }
                }
            } catch {
                await MainActor.run {
                    isLoading = false
                    errorMessage = "Failed to add account: \(error.localizedDescription)"
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
