import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {

  private var sharedText: String?
  private var sharedURL: URL?

  override func viewDidLoad() {
    super.viewDidLoad()
    // Match the app's tint (AppPrimaryColor asset, set as the
    // app-level .tint in ContentView) rather than the iOS default
    // systemBlue. Falls back to systemBlue if the asset is missing
    // so a future asset-catalog refactor doesn't break the
    // extension.
    navigationController?.navigationBar.tintColor =
      UIColor(named: "AppPrimaryColor") ?? UIColor.systemBlue
    extractSharedItems()
  }

  override func isContentValid() -> Bool {
    // Block Post when there's nothing to send — either typed text in
    // the composer, a shared URL from the host app, or shared text.
    // Otherwise the user can ship an empty deep-link that opens an
    // empty composer for no reason.
    let typed = (contentText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !typed.isEmpty { return true }
    if sharedURL != nil { return true }
    if let s = sharedText, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return true
    }
    return false
  }

  override func didSelectPost() {
    var queryItems: [URLQueryItem] = []

    let composedText = contentText ?? ""
    var fullText = composedText

    if let sharedText = sharedText, !sharedText.isEmpty, sharedText != composedText {
      if fullText.isEmpty {
        fullText = sharedText
      } else {
        fullText += "\n" + sharedText
      }
    }

    if !fullText.isEmpty {
      queryItems.append(URLQueryItem(name: "text", value: fullText))
    }

    if let url = sharedURL {
      queryItems.append(URLQueryItem(name: "url", value: url.absoluteString))
    }

    var components = URLComponents()
    components.scheme = "socialfusion"
    components.host = "compose"
    components.queryItems = queryItems.isEmpty ? nil : queryItems

    if let deepLink = components.url {
      var responder: UIResponder? = self
      while let next = responder?.next {
        if let application = next as? UIApplication {
          application.open(deepLink, options: [:], completionHandler: nil)
          break
        }
        responder = next
      }
    }

    extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
  }

  override func configurationItems() -> [Any]! {
    return []
  }

  private func extractSharedItems() {
    guard let extensionItems = extensionContext?.inputItems as? [NSExtensionItem] else { return }

    for item in extensionItems {
      guard let attachments = item.attachments else { continue }

      for provider in attachments {
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
            if let url = item as? URL {
              DispatchQueue.main.async {
                self?.sharedURL = url
                // Re-evaluate `isContentValid()` so the Post button
                // enables once the async URL extraction lands. Without
                // this the user has to type something — even though
                // the URL is enough — to make the button live.
                self?.validateContent()
              }
            }
          }
        }

        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
          provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
            if let text = item as? String {
              DispatchQueue.main.async {
                self?.sharedText = text
                self?.validateContent()
              }
            }
          }
        }
      }
    }
  }
}
