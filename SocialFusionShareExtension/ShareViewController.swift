import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: SLComposeServiceViewController {

  private var sharedText: String?
  private var sharedURL: URL?

  override func viewDidLoad() {
    super.viewDidLoad()
    navigationController?.navigationBar.tintColor = UIColor.systemBlue
    extractSharedItems()
  }

  override func isContentValid() -> Bool {
    // Always valid -- user can share even without adding text
    return true
  }

  override func didSelectPost() {
    // Build the deep link with shared content
    var queryItems: [URLQueryItem] = []

    // Include user-entered text from the compose field
    let composedText = contentText ?? ""
    var fullText = composedText

    // Append any shared text that wasn't from a URL
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
      // Open the main app via the shared URL scheme
      // Share extensions use openURL via responder chain
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
        // Handle URLs
        if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
          provider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] item, _ in
            if let url = item as? URL {
              DispatchQueue.main.async {
                self?.sharedURL = url
              }
            }
          }
        }

        // Handle plain text
        if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
          provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
            if let text = item as? String {
              DispatchQueue.main.async {
                self?.sharedText = text
              }
            }
          }
        }
      }
    }
  }
}
