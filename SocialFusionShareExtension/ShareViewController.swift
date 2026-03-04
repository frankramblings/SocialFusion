import UIKit
import Social
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
    return true
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
              }
            }
          }
        }

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
