import Foundation
import Logging
import SocialFusion
import Testing

@MainActor
@Suite("AppLogger Tests")
final class AppLoggerTests {
    private var logger: AppLogger!
    private var memoryHandler: InMemoryLogHandler!

    @Test("Logger initialization")
    func loggerInitialization() {
        memoryHandler = InMemoryLogHandler()
        logger = AppLogger(handler: memoryHandler)
        #expect(logger != nil)
        #expect(logger.memoryHandler != nil)
    }

    @Test("Debug logging")
    func debugLogging() {
        memoryHandler = InMemoryLogHandler()
        logger = AppLogger(handler: memoryHandler)

        let message = "Test debug message"
        logger.debug(message)

        let entries = memoryHandler.entries(withLevel: .debug)
        #expect(entries.count == 1)
        #expect(entries[0].message.description == message)
    }

    @Test("Info logging")
    func infoLogging() {
        memoryHandler = InMemoryLogHandler()
        logger = AppLogger(handler: memoryHandler)

        let message = "Test info message"
        logger.info(message)

        let entries = memoryHandler.entries(withLevel: .info)
        #expect(entries.count == 1)
        #expect(entries[0].message.description == message)
    }

    @Test("Warning logging")
    func warningLogging() {
        memoryHandler = InMemoryLogHandler()
        logger = AppLogger(handler: memoryHandler)

        let message = "Test warning message"
        logger.warning(message)

        let entries = memoryHandler.entries(withLevel: .warning)
        #expect(entries.count == 1)
        #expect(entries[0].message.description == message)
    }

    @Test("Error logging with error")
    func errorLoggingWithError() {
        memoryHandler = InMemoryLogHandler()
        logger = AppLogger(handler: memoryHandler)

        let message = "Test error message"
        let testError = NSError(domain: "Test", code: 1)
        logger.error(message, error: testError)

        let entries = memoryHandler.entries(withLevel: .error)
        #expect(entries.count == 1)
        #expect(entries[0].message.description == message)
        #expect(entries[0].metadata["error"]?.description == testError.localizedDescription)
    }

    @Test("Error logging without error")
    func errorLoggingWithoutError() {
        memoryHandler = InMemoryLogHandler()
        logger = AppLogger(handler: memoryHandler)

        let message = "Test error message"
        logger.error(message)

        let entries = memoryHandler.entries(withLevel: .error)
        #expect(entries.count == 1)
        #expect(entries[0].message.description == message)
        #expect(entries[0].metadata["error"] == nil)
    }

    @Test("Log level configuration")
    func logLevelConfiguration() {
        memoryHandler = InMemoryLogHandler()
        logger = AppLogger(handler: memoryHandler)

        #if DEBUG
            #expect(logger.logLevel == .debug)
        #else
            #expect(logger.logLevel == .info)
        #endif
    }

    @Test("Log entry metadata")
    func logEntryMetadata() {
        memoryHandler = InMemoryLogHandler()
        logger = AppLogger(handler: memoryHandler)

        let message = "Test message"
        logger.debug(message)

        let entries = memoryHandler.entries
        #expect(entries.count == 1)
        #expect(entries[0].metadata["file"] != nil)
        #expect(entries[0].metadata["function"] != nil)
        #expect(entries[0].metadata["line"] != nil)
    }
}
