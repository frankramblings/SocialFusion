import Foundation

/// The entry point of the SocialFusion application.
struct SocialFusion {
    static func main() {
        do {
            AppLogger.shared.info("Starting SocialFusion application")
            try runApplication()
        } catch {
            AppLogger.shared.error("Application failed to start", error: error)
            exit(1)
        }
    }

    private static func runApplication() throws {
        // Example of error handling
        do {
            try performOperation()
        } catch {
            throw AppError.unknown(error)
        }
    }

    private static func performOperation() throws {
        // Example operation that might fail
        AppLogger.shared.debug("Performing operation")

        // Simulate an error
        throw NSError(
            domain: "com.socialfusion", code: 1,
            userInfo: [
                NSLocalizedDescriptionKey: "Operation failed"
            ])
    }
}

// Top-level code
SocialFusion.main()
