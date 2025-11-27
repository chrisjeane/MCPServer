import Foundation

#if os(Linux)
import Glibc
#else
import Darwin
#endif

// Socket wrapper function to handle platform differences
private func createSocket() -> Int32 {
    #if os(Linux)
    let result = socket(AF_INET, Int32(SOCK_STREAM.rawValue), 0)
    return Int32(result)
    #else
    return socket(AF_INET, SOCK_STREAM, 0)
    #endif
}

/// TCP server for MCP protocol communication.
/// Handles multiple concurrent connections with proper resource limits and cancellation support.
public final class TCPServer: Sendable {
    private let handler: MCPRequestHandler
    private let verbose: Bool
    private let host: String
    private let port: Int

    // Constants for server configuration
    private static let maxConnections = 100
    private static let capacityCheckInterval: UInt64 = 100_000_000  // 100ms in nanoseconds

    public init(handler: MCPRequestHandler, host: String, port: Int, verbose: Bool = false) {
        self.handler = handler
        self.host = host
        self.port = port
        self.verbose = verbose
    }

    /// Starts the TCP server and accepts incoming connections.
    /// This method runs indefinitely until cancelled or an error occurs.
    public func start() async throws {
        if verbose {
            await logToStderr("MCPServer: Starting TCP server on \(host):\(port)")
        }

        let serverSocket = try createServerSocket()
        defer {
            close(serverSocket)
        }

        if verbose {
            await logToStderr("MCPServer: Listening on \(host):\(port)")
        }

        // Use structured concurrency to manage connection lifetime
        try await withThrowingTaskGroup(of: Void.self) { group in
            // Actor-isolated counter for thread-safe connection tracking
            actor ConnectionCounter {
                var count = 0

                /// Atomically increment and return whether we're still below capacity.
                /// This eliminates the race window between check and increment.
                func tryIncrement(max: Int) -> Bool {
                    guard count < max else {
                        return false
                    }
                    count += 1
                    return true
                }

                func decrement() {
                    count -= 1
                }
            }

            let counter = ConnectionCounter()

            while !Task.isCancelled {
                // Accept a new connection
                do {
                    // Atomically check and increment to prevent race condition
                    if await counter.tryIncrement(max: Self.maxConnections) {
                        let clientSocket = try acceptConnection(on: serverSocket)

                        if verbose {
                            await logToStderr("MCPServer: Accepted connection on socket \(clientSocket)")
                        }

                        // Add task to handle this connection
                        group.addTask { [self, counter] in
                            defer {
                                Task {
                                    await counter.decrement()
                                }
                            }
                            await self.handleClient(socket: clientSocket)
                        }
                    } else {
                        // At capacity - wait a bit before trying again
                        try await Task.sleep(nanoseconds: Self.capacityCheckInterval)
                    }
                } catch {
                    if verbose {
                        await logToStderr("MCPServer: Error accepting connection: \(error)")
                    }
                    // Continue accepting new connections on error
                }
            }

            // Wait for all connections to complete on shutdown
            try await group.waitForAll()
        }
    }

    private func createServerSocket() throws -> Int32 {
        let fd = createSocket()
        guard fd >= 0 else {
            throw SocketError.socketCreationFailed
        }

        // Enable address reuse
        var reuseAddr: Int32 = 1
        let reuseResult = setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuseAddr, socklen_t(MemoryLayout<Int32>.size))
        guard reuseResult == 0 else {
            close(fd)
            throw SocketError.socketOptionFailed
        }

        // Bind socket
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian

