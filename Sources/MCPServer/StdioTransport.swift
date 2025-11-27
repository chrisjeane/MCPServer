import Foundation
import Darwin

/// Actor-based stdio transport for MCP server communication.
/// Provides thread-safe message reading/writing via stdin/stdout.
public actor StdioTransport {
    private let handler: MCPRequestHandler
    private let verbose: Bool
    private var stdinBuffer = Data()
    private let stdinFd: Int32 = STDIN_FILENO
    private let stdoutFd: Int32 = STDOUT_FILENO
    private let stderrFd: Int32 = STDERR_FILENO

    // Constants to avoid magic numbers
    private static let defaultBufferSize = 4096
    private static let doubleCrlfBytes: [UInt8] = [13, 10, 13, 10]  // \r\n\r\n
    private static let doubleCrlfLength = 4

    public init(handler: MCPRequestHandler, verbose: Bool = false) {
        self.handler = handler
        self.verbose = verbose
    }

    /// Start the stdio transport loop.
    /// This method runs indefinitely until EOF is reached or cancellation occurs.
    public func start() async throws {
        if verbose {
            await logToStderr("MCPServer: Starting stdio transport")
        }

        while !Task.isCancelled {
            // Read message with Content-Length header
            guard let messageData = try await readMessage() else {
                // EOF reached
                break
            }

            if let messageStr = String(data: messageData, encoding: .utf8) {
                if verbose {
                    await logToStderr("MCPServer: Received: \(messageStr)")
                }
            }

            if let responseData = await handler.handleRequest(messageData) {
                if let responseStr = String(data: responseData, encoding: .utf8) {
                    if verbose {
                        await logToStderr("MCPServer: Sending: \(responseStr)")
                    }
                }

                // Write with Content-Length header
                try await writeMessage(responseData)
            }
        }

        if verbose {
            await logToStderr("MCPServer: Stdio transport closed")
        }
    }

    /// Reads one complete MCP message from stdin.
    /// Returns nil on EOF, throws on errors.
    private func readMessage() async throws -> Data? {
        // MCP uses Content-Length headers: "Content-Length: {N}\r\n\r\n{payload}"
        let doubleCrlfData = Data(Self.doubleCrlfBytes)

        while !Task.isCancelled {
            // Look for double CRLF in buffer
            if let range = stdinBuffer.range(of: doubleCrlfData) {
                let headerEnd = stdinBuffer.distance(from: stdinBuffer.startIndex, to: range.lowerBound)
                let headerData = stdinBuffer.subdata(in: 0..<headerEnd)
                let payloadStart = headerEnd + Self.doubleCrlfLength

                // Parse Content-Length header
                guard let headerStr = String(data: headerData, encoding: .utf8) else {
                    throw StdioError.invalidHeader
                }

                let lines = headerStr.split(separator: "\r")
                guard let firstLine = lines.first else {
                    throw StdioError.invalidHeader
                }

                let parts = firstLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, String(parts[0]).trimmingCharacters(in: .whitespaces) == "Content-Length" else {
                    throw StdioError.missingContentLength
                }

                guard let contentLength = Int(String(parts[1]).trimmingCharacters(in: .whitespaces)),
                      contentLength >= 0,
                      contentLength <= 10_000_000 else {  // 10MB max message size
                    throw StdioError.invalidContentLength
                }

                // Read exactly contentLength bytes
                let requiredBytes = payloadStart + contentLength
                while stdinBuffer.count < requiredBytes {
                    let data = try await readFromStdin()
                    guard let data else {
                        throw StdioError.unexpectedEOF
                    }
                    stdinBuffer.append(data)
                }

                // Extract payload
                let payloadData = stdinBuffer.subdata(in: payloadStart..<requiredBytes)
                stdinBuffer = Data(stdinBuffer.dropFirst(requiredBytes))

                return payloadData
            }

            // Need more data for header
            guard let data = try await readFromStdin() else {
                return nil  // Clean EOF
            }
            stdinBuffer.append(data)
        }

        return nil  // Cancelled
    }

    /// Performs a non-blocking read from stdin using async/await.
    /// Returns nil on EOF, throws on errors.
    private func readFromStdin() async throws -> Data? {
        // Use Task.detached to perform blocking I/O off the actor
        return try await Task.detached {
            var buffer = [UInt8](repeating: 0, count: Self.defaultBufferSize)
            let bytesRead = Darwin.read(STDIN_FILENO, &buffer, Self.defaultBufferSize)

            if bytesRead < 0 {
                // Capture errno immediately before any other system calls
                let errorCode = errno

                // Check for EINTR (interrupted system call)
                if errorCode == EINTR {
                    // Retry by returning empty data
                    return Data()
                }
                throw StdioError.readFailed(errorCode: errorCode)
            } else if bytesRead == 0 {
                return nil  // EOF
            }

            return Data(buffer[0..<bytesRead])
        }.value
    }

    /// Writes an MCP message to stdout with proper framing.
    /// Throws on write errors.
    private func writeMessage(_ data: Data) async throws {
        // MCP framing: "Content-Length: {N}\r\n\r\n{payload}"
        let header = "Content-Length: \(data.count)\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else {
            throw StdioError.invalidEncoding
        }

        // Use Task.detached to perform blocking I/O off the actor
        try await Task.detached {
            // Write header
            try Self.writeAll(data: headerData, to: STDOUT_FILENO)
            // Write payload
            try Self.writeAll(data: data, to: STDOUT_FILENO)
        }.value
    }

    /// Writes all data to the given file descriptor, handling partial writes and interrupts.
    private static func writeAll(data: Data, to fd: Int32) throws {
        var bytesWritten = 0
        let totalBytes = data.count

        while bytesWritten < totalBytes {
            let written = data.withUnsafeBytes { buffer in
                Darwin.write(fd, buffer.baseAddress! + bytesWritten, totalBytes - bytesWritten)
            }

            if written > 0 {
                bytesWritten += written
            } else if written < 0 {
                // Capture errno immediately
                let errorCode = errno

                if errorCode == EINTR {
                    // Interrupted, retry
                    continue
                }
                throw StdioError.writeFailed(errorCode: errorCode)
            } else {
                // written == 0, should not happen on blocking sockets
                // but retry to be safe
                continue
            }
        }
    }

    private func logToStderr(_ message: String) async {
        let stderrHandle = FileHandle.standardError
        if let data = "\(message)\n".data(using: .utf8) {
            stderrHandle.write(data)
        }
    }
}

// MARK: - Errors

/// Errors that can occur during stdio transport operations.
public enum StdioError: Error, LocalizedError {
    case readFailed(errorCode: Int32)
    case writeFailed(errorCode: Int32)
    case invalidHeader
    case missingContentLength
    case invalidContentLength
    case unexpectedEOF
    case invalidEncoding

    public var errorDescription: String? {
        switch self {
        case .readFailed(let code):
            return "Failed to read from stdin: errno \(code)"
        case .writeFailed(let code):
            return "Failed to write to stdout: errno \(code)"
        case .invalidHeader:
            return "Invalid message header"
        case .missingContentLength:
            return "Missing Content-Length header"
        case .invalidContentLength:
            return "Invalid Content-Length value"
        case .unexpectedEOF:
            return "Unexpected end of file while reading message"
        case .invalidEncoding:
            return "Invalid UTF-8 encoding"
        }
    }
}
