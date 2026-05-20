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

    struct Toast: Identifiable, Equatable {
        let id: UUID
        let message: String
        let severity: ToastSeverity

        init(message: String, severity: ToastSeverity = .info) {
            self.id = UUID()
            self.message = message
            self.severity = severity
        }
    }

    @Published private(set) var currentToast: Toast?
    private var dismissTask: Task<Void, Never>?

    /// Shows a toast. Pass a `severity` to get a leading glyph + matching
    /// haptic; default `.info` is the plain capsule (back-compat with existing
    /// callers that used the single-argument form).
    func show(_ message: String, severity: ToastSeverity = .info, duration: TimeInterval = 2.0) {
        // Cancel any pending dismiss so a rapid succession of show()s doesn't
        // dismiss the latest toast prematurely.
        dismissTask?.cancel()

        let toast = Toast(message: message, severity: severity)
        currentToast = toast

        // Fire severity-appropriate haptic (success/warning/error). .info
        // toasts stay quiet — they're informational, not feedback on action.
        severity.haptic?.trigger()

        // VoiceOver users won't see the toast slide in — post an
        // announcement so they're aware of the same feedback sighted
        // users get. Severity prefix mirrors the accessibilityLabel.
        if UIAccessibility.isVoiceOverRunning {
            let prefix: String
            switch severity {
            case .info: prefix = ""
            case .success: prefix = "Success. "
            case .warning: prefix = "Warning. "
            case .error: prefix = "Error. "
            }
            UIAccessibility.post(notification: .announcement, argument: "\(prefix)\(message)")
        }

        dismissTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            guard !Task.isCancelled else { return }
            // Only clear if this is still the toast we showed (rapid succession
            // guard).
            if currentToast?.id == toast.id {
                currentToast = nil
            }
        }
    }

    /// Manually dismiss the current toast — used by tap-to-dismiss.
    func dismiss() {
        dismissTask?.cancel()
        currentToast = nil
    }
}

struct ToastNotification: View {
    let toast: ToastManager.Toast
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
            // Tap to dismiss — feels expected on a temporary banner.
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
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Dismisses this notification")
        .accessibilityAddTraits(.updatesFrequently)
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

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = toastManager.currentToast {
                    ToastNotification(toast: toast, onDismiss: toastManager.dismiss)
                        .padding(.top, 14)
                        .padding(.horizontal, 16)
                        .id(toast.id)
                        .transaction { t in
                            t.animation = .spring(response: 0.42, dampingFraction: 0.78)
                        }
                }
            }
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: toastManager.currentToast)
    }
}

extension View {
    func withToastNotifications() -> some View {
        modifier(ToastHostModifier())
    }
}
