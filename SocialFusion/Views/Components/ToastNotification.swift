import SwiftUI
import UIKit

/// Severity of a toast message. Controls the leading glyph, its tint, and the
/// haptic that fires when the toast appears.
enum ToastSeverity: Equatable {
    case info
    case success
    case warning
    case error

    fileprivate var symbol: String? {
        switch self {
        case .info: return nil
        case .success: return "checkmark.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .error: return "xmark.octagon.fill"
        }
    }

    fileprivate var tint: Color {
        switch self {
        case .info: return .primary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }

    fileprivate var haptic: HapticEngine? {
        switch self {
        case .info: return nil
        case .success: return .success
        case .warning: return .warning
        case .error: return .error
        }
    }
}

@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    /// One user-visible toast.
    ///
    /// Non-actionable toasts (no `retry`) auto-dismiss after `autoDismissAfter`
    /// seconds. Retry-bearing toasts default to persistent — they stay on
    /// screen until the user taps Retry, taps to dismiss, or the queue is
    /// programmatically cleared.
    struct Toast: Identifiable, Equatable {
        let id: UUID
        let message: String
        let severity: ToastSeverity
        let retry: RetryAction?
        /// `nil` = persistent (no auto-dismiss). Set to a positive interval
        /// to override the default for the toast's actionability.
        let autoDismissAfter: TimeInterval?

        /// Wrapper for the actionable retry callback so `Toast` stays
        /// `Equatable` (closures aren't). Identity is the wrapper's UUID,
        /// not the underlying function pointer.
        struct RetryAction: Equatable {
            let id: UUID
            let label: String
            let perform: @MainActor () -> Void

            init(label: String = "Retry", perform: @escaping @MainActor () -> Void) {
                self.id = UUID()
                self.label = label
                self.perform = perform
            }

            static func == (lhs: RetryAction, rhs: RetryAction) -> Bool {
                lhs.id == rhs.id
            }
        }

        init(
            message: String,
            severity: ToastSeverity = .info,
            retry: RetryAction? = nil,
            autoDismissAfter: TimeInterval? = nil
        ) {
            self.id = UUID()
            self.message = message
            self.severity = severity
            self.retry = retry
            // Persistent when actionable; transient otherwise. An explicit
            // duration overrides both defaults.
            if let dur = autoDismissAfter {
                self.autoDismissAfter = dur
            } else if retry != nil {
                self.autoDismissAfter = nil
            } else {
                self.autoDismissAfter = 2.0
            }
        }

        static func == (lhs: Toast, rhs: Toast) -> Bool {
            lhs.id == rhs.id
                && lhs.message == rhs.message
                && lhs.severity == rhs.severity
                && lhs.retry == rhs.retry
                && lhs.autoDismissAfter == rhs.autoDismissAfter
        }
    }

    /// FIFO queue of toasts. Head (`pending.first`) is what the host renders.
    /// Producers `show(...)` and the head auto-advances as toasts expire or
    /// are dismissed.
    @Published private(set) var pending: [Toast] = []

    /// Convenience for the host modifier (and external observers that want a
    /// stable "what's currently visible" hook).
    var currentToast: Toast? { pending.first }

    /// Auto-dismiss tasks keyed by toast id so a specific toast can be
    /// cancelled (e.g., when the user taps Dismiss) without affecting others.
    private var dismissTasks: [UUID: Task<Void, Never>] = [:]

    /// Show a transient toast. Pass a `severity` to get a leading glyph +
    /// matching haptic; default `.info` is the plain capsule.
    func show(_ message: String, severity: ToastSeverity = .info, duration: TimeInterval = 2.0) {
        let toast = Toast(
            message: message,
            severity: severity,
            retry: nil,
            autoDismissAfter: duration
        )
        enqueue(toast)
    }

    /// Show a persistent, actionable error toast. Stays on screen until the
    /// user taps Retry, taps to dismiss, or the queue is cleared. The retry
    /// closure runs on the main actor.
    func showError(
        _ message: String,
        retryLabel: String = "Retry",
        retry: @escaping @MainActor () -> Void
    ) {
        let toast = Toast(
            message: message,
            severity: .error,
            retry: Toast.RetryAction(label: retryLabel, perform: retry)
        )
        enqueue(toast)
    }

    /// Generic enqueue path. Use when you want full control over the Toast
    /// fields (e.g., to set a custom `autoDismissAfter` on a non-retry toast).
    func enqueue(_ toast: Toast) {
        // Fire severity-appropriate haptic (success/warning/error). .info
        // toasts stay quiet — they're informational, not feedback on action.
        toast.severity.haptic?.trigger()

        // VoiceOver users won't see the toast slide in — post an
        // announcement so they're aware of the same feedback sighted
        // users get. Severity prefix mirrors the accessibilityLabel.
        if UIAccessibility.isVoiceOverRunning {
            let prefix: String
            switch toast.severity {
            case .info: prefix = ""
            case .success: prefix = "Success. "
            case .warning: prefix = "Warning. "
            case .error: prefix = "Error. "
            }
            UIAccessibility.post(notification: .announcement, argument: "\(prefix)\(toast.message)")
        }

        pending.append(toast)
        scheduleAutoDismissIfNeeded(for: toast)
    }

