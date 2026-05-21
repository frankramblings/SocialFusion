import SwiftUI

extension View {
    func apply<Content: View>(@ViewBuilder _ transform: (Self) -> Content) -> Content {
        transform(self)
    }
}

/// Enhanced empty state view that handles various edge cases with helpful guidance
struct EnhancedEmptyStateView: View {
    let state: EmptyState
    let onRetry: (() -> Void)?
    let onPrimaryAction: (() -> Void)?

    @EnvironmentObject private var edgeCase: EdgeCaseHandler
    @Environment(\.colorScheme) private var colorScheme

    enum EmptyState: Equatable {
        case noAccounts
        case noInternet
        case noPostsYet
        case authenticationExpired
        case serverError
        case loading
        case memoryPressure
        case rateLimited(retryAfter: TimeInterval?)

        static func == (lhs: EmptyState, rhs: EmptyState) -> Bool {
            switch (lhs, rhs) {
            case (.noAccounts, .noAccounts),
                (.noInternet, .noInternet),
                (.noPostsYet, .noPostsYet),
                (.authenticationExpired, .authenticationExpired),
                (.serverError, .serverError),
                (.loading, .loading),
                (.memoryPressure, .memoryPressure):
                return true
            case (.rateLimited(let lhsRetry), .rateLimited(let rhsRetry)):
                return lhsRetry == rhsRetry
            default:
                return false
            }
        }

        var icon: String {
            switch self {
            case .noAccounts:
                return "person.crop.circle.badge.plus"
            case .noInternet:
                return "wifi.slash"
            case .noPostsYet:
                return "timeline.selection"
            case .authenticationExpired:
                return "key.slash"
            case .serverError:
                return "server.rack"
            case .loading:
                return "arrow.clockwise"
            case .memoryPressure:
                return "memorychip.fill"
            case .rateLimited:
                return "clock.badge.exclamationmark"
            }
        }

        var title: String {
            switch self {
            case .noAccounts:
                return "Welcome to SocialFusion"
            case .noInternet:
                return "No Internet Connection"
            case .noPostsYet:
                return "Your Timeline is Empty"
            case .authenticationExpired:
                return "Authentication Required"
            case .serverError:
                return "Server Unavailable"
            case .loading:
                return "Loading Your Timeline"
            case .memoryPressure:
                return "Memory Usage High"
            case .rateLimited:
                return "Rate Limited"
            }
        }

        var message: String {
            switch self {
            case .noAccounts:
                return
                    "Add your Mastodon or Bluesky accounts to get started viewing your social timeline."
            case .noInternet:
                return
                    "Check your internet connection. You can still view cached posts while offline."
            case .noPostsYet:
                return
                    "Follow some accounts or check back later for new posts to appear in your timeline."
            case .authenticationExpired:
                return "Your account credentials have expired. Please re-authenticate to continue."
            case .serverError:
                return "The servers are temporarily unavailable. Please try again in a few moments."
            case .loading:
                return "Fetching the latest posts from your social accounts..."
            case .memoryPressure:
                return
                    "The app is using a lot of memory. Some features may be limited until memory is freed."
            case .rateLimited(let retryAfter):
                if let retryAfter = retryAfter {
                    let minutes = Int(retryAfter / 60)
                    let waitPhrase: String
                    if minutes > 0 {
                        waitPhrase = "\(minutes) minute\(minutes == 1 ? "" : "s")"
                    } else {
                        waitPhrase = "a moment"
                    }
                    return
                        "You've made too many requests. Please wait \(waitPhrase) before trying again."
                } else {
                    return "You've made too many requests. Please wait before trying again."
                }
            }
        }

        var primaryActionTitle: String? {
            switch self {
            case .noAccounts:
                return "Add Account"
            case .noInternet:
                return "Retry"
            case .noPostsYet:
                return "Refresh"
            case .authenticationExpired:
                return "Re-authenticate"
            case .serverError:
                return "Try Again"
            case .loading:
                return nil
            case .memoryPressure:
                return "Clear Cache"
            case .rateLimited:
                return "OK"
            }
        }

