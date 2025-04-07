import SocialFusion
import Testing

@Suite("AppError Tests")
final class AppErrorTests {
    @Test("Network error conversion")
    func networkErrorConversion() {
        let underlyingError = NSError(domain: "Test", code: 1)
        let error = AppError.networkError(underlyingError: underlyingError)

        #expect(
            error.errorDescription
                == "Network error: The operation couldn't be completed. (Test error 1.)")
        #expect(error.recoverySuggestion == "Please check your internet connection and try again.")
    }

    @Test("Invalid input error")
    func invalidInputError() {
        let message = "Invalid email format"
        let error = AppError.invalidInput(message)

        #expect(error.errorDescription == "Invalid input: Invalid email format")
        #expect(error.recoverySuggestion == "Please check your input and try again.")
    }

    @Test("Error conversion")
    func errorConversion() {
        let underlyingError = NSError(domain: "Test", code: 1)
        let convertedError = underlyingError.asAppError()

        #expect(
            convertedError.errorDescription
                == "Unknown error: The operation couldn't be completed. (Test error 1.)")
        #expect(
            convertedError.recoverySuggestion
                == "Please try again or contact support if the problem persists.")
    }
}