    /// Dismiss the head toast (back-compat with the legacy single-slot API).
    func dismiss() {
        if let head = pending.first {
            dismiss(head.id)
        }
    }

    /// Dismiss a specific toast by id. If it was the head, the next toast in
    /// the queue becomes current and its auto-dismiss (if any) is scheduled.
    func dismiss(_ id: UUID) {
        guard pending.contains(where: { $0.id == id }) else { return }
        let wasHead = pending.first?.id == id
        pending.removeAll { $0.id == id }
        dismissTasks[id]?.cancel()
        dismissTasks[id] = nil
        // If a new head exists and isn't already counting down, start its timer.
        if wasHead, let newHead = pending.first, dismissTasks[newHead.id] == nil {
            scheduleAutoDismissIfNeeded(for: newHead)
        }
    }

    /// Drop the entire queue — used on logout, scene transitions, or
    /// catastrophic state resets.
    func dismissAll() {
        dismissTasks.values.forEach { $0.cancel() }
        dismissTasks.removeAll()
        pending.removeAll()
    }

    /// Fire a toast's retry callback and dismiss it. No-op if the message
    /// isn't in the queue or carries no retry.
    func invokeRetry(for id: UUID) {
        guard let toast = pending.first(where: { $0.id == id }),
              let retry = toast.retry else { return }
        retry.perform()
        dismiss(id)
    }

    private func scheduleAutoDismissIfNeeded(for toast: Toast) {
        guard let duration = toast.autoDismissAfter, duration > 0 else { return }
        let id = toast.id
        dismissTasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self?.dismiss(id)
        }
    }
}

struct ToastNotification: View {
    let toast: ToastManager.Toast
    let onRetry: () -> Void
    let onDismiss: () -> Void
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            if let symbol = toast.severity.symbol {
                Image(systemName: symbol)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(toast.severity.tint.gradient)
                    .symbolRenderingMode(.hierarchical)
                    .transition(.scale.combined(with: .opacity))
            }

            Text(toast.message)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let retry = toast.retry {
                Button(retry.label) {
                    // Tap haptic confirms the gesture before the async retry
                    // surfaces, matching the Fused outage-banner pattern.
                    HapticEngine.tap.trigger()
                    onRetry()
                }
                .font(.footnote.weight(.bold))
                .foregroundColor(toast.severity.tint)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(
                    Capsule(style: .continuous)
                        .fill(toast.severity.tint.opacity(0.16))
                )
                .accessibilityHint("Retries the failed action")
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
        .background(
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    // Hairline border picks up the severity tint subtly when
                    // present; otherwise stays neutral.
                    Capsule(style: .continuous)
                        .strokeBorder(
                            toast.severity == .info
                                ? Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06)
                                : toast.severity.tint.opacity(0.32),
                            lineWidth: 0.5
                        )
                )
                .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
                .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
        )
        .contentShape(Capsule(style: .continuous))
        .onTapGesture {
            // Tap on the capsule body (away from the Retry button) dismisses
            // the toast. Retry button intercepts its own taps.
            HapticEngine.tap.trigger()
            onDismiss()
        }
        .transition(
            reduceMotion
                ? .opacity
                : .asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                )
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(toast.retry == nil ? "Dismisses this notification" : "Dismisses this notification, or tap Retry to try again")
        .accessibilityAddTraits(.updatesFrequently)
        // Rotor action mirrors the visible Dismiss tap for VoiceOver users
        // who navigate by rotor rather than scanning the toast geometry.
        .accessibilityAction(named: "Dismiss") {
            onDismiss()
        }
    }

    private var accessibilityLabel: String {
        switch toast.severity {
        case .info: return toast.message
        case .success: return "Success. \(toast.message)"
        case .warning: return "Warning. \(toast.message)"
        case .error: return "Error. \(toast.message)"
        }
    }
}

struct ToastHostModifier: ViewModifier {
    @StateObject private var toastManager = ToastManager.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = toastManager.currentToast {
                    ToastNotification(
                        toast: toast,
                        onRetry: { toastManager.invokeRetry(for: toast.id) },
                        onDismiss: { toastManager.dismiss(toast.id) }
                    )
                    .padding(.top, 14)
                    .padding(.horizontal, 16)
                    .id(toast.id)
                    .transaction { t in
                        // Reduce Motion: drop the spring envelope so the
                        // toast just appears/disappears. The view's own
                        // .transition already handles reduceMotion via the
                        // accessibility env; this just gates the driving
                        // animation here at the host.
                        t.animation = reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78)
                    }
                }
            }
            .animation(reduceMotion ? nil : .spring(response: 0.42, dampingFraction: 0.78), value: toastManager.currentToast)
    }
}

extension View {
    func withToastNotifications() -> some View {
        modifier(ToastHostModifier())
    }
}