        var secondaryActionTitle: String? {
            switch self {
            case .noAccounts:
                return nil
            case .noInternet:
                return "View Cached"
            case .noPostsYet:
                return "Find Accounts"
            case .authenticationExpired:
                return "Later"
            case .serverError:
                return "Check Status"
            case .loading:
                return "Cancel"
            case .memoryPressure:
                return "Continue"
            case .rateLimited:
                return nil
            }
        }

        var color: Color {
            switch self {
            case .noAccounts:
                return .blue
            case .noInternet:
                return .orange
            case .noPostsYet:
                return .secondary
            case .authenticationExpired:
                return .red
            case .serverError:
                return .red
            case .loading:
                return .blue
            case .memoryPressure:
                return .yellow
            case .rateLimited:
                return .orange
            }
        }

        var showProgressIndicator: Bool {
            switch self {
            case .loading:
                return true
            default:
                return false
            }
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            // Icon and progress indicator
            VStack(spacing: 16) {
                if state.showProgressIndicator {
                    ProgressView()
                        .scaleEffect(1.2)
                        .tint(state.color)
                        .accessibilityLabel(state.title)
                } else {
                    Image(systemName: state.icon)
                        .font(.system(size: 64, weight: .light))
                        .foregroundColor(state.color)
                        .apply { view in
                            if #available(iOS 17.0, *) {
                                view.symbolEffect(.pulse.byLayer, options: .repeating)
                            } else {
                                view
                            }
                        }
                        // Decorative — title/message below name the state.
                        .accessibilityHidden(true)
                }
            }

            // Title and message
            VStack(spacing: 12) {
                Text(state.title)
                    .font(.title2)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)

                Text(state.message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .fixedSize(horizontal: false, vertical: true)
            }
            // Combine the empty-state intro into one VoiceOver swipe so
            // users hear "Welcome to SocialFusion. Add your first account
            // …" as a single announcement instead of as two stops.
            .accessibilityElement(children: .combine)

            // System status (if relevant)
            if shouldShowSystemStatus {
                systemStatusView
            }

            // Action buttons — refined with gradient fill and subtle shadow on primary,
            // soft tinted background on secondary
            VStack(spacing: 10) {
                if let primaryTitle = state.primaryActionTitle {
                    Button {
                        HapticEngine.tap.trigger()
                        handlePrimaryAction()
                    } label: {
                        HStack(spacing: 8) {
                            if state == .loading {
                                ProgressView()
                                    .scaleEffect(0.8)
                                    .tint(.white)
                            }
                            Text(primaryTitle)
                                .font(.headline)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 15)
                        .foregroundColor(.white)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(state.color.gradient)
                                .shadow(color: state.color.opacity(0.28), radius: 12, x: 0, y: 4)
                        )
                    }
                    .buttonStyle(EmptyStatePressStyle())
                    .disabled(state == .loading)
                }

