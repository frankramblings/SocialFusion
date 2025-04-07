import Logging

/// A centralized logging system for the SocialFusion application.
public struct AppLogger {
    /// The shared logger instance.
    public static let shared = AppLogger()

    private let logger: Logger
    private let inMemoryHandler: InMemoryLogHandler?

    /// Creates a new logger with the specified handler.
    /// - Parameter handler: The log handler to use. If nil, a default handler is used.
    public init(handler: LogHandler? = nil) {
        if let handler = handler {
            self.logger = Logger(label: "com.socialfusion.app", factory: { _ in handler })
            self.inMemoryHandler = handler as? InMemoryLogHandler
        } else {
            var logger = Logger(label: "com.socialfusion.app")
            #if DEBUG
                logger.logLevel = .debug
            #else
                logger.logLevel = .info
            #endif
            self.logger = logger
            self.inMemoryHandler = nil
        }
    }

    /// The log level of the logger.
    public var logLevel: Logger.Level {
        logger.logLevel
    }

    /// Returns the in-memory log handler if one is being used.
    public var memoryHandler: InMemoryLogHandler? {
        inMemoryHandler
    }

    /// Logs a debug message.
    /// - Parameters:
    ///   - message: The message to log.
    ///   - file: The file where the log originated.
    ///   - function: The function where the log originated.
    ///   - line: The line number where the log originated.
    public func debug(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger.debug(
            "\(message)",
            metadata: [
                "file": "\(file)",
                "function": "\(function)",
                "line": "\(line)",
            ])
    }

    /// Logs an info message.
    /// - Parameters:
    ///   - message: The message to log.
    ///   - file: The file where the log originated.
    ///   - function: The function where the log originated.
    ///   - line: The line number where the log originated.
    public func info(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger.info(
            "\(message)",
            metadata: [
                "file": "\(file)",
                "function": "\(function)",
                "line": "\(line)",
            ])
    }

    /// Logs a warning message.
    /// - Parameters:
    ///   - message: The message to log.
    ///   - file: The file where the log originated.
    ///   - function: The function where the log originated.
    ///   - line: The line number where the log originated.
    public func warning(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        logger.warning(
            "\(message)",
            metadata: [
                "file": "\(file)",
                "function": "\(function)",
                "line": "\(line)",
            ])
    }

    /// Logs an error message.
    /// - Parameters:
    ///   - message: The message to log.
    ///   - error: The error to log.
    ///   - file: The file where the log originated.
    ///   - function: The function where the log originated.
    ///   - line: The line number where the log originated.
    public func error(
        _ message: String,
        error: Error? = nil,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        var metadata: Logger.Metadata = [
            "file": "\(file)",
            "function": "\(function)",
            "line": "\(line)",
        ]

        if let error = error {
            metadata["error"] = "\(error.localizedDescription)"
        }

        logger.error("\(message)", metadata: metadata)
    }
}
