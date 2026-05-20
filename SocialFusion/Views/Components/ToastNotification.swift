import SwiftUI

@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
    }

    @Published private(set) var currentToast: Toast?

    func show(_ message: String, duration: TimeInterval = 2.0) {
        currentToast = Toast(message: message)
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if currentToast?.message == message {
                currentToast = nil
            }
        }
    }
}

struct ToastNotification: View {
    let toast: ToastManager.Toast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Text(toast.message)
            .font(.footnote.weight(.semibold))
            .foregroundColor(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 11)
            .background(
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(
                        // Hairline border picks up the system tint subtly
                        Capsule()
                            .strokeBorder(
                                Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06),
                                lineWidth: 0.5
                            )
                    )
                    .shadow(color: .black.opacity(0.18), radius: 14, x: 0, y: 6)
                    .shadow(color: .black.opacity(0.08), radius: 1, x: 0, y: 1)
            )
            .transition(
                .asymmetric(
                    insertion: .move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.92, anchor: .top)),
                    removal: .opacity.combined(with: .scale(scale: 0.96, anchor: .top))
                )
            )
            .accessibilityLabel(toast.message)
    }
}

struct ToastHostModifier: ViewModifier {
    @StateObject private var toastManager = ToastManager.shared

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if let toast = toastManager.currentToast {
                    ToastNotification(toast: toast)
                        .padding(.top, 14)
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
