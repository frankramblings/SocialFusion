import SwiftUI

/// Debug view to help troubleshoot Bluesky content issues
struct DebugBlueskyView: View {
    @EnvironmentObject var serviceManager: SocialServiceManager
    @State private var debugInfo: String = "Loading..."
    @State private var isRefreshing = false
    @State private var lastRefreshResult: String = ""

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Account Status Section
                    GroupBox("Bluesky Accounts") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Total Bluesky Accounts: \(serviceManager.blueskyAccounts.count)")
                                .font(.headline)

                            ForEach(serviceManager.blueskyAccounts, id: \.id) { account in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("@\(account.username)")
                                        .font(.subheadline)
                                        .fontWeight(.medium)

                                    Text("Server: \(account.serverURL?.absoluteString ?? "None")")
                                        .font(.caption)
                                        .foregroundColor(.secondary)

                                    Text("Token Status: \(tokenStatus(for: account))")
                                        .font(.caption)
                                        .foregroundColor(
                                            tokenStatus(for: account) == "Valid" ? .green : .red)

                                    Text("Selected: \(isAccountSelected(account) ? "Yes" : "No")")
                                        .font(.caption)
                                        .foregroundColor(
                                            isAccountSelected(account) ? .green : .orange)
                                }
                                .padding(.vertical, 4)
                                .padding(.horizontal, 8)
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                            }

                            if serviceManager.blueskyAccounts.isEmpty {
                                Text("No Bluesky accounts configured")
                                    .foregroundColor(.orange)
                                    .italic()
                            }
                        }
                    }

                    // Timeline Status Section
                    GroupBox("Timeline Status") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Total Posts: \(serviceManager.unifiedTimeline.count)")
                            Text("Bluesky Posts: \(blueskyPostCount)")
                            Text("Mastodon Posts: \(mastodonPostCount)")
                            Text("Loading: \(serviceManager.isLoadingTimeline ? "Yes" : "No")")
                                .foregroundColor(
                                    serviceManager.isLoadingTimeline ? .orange : .primary)
                            Text("Has Next Page: \(serviceManager.hasNextPage ? "Yes" : "No")")
                        }
                    }

                    // Selection Status Section
                    GroupBox("Account Selection") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                "Selected Account IDs: \(Array(serviceManager.selectedAccountIds).joined(separator: ", "))"
                            )
                            Text(
                                "Selection Mode: \(serviceManager.selectedAccountIds.contains("all") ? "All Accounts" : "Specific Accounts")"
                            )
                        }
                    }

                    // Debug Actions Section
                    GroupBox("Debug Actions") {
                        VStack(spacing: 12) {
                            Button("Force Refresh Timeline") {
                                Task {
                                    await forceRefreshTimeline()
                                }
                            }
                            .disabled(isRefreshing)

                            Button("Test Bluesky Connection") {
                                Task {
                                    await testBlueskyConnection()
                                }
                            }
                            .disabled(isRefreshing)

                            Button("Reset Account Selection to All") {
                                serviceManager.selectedAccountIds = ["all"]
                                Task {
                                    try? await serviceManager.refreshTimeline(force: true)
                                }
                            }

                            Button("Full Diagnostic Test") {
                                Task {
                                    await runFullDiagnostic()
                                }
                            }
                            .disabled(isRefreshing)
                        }
                    }

                    // Recent Activity Section
                    if !lastRefreshResult.isEmpty {
                        GroupBox("Last Refresh Result") {
                            Text(lastRefreshResult)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }

                    // Debug Info Section
                    GroupBox("Debug Information") {
                        Text(debugInfo)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Bluesky Debug")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                updateDebugInfo()
            }
        }
    }

    private var blueskyPostCount: Int {
        serviceManager.unifiedTimeline.filter { $0.platform == .bluesky }.count
    }

    private var mastodonPostCount: Int {
        serviceManager.unifiedTimeline.filter { $0.platform == .mastodon }.count
    }

    private func tokenStatus(for account: SocialAccount) -> String {
        guard let token = account.getAccessToken() else {
            return "Missing"
        }

        if account.isTokenExpired {
            return "Expired"
        }

        return "Valid"
    }

    private func isAccountSelected(_ account: SocialAccount) -> Bool {
        return serviceManager.selectedAccountIds.contains("all")
            || serviceManager.selectedAccountIds.contains(account.id)
    }

    private func updateDebugInfo() {
        var info = "=== Debug Information ===\n"
        info += "Total Accounts: \(serviceManager.accounts.count)\n"
        info += "Bluesky Accounts: \(serviceManager.blueskyAccounts.count)\n"
        info += "Mastodon Accounts: \(serviceManager.mastodonAccounts.count)\n"
        info += "Selected IDs: \(serviceManager.selectedAccountIds)\n"
        info += "Timeline Posts: \(serviceManager.unifiedTimeline.count)\n"
        info += "Loading: \(serviceManager.isLoadingTimeline)\n"
        info += "Has Next Page: \(serviceManager.hasNextPage)\n"

        // Check for recent posts by platform
        let recentBluesky = serviceManager.unifiedTimeline.filter {
            $0.platform == .bluesky && $0.createdAt > Date().addingTimeInterval(-24 * 60 * 60)
        }.count
        let recentMastodon = serviceManager.unifiedTimeline.filter {
            $0.platform == .mastodon && $0.createdAt > Date().addingTimeInterval(-24 * 60 * 60)
        }.count

        info += "Recent Bluesky Posts (24h): \(recentBluesky)\n"
        info += "Recent Mastodon Posts (24h): \(recentMastodon)\n"

        debugInfo = info
    }

    private func forceRefreshTimeline() async {
        isRefreshing = true
        lastRefreshResult = "Refreshing..."

        do {
            try await serviceManager.refreshTimeline(force: true)
            await MainActor.run {
                lastRefreshResult = "Success! Loaded \(serviceManager.unifiedTimeline.count) posts"
                updateDebugInfo()
            }
        } catch {
            await MainActor.run {
                lastRefreshResult = "Error: \(error.localizedDescription)"
            }
        }

        isRefreshing = false
    }

    private func testBlueskyConnection() async {
        isRefreshing = true
        lastRefreshResult = "Testing Bluesky connection..."

        guard let blueskyAccount = serviceManager.blueskyAccounts.first else {
            lastRefreshResult = "No Bluesky account found"
            isRefreshing = false
            return
        }

        do {
            let result = try await serviceManager.blueskyService.fetchHomeTimeline(
                for: blueskyAccount, limit: 5)
            await MainActor.run {
                lastRefreshResult =
                    "Bluesky connection successful! Fetched \(result.posts.count) posts"
            }
        } catch {
            await MainActor.run {
                lastRefreshResult = "Bluesky connection failed: \(error.localizedDescription)"
            }
        }

        isRefreshing = false
    }

    private func runFullDiagnostic() async {
        isRefreshing = true
        lastRefreshResult = "Running full diagnostic..."

        var diagnosticResult = "=== FULL DIAGNOSTIC ===\n"

        // Step 1: Check accounts
        diagnosticResult += "Bluesky Accounts: \(serviceManager.blueskyAccounts.count)\n"
        diagnosticResult += "Mastodon Accounts: \(serviceManager.mastodonAccounts.count)\n"
        diagnosticResult += "Total Accounts: \(serviceManager.accounts.count)\n"
        diagnosticResult +=
            "Selected IDs: \(Array(serviceManager.selectedAccountIds).joined(separator: ", "))\n"

        // Step 2: Check current timeline
        let currentBlueskyCount = serviceManager.unifiedTimeline.filter { $0.platform == .bluesky }
            .count
        let currentMastodonCount = serviceManager.unifiedTimeline.filter {
            $0.platform == .mastodon
        }.count
        diagnosticResult +=
            "Current Timeline - Bluesky: \(currentBlueskyCount), Mastodon: \(currentMastodonCount)\n"

        // Step 3: Reset account selection and test
        serviceManager.selectedAccountIds = ["all"]
        diagnosticResult += "Reset selection to 'all'\n"

        // Step 4: Test Bluesky connection directly
        if let blueskyAccount = serviceManager.blueskyAccounts.first {
            do {
                let result = try await serviceManager.blueskyService.fetchHomeTimeline(
                    for: blueskyAccount, limit: 5)
                diagnosticResult +=
                    "Direct Bluesky API test: SUCCESS - \(result.posts.count) posts\n"
            } catch {
                diagnosticResult +=
                    "Direct Bluesky API test: FAILED - \(error.localizedDescription)\n"
            }
        } else {
            diagnosticResult += "Direct Bluesky API test: NO ACCOUNT FOUND\n"
        }

        // Step 5: Force timeline refresh
        do {
            try await serviceManager.refreshTimeline(force: true)
            let newBlueskyCount = serviceManager.unifiedTimeline.filter { $0.platform == .bluesky }
                .count
            let newMastodonCount = serviceManager.unifiedTimeline.filter {
                $0.platform == .mastodon
            }.count
            diagnosticResult +=
                "After refresh - Bluesky: \(newBlueskyCount), Mastodon: \(newMastodonCount)\n"

            if newBlueskyCount == 0 && serviceManager.blueskyAccounts.count > 0 {
                diagnosticResult += "❌ ISSUE CONFIRMED: No Bluesky posts despite having accounts\n"
                diagnosticResult += "Suggested fix: Check token expiration and re-authenticate\n"
            } else if newBlueskyCount > 0 {
                diagnosticResult += "✅ SUCCESS: Bluesky posts are now appearing\n"
            }
        } catch {
            diagnosticResult += "Timeline refresh FAILED: \(error.localizedDescription)\n"
        }

        await MainActor.run {
            lastRefreshResult = diagnosticResult
            updateDebugInfo()
        }

        isRefreshing = false
    }
}

#Preview {
    DebugBlueskyView()
        .environmentObject(SocialServiceManager())
}
