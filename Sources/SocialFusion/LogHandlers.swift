import Logging

/// A log handler that stores logs in memory for testing and debugging purposes.
public final class InMemoryLogHandler: LogHandler {
    /// The log entries stored by this handler.
    public private(set) var entries: [LogEntry] = []

    /// A log entry containing the message and metadata.
    public struct LogEntry {
        /// The log level of the entry.
        public let level: Logger.Level
        /// The message of the entry.
        public let message: Logger.Message
        /// The metadata of the entry.
        public let metadata: Logger.Metadata
        /// The source of the entry.
        public let source: String
        /// The file where the log originated.
        public let file: String
        /// The function where the log originated.
        public let function: String
        /// The line number where the log originated.
        public let line: UInt
    }

    /// The metadata for this log handler.
    public var metadata: Logger.Metadata = [:]

    /// The log level for this log handler.
    public var logLevel: Logger.Level = .debug

    /// Creates a new in-memory log handler.
    public init() {}

    /// Logs a message with the specified level and metadata.
    public func log(
        level: Logger.Level,
        message: Logger.Message,
        metadata: Logger.Metadata?,
        source: String,
        file: String,
        function: String,
        line: UInt
    ) {
        let entry = LogEntry(
            level: level,
            message: message,
            metadata: metadata ?? [:],
            source: source,
            file: file,
            function: function,
            line: line
        )
        entries.append(entry)
    }

    /// Returns the metadata value for the specified key.
    public subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }

    /// Clears all stored log entries.
    public func clear() {
        entries.removeAll()
    }

    /// Returns all log entries with the specified level.
    public func entries(withLevel level: Logger.Level) -> [LogEntry] {
        entries.filter { $0.level == level }
    }

    /// Returns all log entries containing the specified message.
    public func entries(containing message: String) -> [LogEntry] {
        entries.filter { $0.message.description.contains(message) }
    }
}
