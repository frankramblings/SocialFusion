import SafariServices
import SwiftUI
import WebKit

struct AuthWebView: View {
    let url: URL
    let callbackURLScheme: String
    let onComplete: (URL) -> Void
    let onCancel: () -> Void

    @State private var presentSafariView = false

    var body: some View {
        VStack {
            if #available(iOS 17.0, *) {
                WebAuthenticationView(
                    url: url,
                    callbackURLScheme: callbackURLScheme,
                    onComplete: onComplete,
                    onCancel: onCancel
                )
            } else {
                // For older iOS versions, we'll use SFSafariViewController
                Button(action: {
                    presentSafariView = true
                }) {
                    Text("Continue to Authorization")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding()
                .sheet(isPresented: $presentSafariView) {
                    SafariAuthView(
                        url: url,
                        callbackURLScheme: callbackURLScheme,
                        onComplete: onComplete,
                        onCancel: onCancel
                    )
                }
            }
        }
    }
}

// Modern WebAuthentication API (iOS 17+)
@available(iOS 17.0, *)
struct WebAuthenticationView: UIViewControllerRepresentable {
    let url: URL
    let callbackURLScheme: String
    let onComplete: (URL) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()

        let webAuthSession = ASWebAuthenticationSession(
            url: url,
            callbackURLScheme: callbackURLScheme
        ) { callbackURL, error in
            if let error = error {
                print("Authentication error: \(error.localizedDescription)")
                onCancel()
                return
            }

            guard let callbackURL = callbackURL else {
                print("No callback URL returned")
                onCancel()
                return
            }

            onComplete(callbackURL)
        }

        webAuthSession.presentationContextProvider = context.coordinator
        webAuthSession.prefersEphemeralWebBrowserSession = true

        // Store the session in the coordinator to prevent it from being deallocated
        context.coordinator.webAuthSession = webAuthSession

        // Start the authentication session
        webAuthSession.start()

        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // No update needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, ASWebAuthenticationPresentationContextProviding {
        var webAuthSession: ASWebAuthenticationSession?

        func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
            // Return the key window as the presentation anchor
            // iOS 16 compatible method to get key window
            let scenes = UIApplication.shared.connectedScenes
            let windowScene = scenes.first as? UIWindowScene
            guard let window = windowScene?.windows.first else {
                return UIWindow()
            }
            return window
        }
    }
}

// Safari View Controller for older iOS versions
struct SafariAuthView: UIViewControllerRepresentable {
    let url: URL
    let callbackURLScheme: String
    let onComplete: (URL) -> Void
    let onCancel: () -> Void

    @Environment(\.presentationMode) var presentationMode

    class Coordinator: NSObject, SFSafariViewControllerDelegate {
        let parent: SafariAuthView

        init(parent: SafariAuthView) {
            self.parent = parent
        }

        func safariViewControllerDidFinish(_ controller: SFSafariViewController) {
            parent.presentationMode.wrappedValue.dismiss()
            parent.onCancel()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIViewController(context: Context) -> SFSafariViewController {
        // Register for URL notification
        NotificationCenter.default.addObserver(
            forName: Notification.Name("AuthCallbackReceived"),
            object: nil,
            queue: .main
        ) { notification in
            if let url = notification.object as? URL {
                self.presentationMode.wrappedValue.dismiss()
                self.onComplete(url)
            }
        }

        let safariVC = SFSafariViewController(url: url)
        safariVC.delegate = context.coordinator
        safariVC.preferredControlTintColor = UIColor.systemBlue
        safariVC.dismissButtonStyle = .done

        return safariVC
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {
        // No update needed
    }
}

// Preview
struct AuthWebView_Previews: PreviewProvider {
    static var previews: some View {
        AuthWebView(
            url: URL(string: "https://mastodon.social/oauth/authorize")!,
            callbackURLScheme: "socialfusion",
            onComplete: { _ in },
            onCancel: {}
        )
    }
}
