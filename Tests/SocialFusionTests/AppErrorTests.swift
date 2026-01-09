import Foundation
import SocialFusion
import Testing

@MainActor
@Suite("AppError Tests")
final class AppErrorTests {
    @Test("Network error conversion")
    func networkErrorConversion() {
        let underlyingError = NSError(domain: "Test", code: 1)
        let error = AppError.networkError(underlyingError: underlyingError)

        let normalized = error.errorDescription?.replacingOccurrences(of: "’", with: "'")
        #expect(
            normalized == "Network error: The operation couldn't be completed. (Test error 1.)")
        #expect(error.recoverySuggestion == "Please check your internet connection and try again.")
    }

    @Test("File error handling")
    func fileErrorHandling() {
        let path = "/test/file.txt"
        let error = AppError.fileError(.fileNotFound(path))

        #expect(error.errorDescription == "File error: File not found: /test/file.txt")
        #expect(error.recoverySuggestion == "Please check if the file exists and try again.")
    }

    @Test("Database error handling")
    func databaseErrorHandling() {
        let underlyingError = NSError(domain: "Test", code: 1)
        let error = AppError.databaseError(.connectionError(underlyingError))

        let normalized = error.errorDescription?.replacingOccurrences(of: "’", with: "'")
        #expect(
            normalized
                == "Database error: Connection error: The operation couldn't be completed. (Test error 1.)"
        )
        #expect(error.recoverySuggestion == "Please check your database connection and try again.")
    }

    @Test("Validation error handling")
    func validationErrorHandling() {
        let errors = [
            AppError.ValidationError(field: "email", message: "Invalid format"),
            AppError.ValidationError(field: "password", message: "Too short"),
        ]
        let error = AppError.validationError(errors)

        #expect(
            error.errorDescription
                == "Validation errors: email: Invalid format, password: Too short")
        #expect(error.recoverySuggestion == "Please correct the validation errors and try again.")
    }

    @Test("Configuration error handling")
    func configurationErrorHandling() {
        let message = "Invalid API key"
        let error = AppError.configurationError(message)

        #expect(error.errorDescription == "Configuration error: Invalid API key")
        #expect(
            error.recoverySuggestion == "Please check your configuration settings and try again.")
    }

    @Test("Error conversion")
    func errorConversion() {
        let underlyingError = NSError(domain: "Test", code: 1)
        let convertedError = underlyingError.asAppError()

        let normalized = convertedError.errorDescription?.replacingOccurrences(of: "’", with: "'")
        #expect(
            normalized
                == "Unknown error: The operation couldn't be completed. (Test error 1.)")
        #expect(
            convertedError.recoverySuggestion
                == "Please try again or contact support if the problem persists.")
    }
}
