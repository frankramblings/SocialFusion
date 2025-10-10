import Foundation

extension Notification.Name {
    // Use canonical name in SocialServiceManager (AccountUpdated)
    static let accountUpdatedCanonical = Notification.Name("AccountUpdated")
    static let shouldRepresentAddAccount = Notification.Name("shouldRepresentAddAccount")
    static let autofillInterrupted = Notification.Name("autofillInterrupted")
}
