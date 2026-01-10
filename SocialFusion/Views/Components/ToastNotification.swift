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

    var body: some View {
        Text(toast.message)
            .font(.footnote.weight(.semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.black.opacity(0.85))
            .cornerRadius(12)
            .shadow(radius: 12)
            .transition(.move(edge: .top).combined(with: .opacity))
            .accessibilityLabel(toast.message)
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
                            ToastNotification(toast: toast)
                                .padding(.top, 12)
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
