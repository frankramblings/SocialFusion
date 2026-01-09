import Foundation
import Logging
import SocialFusion
import Testing

@MainActor
@Suite("StructuredLogger Tests")
final class StructuredLoggerTests {
    private var logger: StructuredLogger!
    private static var didBootstrap = false
    private static var sharedMemoryHandler = InMemoryLogHandler()
    private var memoryHandler: InMemoryLogHandler! {
        get { Self.sharedMemoryHandler }
        set { Self.sharedMemoryHandler = newValue }
    }

    @Test("Logger initialization")
    func loggerInitialization() {
        if !Self.didBootstrap {
            LoggingSystem.bootstrap { _ in Self.sharedMemoryHandler }
            Self.didBootstrap = true
        }
        memoryHandler.clear()
        logger = StructuredLogger(label: "com.socialfusion.test")
        #expect(logger != nil)
    }

    @Test("Debug logging with context")
    func debugLoggingWithContext() {
        if !Self.didBootstrap {
            LoggingSystem.bootstrap { _ in Self.sharedMemoryHandler }
            Self.didBootstrap = true
        }
        memoryHandler.clear()
        logger = StructuredLogger(label: "com.socialfusion.test")

        let context = LogContext(
            name: "test",
            attributes: ["key": "value"]
        )
        logger.debug("Test message", context: context)

        let entries = memoryHandler.entries(withLevel: .debug)
        #expect(entries.count == 1)
        #expect(entries[0].message.description == "Test message")
        #expect(entries[0].metadata["context"]?.description == "test")
        #expect(entries[0].metadata["attributes"]?.description.contains("key") == true)
    }

    @Test("Error logging with error context")
    func errorLoggingWithErrorContext() {
        if !Self.didBootstrap {
            LoggingSystem.bootstrap { _ in Self.sharedMemoryHandler }
            Self.didBootstrap = true
        }
        memoryHandler.clear()
        logger = StructuredLogger(label: "com.socialfusion.test")

        let error = NSError(domain: "Test", code: 1)
        let context = LogContext(
            name: "error",
            error: error,
            attributes: ["key": "value"]
        )
        logger.error("Test error", context: context)

        let entries = memoryHandler.entries(withLevel: .error)
        #expect(entries.count == 1)
        #expect(entries[0].message.description == "Test error")
        #expect(entries[0].metadata["context"]?.description == "error")
        #expect(entries[0].metadata["error"]?.description == error.localizedDescription)
    }

    @Test("Log context creation")
    func logContextCreation() {
        let context = LogContext.context(
            name: "test",
            attributes: ["key": "value"]
        )

        #expect(context.name == "test")
        #expect(context.error == nil)
        #expect(context.attributes["key"]?.description == "value")
    }

    @Test("Log context with error")
    func logContextWithError() {
        let error = NSError(domain: "Test", code: 1)
        let context = LogContext.context(
            name: "error",
            error: error
        )

        #expect(context.name == "error")
        #expect(context.error?.localizedDescription == error.localizedDescription)
    }

    @Test("Log metadata structure")
    func logMetadataStructure() {
        if !Self.didBootstrap {
            LoggingSystem.bootstrap { _ in Self.sharedMemoryHandler }
            Self.didBootstrap = true
        }
        memoryHandler.clear()
        logger = StructuredLogger(label: "com.socialfusion.test")

        let context = LogContext(
            name: "test",
            attributes: ["key": "value"]
        )
        logger.info("Test message", context: context)

        let entries = memoryHandler.entries
        #expect(entries.count == 1)
        #expect(entries[0].metadata["file"] != nil)
        #expect(entries[0].metadata["function"] != nil)
        #expect(entries[0].metadata["line"] != nil)
        #expect(entries[0].metadata["timestamp"] != nil)
    }
}
