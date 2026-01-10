import Foundation

enum UITestHooks {
    static var isEnabled: Bool {
        let args = ProcessInfo.processInfo.arguments
        return args.contains("UI-Testing") || args.contains("UI_TESTING")
    }
}