                if let secondaryTitle = state.secondaryActionTitle {
                    Button {
                        HapticEngine.tap.trigger()
                        handleSecondaryAction()
                    } label: {
                        Text(secondaryTitle)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundColor(.primary.opacity(0.7))
                            .background(
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.05))
                            )
                    }
                    .buttonStyle(EmptyStatePressStyle())
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private struct EmptyStatePressStyle: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
                .opacity(configuration.isPressed ? 0.9 : 1.0)
                .animation(
                    .interactiveSpring(response: 0.25, dampingFraction: 0.8),
                    value: configuration.isPressed
                )
        }
    }

    private var shouldShowSystemStatus: Bool {
        switch state {
        case .noInternet, .serverError, .memoryPressure:
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private var systemStatusView: some View {
        VStack(spacing: 8) {
            HStack(spacing: 4) {
                Circle()
                    .fill(networkStatusColor)
                    .frame(width: 8, height: 8)
                Text(edgeCase.networkStatus.userFriendlyDescription)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if edgeCase.memoryPressure != .normal {
                HStack(spacing: 4) {
                    Circle()
                        .fill(memoryStatusColor)
                        .frame(width: 8, height: 8)
                    Text(edgeCase.memoryPressure.userFriendlyDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color.secondary.opacity(0.1))
        .cornerRadius(8)
    }

    private var networkStatusColor: Color {
        switch edgeCase.networkStatus {
        case .available:
            return .green
        case .limited, .expensive:
            return .yellow
        case .unavailable:
            return .red
        case .unknown:
            return .gray
        }
    }

    private var memoryStatusColor: Color {
        switch edgeCase.memoryPressure {
        case .normal:
            return .green
        case .elevated:
            return .yellow
        case .critical:
            return .red
        }
    }

    private func handlePrimaryAction() {
        // Tap haptic at the funnel so every primary action — retry,
        // re-auth, add-account, cleanup — gets the same tactile
        // confirmation. Matches the retry-haptic vocabulary used by
        // the other empty-state and error surfaces (3929dc2, 6028402,
        // 23a69b4).
        HapticEngine.tap.trigger()
        switch state {
        case .noAccounts:
            NotificationCenter.default.post(name: .showAccountSetup, object: nil)
        case .noInternet:
            onRetry?()
        case .noPostsYet:
            onRetry?()
        case .authenticationExpired:
            NotificationCenter.default.post(name: .showAccountReauth, object: nil)
        case .serverError:
            onRetry?()
        case .loading:
            break  // No action for loading state
        case .memoryPressure:
            NotificationCenter.default.post(name: .performMemoryCleanup, object: nil)
        case .rateLimited:
            break  // Just dismiss
        }

        onPrimaryAction?()
    }

    private func handleSecondaryAction() {
        // Match the primary-action funnel haptic (3e2c4d0) so both
        // buttons on this surface give the same tactile confirmation.
        HapticEngine.tap.trigger()
        switch state {
        case .noInternet:
            // Show cached content - this could trigger a different view mode
            NotificationCenter.default.post(name: .showCachedContent, object: nil)
        case .noPostsYet:
            // Navigate to account discovery or suggestions
            NotificationCenter.default.post(name: .showAccountDiscovery, object: nil)
        case .authenticationExpired:
            // Dismiss and continue with limited functionality
            break
        case .serverError:
            // Open status page or help
            if let url = URL(string: "https://status.socialfusion.app") {
                UIApplication.shared.open(url)
            }
        case .loading:
            // Cancel loading operation
            NotificationCenter.default.post(name: .cancelCurrentOperation, object: nil)
        case .memoryPressure:
            // Continue with current memory usage
            break
        default:
            break
        }
    }
}

// MARK: - Additional Notification Names

extension Notification.Name {
    static let showCachedContent = Notification.Name("showCachedContent")
    static let showAccountDiscovery = Notification.Name("showAccountDiscovery")
    static let cancelCurrentOperation = Notification.Name("cancelCurrentOperation")
}

// MARK: - Preview

struct EnhancedEmptyStateView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            EnhancedEmptyStateView(
                state: .noAccounts,
                onRetry: nil,
                onPrimaryAction: nil
            )
            .previewDisplayName("No Accounts")

            EnhancedEmptyStateView(
                state: .noInternet,
                onRetry: {},
                onPrimaryAction: nil
            )
            .previewDisplayName("No Internet")

            EnhancedEmptyStateView(
                state: .authenticationExpired,
                onRetry: nil,
                onPrimaryAction: nil
            )
            .previewDisplayName("Auth Expired")

            EnhancedEmptyStateView(
                state: .loading,
                onRetry: nil,
                onPrimaryAction: nil
            )
            .previewDisplayName("Loading")

            EnhancedEmptyStateView(
                state: .rateLimited(retryAfter: 300),
                onRetry: nil,
                onPrimaryAction: nil
            )
            .previewDisplayName("Rate Limited")
        }
        .environmentObject(EdgeCaseHandler.shared)
    }
}
