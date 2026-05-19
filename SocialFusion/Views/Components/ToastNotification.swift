import SwiftUI

@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    /// One user-visible toast. Plain ones auto-dismiss; retry-bearing toasts
    /// are persistent (no auto-dismiss) so the user has time to act on
    /// them — matches Apple HIG for "inform + offer recovery."
    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        let style: Style
        let retry: RetryAction?

        enum Style: Equatable {
            case info
            case error
        }

        /// Wrapper so closures don't break Equatable. Identity is the
        /// RetryAction's UUID, not the closure pointer.
        struct RetryAction: Equatable {
            let id = UUID()
            let label: String
            let perform: @MainActor () -> Void

            static func == (lhs: RetryAction, rhs: RetryAction) -> Bool {
                lhs.id == rhs.id
            }
        }

        static func == (lhs: Toast, rhs: Toast) -> Bool {
            lhs.id == rhs.id && lhs.message == rhs.message
                && lhs.style == rhs.style && lhs.retry == rhs.retry
        }
    }

    @Published private(set) var currentToast: Toast?

    /// Show a transient info toast. Auto-dismisses after `duration`.
    func show(_ message: String, duration: TimeInterval = 2.0) {
        present(Toast(message: message, style: .info, retry: nil), duration: duration)
    }

    /// Show an error toast with an actionable retry button. Persistent —
    /// stays on screen until the user taps Retry, swipes away, or until
    /// another show() supersedes it.
    ///
    /// Fires an error haptic on present: the toast slides in from the top
    /// and is easy to miss if the user's eye is elsewhere on screen.
    /// The haptic draws attention to the recoverable failure so they
    /// notice the Retry affordance.
    func showError(_ message: String, retryLabel: String = "Retry", retry: @escaping @MainActor () -> Void) {
        // Suppress duplicate haptics when the same error message
        // re-appears (e.g., the timeline's onChange fires twice as the
        // controller's error stabilizes). Identity by message is good
        // enough — the toast's own dedup logic uses the same key.
        if currentToast?.message != message || currentToast?.style != .error {
            HapticEngine.error.trigger()
        }
        let toast = Toast(
            message: message,
            style: .error,
            retry: Toast.RetryAction(label: retryLabel, perform: retry)
        )
        currentToast = toast
        // No auto-dismiss timer here — actionable toasts stay until acted on.
    }

    /// Dismiss the current toast (programmatic; e.g. when underlying state
    /// changes so the message no longer applies).
    func dismiss() {
        currentToast = nil
    }

    private func present(_ toast: Toast, duration: TimeInterval) {
        currentToast = toast
        let messageSnapshot = toast.message
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            // Only auto-dismiss if no newer toast has superseded us.
            if currentToast?.message == messageSnapshot && currentToast?.style == .info {
                currentToast = nil
            }
        }
    }
}

struct ToastNotification: View {
    let toast: ToastManager.Toast
    var onDismiss: () -> Void = {}

    var body: some View {
        HStack(spacing: 12) {
            if toast.style == .error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.yellow)
                    .accessibilityHidden(true)
            }
            Text(toast.message)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let retry = toast.retry {
                Button(retry.label) {
                    retry.perform()
                    onDismiss()
                }
                .font(.footnote.weight(.bold))
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(Color.white.opacity(0.18), in: Capsule())
                .accessibilityHint("Retries the operation that just failed.")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(toastBackground)
        .cornerRadius(12)
        .shadow(radius: 12)
        .transition(.move(edge: .top).combined(with: .opacity))
        // Swipe-up to dismiss. Persistent error toasts otherwise have
        // no escape short of tapping Retry — fine if the user wants to
        // retry, but a dead end if they've already addressed the issue
        // some other way. Matches iOS notification-banner conventions.
        .gesture(
            DragGesture(minimumDistance: 20)
                .onEnded { value in
                    if value.translation.height < -20 {
                        onDismiss()
                    }
                }
        )
        // `.contain` keeps the Retry button independently focusable;
        // `.combine` previously swallowed it so VoiceOver users heard
        // the error but had no way to act on the retry affordance.
        // The custom rotor action mirrors the button for users who
        // rely on the rotor instead of scanning the toast geometry —
        // only attached when a retry actually exists.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(toast.message)
        .modifier(ToastRetryRotorAction(retry: toast.retry, onDismiss: onDismiss))
        // VoiceOver users can't perform the swipe-up dismiss gesture
        // reliably with the screen reader's gesture vocabulary already
        // occupying that area. Expose Dismiss via the rotor so they
        // have a path out that isn't tied to acting on the failure.
        .accessibilityAction(named: "Dismiss", onDismiss)
    }

    private var toastBackground: some View {
        Color.black.opacity(0.85)
    }
}

/// Attaches a VoiceOver rotor action only when the toast carries a
/// retry. Conditional `.accessibilityAction` on a parent view stays
/// registered even when its closure does nothing, which would show a
/// dead "Retry" entry in the rotor for non-retryable toasts.
private struct ToastRetryRotorAction: ViewModifier {
    let retry: ToastManager.Toast.RetryAction?
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        if let retry = retry {
            content.accessibilityAction(named: retry.label) {
                retry.perform()
                onDismiss()
            }
        } else {
            content
        }
    }
}

struct ToastHostModifier: ViewModifier {
    @StateObject private var toastManager = ToastManager.shared

    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if let toast = toastManager.currentToast {
                        VStack {
                            ToastNotification(toast: toast, onDismiss: {
                                toastManager.dismiss()
                            })
                            .padding(.top, 12)
                            .padding(.horizontal, 12)
                            Spacer()
                        }
                        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: toastManager.currentToast)
                    }
                }
            )
    }
}

extension View {
    func withToastNotifications() -> some View {
        modifier(ToastHostModifier())
    }
}
