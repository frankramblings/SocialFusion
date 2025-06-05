import Foundation
import Logging

/// A structured logging system for the SocialFusion application.
public struct StructuredLogger {
    /// The underlying logger.
    private let logger: Logger

    /// Creates a new structured logger.
    /// - Parameter label: The label for the logger.
    public init(label: String) {
        self.logger = Logger(label: label)
    }

    /// Logs a structured message with the specified level and context.
    /// - Parameters:
    ///   - level: The log level.
    ///   - message: The message to log.
    ///   - context: The context for the log entry.
    ///   - file: The file where the log originated.
    ///   - function: The function where the log originated.
    ///   - line: The line number where the log originated.
    public func log(
        level: Logger.Level,
        message: String,
        context: LogContext,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        var metadata: Logger.Metadata = [
            "file": "\(file)",
            "function": "\(function)",
            "line": "\(line)",
            "context": "\(context.name)",
            "timestamp": "\(Date())",
        ]

        if let error = context.error {
            metadata["error"] = "\(error.localizedDescription)"
        }

        if !context.attributes.isEmpty {
            metadata["attributes"] = .dictionary(context.attributes)
        }

        logger.log(level: level, "\(message)", metadata: metadata)
    }

    /// Logs a debug message with the specified context.
    public func debug(
        _ message: String,
        context: LogContext,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(
            level: .debug, message: message, context: context, file: file, function: function,
            line: line)
    }

    /// Logs an info message with the specified context.
    public func info(
        _ message: String,
        context: LogContext,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(
            level: .info, message: message, context: context, file: file, function: function,
            line: line)
    }

    /// Logs a warning message with the specified context.
    public func warning(
        _ message: String,
        context: LogContext,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(
            level: .warning, message: message, context: context, file: file, function: function,
            line: line)
    }

    /// Logs an error message with the specified context.
    public func error(
        _ message: String,
        context: LogContext,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        log(
            level: .error, message: message, context: context, file: file, function: function,
            line: line)
    }
}

/// A context for structured logging.
public struct LogContext {
    /// The name of the context.
    public let name: String
    /// The error associated with the context, if any.
    public let error: Error?
    /// Additional attributes for the context.
    public let attributes: Logger.Metadata

    /// Creates a new log context.
    /// - Parameters:
    ///   - name: The name of the context.
    ///   - error: The error associated with the context, if any.
    ///   - attributes: Additional attributes for the context.
    public init(
        name: String,
        error: Error? = nil,
        attributes: Logger.Metadata = [:]
    ) {
        self.name = name
        self.error = error
        self.attributes = attributes
    }

    /// Creates a new log context with the specified attributes.
    /// - Parameters:
    ///   - name: The name of the context.
    ///   - error: The error associated with the context, if any.
    ///   - attributes: Additional attributes for the context.
    public static func context(
        name: String,
        error: Error? = nil,
        attributes: Logger.Metadata = [:]
    ) -> LogContext {
        LogContext(name: name, error: error, attributes: attributes)
    }
}