        let hostCString = host.cString(using: .utf8)
        guard inet_aton(hostCString, &addr.sin_addr) != 0 else {
            close(fd)
            throw SocketError.invalidAddress
        }

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            bind(fd, UnsafeRawPointer(ptr).assumingMemoryBound(to: sockaddr.self), socklen_t(MemoryLayout<sockaddr_in>.size))
        }

        guard bindResult == 0 else {
            close(fd)
            throw SocketError.bindFailed
        }

        // Listen
        let listenResult = listen(fd, 128)
        guard listenResult == 0 else {
            close(fd)
            throw SocketError.listenFailed
        }

        return fd
    }

    private func acceptConnection(on serverSocket: Int32) throws -> Int32 {
        var clientAddr = sockaddr_in()
        var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
            accept(serverSocket, UnsafeMutableRawPointer(ptr).assumingMemoryBound(to: sockaddr.self), &clientAddrLen)
        }

        guard clientSocket >= 0 else {
            throw SocketError.acceptFailed
        }

        // Configure socket timeouts for read and write operations
        try setSocketTimeouts(socket: clientSocket, readTimeout: 30, writeTimeout: 10)

        return clientSocket
    }

    private func setSocketTimeouts(socket: Int32, readTimeout: Int, writeTimeout: Int) throws {
        // Set read timeout (SO_RCVTIMEO)
        #if os(Linux)
        var readTV = timeval(tv_sec: Int(readTimeout), tv_usec: 0)
        #else
        var readTV = timeval(tv_sec: __darwin_time_t(readTimeout), tv_usec: 0)
        #endif

        let readResult = setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &readTV, socklen_t(MemoryLayout<timeval>.size))
        guard readResult == 0 else {
            close(socket)  // Prevent file descriptor leak
            throw SocketError.socketOptionFailed
        }

        // Set write timeout (SO_SNDTIMEO)
        #if os(Linux)
        var writeTV = timeval(tv_sec: Int(writeTimeout), tv_usec: 0)
        #else
        var writeTV = timeval(tv_sec: __darwin_time_t(writeTimeout), tv_usec: 0)
        #endif

        let writeResult = setsockopt(socket, SOL_SOCKET, SO_SNDTIMEO, &writeTV, socklen_t(MemoryLayout<timeval>.size))
        guard writeResult == 0 else {
            close(socket)  // Prevent file descriptor leak
            throw SocketError.socketOptionFailed
        }
    }

    nonisolated private func handleClient(socket: Int32) async {
        defer {
            // Graceful shutdown: shutdown before close
            shutdown(socket, SHUT_RDWR)
            close(socket)
        }

        if verbose {
            await logToStderr("MCPServer: Client connected")
        }

        let inputStream = FileInputStream(socket: socket)
        let outputStream = FileOutputStream(socket: socket)

        while true {
            do {
                guard let messageData = try inputStream.readMessage() else {
                    break
                }

                if verbose {
                    if let messageStr = String(data: messageData, encoding: .utf8) {
                        await logToStderr("MCPServer: Received: \(messageStr)")
                    }
                }

                if let responseData = await handler.handleRequest(messageData) {
                    try outputStream.writeMessage(responseData)

                    if verbose {
                        if let responseStr = String(data: responseData, encoding: .utf8) {
                            await logToStderr("MCPServer: Sending: \(responseStr)")
                        }
                    }
                } else if verbose {
                    await logToStderr("MCPServer: No response generated for request")
                }
            } catch {
                await logToStderr("MCPServer: Client error: \(error)")
                break
            }
        }

        if verbose {
            await logToStderr("MCPServer: Client disconnected")
        }
    }

    nonisolated private func logToStderrSync(_ message: String) {
        if let data = "\(message)\n".data(using: .utf8) {
            FileHandle.standardError.write(data)
        }
    }

    nonisolated private func logToStderr(_ message: String) async {
        let stderrHandle = FileHandle.standardError
        if let data = "\(message)\n".data(using: .utf8) {
            stderrHandle.write(data)
        }
    }
}

// MARK: - Socket Utilities

/// Errors that can occur during socket operations.
public enum SocketError: Error, LocalizedError, Sendable {
    case socketCreationFailed
    case socketOptionFailed
    case invalidAddress
    case bindFailed
    case listenFailed
    case acceptFailed
    case readFailed(errorCode: Int32)
    case writeFailed(errorCode: Int32)
    case invalidHeader
    case missingContentLength
    case invalidContentLength
    case unexpectedEOF
    case bufferOverflow
    case invalidEncoding

    public var errorDescription: String? {
        switch self {
        case .socketCreationFailed:
            return "Failed to create socket"
        case .socketOptionFailed:
            return "Failed to set socket option"
        case .invalidAddress:
            return "Invalid address"
        case .bindFailed:
            return "Failed to bind socket"
        case .listenFailed:
            return "Failed to listen on socket"
        case .acceptFailed:
            return "Failed to accept connection"
        case .readFailed(let code):
            return "Failed to read from socket: errno \(code)"
        case .writeFailed(let code):
            return "Failed to write to socket: errno \(code)"
        case .invalidHeader:
            return "Invalid message header"
        case .missingContentLength:
            return "Missing Content-Length header"
        case .invalidContentLength:
            return "Invalid Content-Length value"
        case .unexpectedEOF:
            return "Unexpected end of file while reading message"
        case .bufferOverflow:
            return "Buffer size exceeded maximum allowed (10MB)"
        case .invalidEncoding:
            return "Invalid UTF-8 encoding"
        }
    }
}

// MARK: - Socket Input Stream

/// Thread-safe input stream for reading MCP protocol messages from a socket.
/// Handles Content-Length framing and buffer management with bounded memory growth.
private final class FileInputStream: @unchecked Sendable {
    private let socket: Int32
    private var buffer: Data = Data()
    private static let bufferSize = 4096
    private static let maxBufferSize = 10_000_000  // 10MB max to prevent unbounded growth
    private static let doubleCrlfBytes: [UInt8] = [13, 10, 13, 10]  // \r\n\r\n
    private static let doubleCrlfLength = 4
    private static let maxContentLength = 10_000_000  // 10MB max message size

    init(socket: Int32) {
        self.socket = socket
    }

    func readMessage() throws -> Data? {
        // MCP uses Content-Length headers: "Content-Length: {N}\r\n\r\n{payload}"
        let doubleCrlfData = Data(Self.doubleCrlfBytes)

        while true {
            // Prevent unbounded buffer growth
            guard buffer.count <= Self.maxBufferSize else {
                throw SocketError.bufferOverflow
            }

            // Look for double CRLF in buffer
            if let range = buffer.range(of: doubleCrlfData) {
                let headerEnd = buffer.distance(from: buffer.startIndex, to: range.lowerBound)
                let headerData = buffer.subdata(in: 0..<headerEnd)
                let payloadStart = headerEnd + Self.doubleCrlfLength

                // Parse Content-Length header
                guard let headerStr = String(data: headerData, encoding: .utf8) else {
                    throw SocketError.invalidHeader
                }

                guard let contentLengthLine = headerStr.split(separator: "\r").first else {
                    throw SocketError.invalidHeader
                }

                let parts = contentLengthLine.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "Content-Length" else {
                    throw SocketError.missingContentLength
                }

                guard let contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)),
                      contentLength >= 0,
                      contentLength <= Self.maxContentLength else {
                    throw SocketError.invalidContentLength
                }

                // Read exactly contentLength bytes
                let requiredBytes = payloadStart + contentLength
                while buffer.count < requiredBytes {
                    let data = try readFromSocket()
                    guard let data else {
                        throw SocketError.unexpectedEOF
                    }
                    buffer.append(data)

                    // Check for overflow again
                    guard buffer.count <= Self.maxBufferSize else {
                        throw SocketError.bufferOverflow
                    }
                }

                // Extract payload
                let payloadData = buffer.subdata(in: payloadStart..<requiredBytes)
                buffer.removeFirst(requiredBytes)

                return payloadData
            }

            // Need more data for header
            guard let data = try readFromSocket() else {
                return nil  // Clean EOF
            }
            buffer.append(data)
        }
    }

    /// Reads data from socket, handling interrupts and capturing errno safely.
    private func readFromSocket() throws -> Data? {
        var readBuffer = [UInt8](repeating: 0, count: Self.bufferSize)
        let bytesRead = read(socket, &readBuffer, Self.bufferSize)

        if bytesRead > 0 {
            return Data(readBuffer[0..<bytesRead])
        } else if bytesRead == 0 {
            return nil  // EOF
        } else {
            // Capture errno immediately before any other system calls
            #if os(Linux)
            let errorCode = errno
            #else
            let errorCode = errno
            #endif

            if errorCode == EINTR {
                // Interrupted, retry by returning empty data
                return Data()
            } else {
                throw SocketError.readFailed(errorCode: errorCode)
            }
        }
    }
}

// MARK: - Socket Output Stream

/// Thread-safe output stream for writing MCP protocol messages to a socket.
/// Handles Content-Length framing and partial write scenarios.
private final class FileOutputStream: @unchecked Sendable {
    private let socket: Int32

    init(socket: Int32) {
        self.socket = socket
    }

    /// Writes a complete MCP message with Content-Length framing.
    /// Handles partial writes and interrupts properly.
    func writeMessage(_ data: Data) throws {
        // MCP framing: "Content-Length: {N}\r\n\r\n{payload}"
        let header = "Content-Length: \(data.count)\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else {
            throw SocketError.invalidEncoding
        }

        // Write header
        try writeAll(data: headerData)

        // Write payload
        try writeAll(data: data)
    }

    /// Writes all data to socket, handling partial writes and interrupts.
    private func writeAll(data: Data) throws {
        var bytesWritten = 0
        let totalBytes = data.count

        while bytesWritten < totalBytes {
            let written = data.withUnsafeBytes { buffer in
                // Safe to force unwrap here as Data guarantees baseAddress for non-empty data
                guard let baseAddress = buffer.baseAddress else {
                    return 0
                }
                return write(socket, baseAddress + bytesWritten, totalBytes - bytesWritten)
            }

            if written > 0 {
                bytesWritten += written
            } else if written < 0 {
                // Capture errno immediately before any other system calls
                #if os(Linux)
                let errorCode = errno
                #else
                let errorCode = errno
                #endif

                if errorCode == EINTR {
                    // Interrupted system call, retry
                    continue
                } else {
                    throw SocketError.writeFailed(errorCode: errorCode)
                }
            } else {
                // written == 0, should not happen on blocking sockets
                // but retry to be safe
                continue
            }
        }
    }
}
