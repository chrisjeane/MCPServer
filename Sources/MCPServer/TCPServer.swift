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

public final class TCPServer: Sendable {
    private let handler: MCPRequestHandler
    private let verbose: Bool
    private let host: String
    private let port: Int

    public init(handler: MCPRequestHandler, host: String, port: Int, verbose: Bool = false) {
        self.handler = handler
        self.host = host
        self.port = port
        self.verbose = verbose
    }

    public func start() async throws {
        if verbose {
            await logToStderr("MCPServer: Starting TCP server on \(host):\(port)")
        }

        let serverSocket = try createServerSocket()

        if verbose {
            await logToStderr("MCPServer: Listening on \(host):\(port)")
        }

        // Accept connections indefinitely
        while true {
            logToStderrSync("DEBUG: Entering accept loop, calling acceptConnection...")
            do {
                let clientSocket = try acceptConnection(on: serverSocket)
                logToStderrSync("DEBUG: acceptConnection returned socket \(clientSocket)")

                // Handle each connection concurrently on a background queue
                logToStderrSync("DEBUG: Creating queue for handleClient")
                DispatchQueue.global(qos: .userInitiated).async { [self] in
                    self.logToStderrSync("DEBUG: Handler started for socket \(clientSocket)")
                    // Use a semaphore to wait for async operation
                    let semaphore = DispatchSemaphore(value: 0)
                    Task {
                        await self.handleClient(socket: clientSocket)
                        semaphore.signal()
                    }
                    semaphore.wait()
                    self.logToStderrSync("DEBUG: Handler completed for socket \(clientSocket)")
                }
                logToStderrSync("DEBUG: Handler queued, returning to accept loop")
            } catch {
                logToStderrSync("DEBUG: acceptConnection threw error: \(error)")
                await logToStderr("MCPServer: Error accepting connection: \(error)")
                // Continue accepting new connections
            }
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

        return clientSocket
    }

    nonisolated private func handleClient(socket: Int32) async {
        defer {
            close(socket)
        }

        logToStderrSync("DEBUG: handleClient called for socket \(socket)")

        if verbose {
            await logToStderr("MCPServer: Client connected")
        }

        let inputStream = FileInputStream(socket: socket)
        let outputStream = FileOutputStream(socket: socket)

        while true {
            do {
                logToStderrSync("DEBUG: Calling readMessage()")
                guard let messageData = try inputStream.readMessage() else {
                    logToStderrSync("DEBUG: readMessage() returned nil (EOF)")
                    break
                }

                if let messageStr = String(data: messageData, encoding: .utf8) {
                    logToStderrSync("DEBUG: readMessage() returned: \(messageStr)")
                    if verbose {
                        await logToStderr("MCPServer: Received: \(messageStr)")
                    }
                }

                logToStderrSync("DEBUG: Calling handler.handleRequest()")
                if let responseData = await handler.handleRequest(messageData) {
                    if let responseStr = String(data: responseData, encoding: .utf8) {
                        logToStderrSync("DEBUG: Got response: \(responseStr.prefix(100))")
                        if verbose {
                            await logToStderr("MCPServer: Sending: \(responseStr)")
                        }
                    }

                    try outputStream.writeMessage(responseData)
                    logToStderrSync("DEBUG: Response sent")
                } else {
                    logToStderrSync("DEBUG: handler returned nil")
                    if verbose {
                        await logToStderr("MCPServer: No response generated for request")
                    }
                }
            } catch {
                logToStderrSync("DEBUG: Exception: \(error)")
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

public enum SocketError: Error, LocalizedError {
    case socketCreationFailed
    case socketOptionFailed
    case invalidAddress
    case bindFailed
    case listenFailed
    case acceptFailed
    case readFailed
    case writeFailed

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
        case .readFailed:
            return "Failed to read from socket"
        case .writeFailed:
            return "Failed to write to socket"
        }
    }
}

// MARK: - Socket Input Stream

private class FileInputStream {
    private let socket: Int32
    private var buffer: Data = Data()
    private let bufferSize = 4096

    init(socket: Int32) {
        self.socket = socket
    }

    func readMessage() throws -> Data? {
        // MCP uses Content-Length headers: "Content-Length: {N}\r\n\r\n{payload}"
        // Read until we find the double CRLF that separates header from body

        let doubleCrlfBytes: [UInt8] = [13, 10, 13, 10]  // \r\n\r\n

        while true {
            // Look for double CRLF in buffer
            if let range = buffer.range(of: Data(doubleCrlfBytes)) {
                let headerEnd = buffer.distance(from: buffer.startIndex, to: range.lowerBound)
                let headerData = buffer.subdata(in: 0..<headerEnd)
                let payloadStart = headerEnd + 4  // Skip \r\n\r\n

                // Parse Content-Length header
                guard let headerStr = String(data: headerData, encoding: .utf8) else {
                    throw SocketError.readFailed
                }

                guard let contentLengthLine = headerStr.split(separator: "\r").first else {
                    throw SocketError.readFailed
                }

                let parts = contentLengthLine.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "Content-Length" else {
                    throw SocketError.readFailed
                }

                guard let contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
                    throw SocketError.readFailed
                }

                // Read exactly contentLength bytes
                while buffer.count < payloadStart + contentLength {
                    var readBuffer = [UInt8](repeating: 0, count: bufferSize)
                    let bytesRead = read(socket, &readBuffer, bufferSize)

                    if bytesRead > 0 {
                        buffer.append(contentsOf: readBuffer[0..<bytesRead])
                    } else if bytesRead == 0 {
                        // Connection closed
                        return nil
                    } else {
                        // Error occurred
                        #if os(Linux)
                        let err = Darwin.errno
                        #else
                        let err = Darwin.errno
                        #endif

                        if err == EINTR {
                            // Interrupted system call, retry
                            continue
                        } else {
                            throw SocketError.readFailed
                        }
                    }
                }

                // Extract payload
                let payloadData = buffer.subdata(in: payloadStart..<(payloadStart + contentLength))
                buffer.removeFirst(payloadStart + contentLength)

                return payloadData
            }

            // Need more data for header
            var readBuffer = [UInt8](repeating: 0, count: bufferSize)
            let bytesRead = read(socket, &readBuffer, bufferSize)

            if bytesRead > 0 {
                buffer.append(contentsOf: readBuffer[0..<bytesRead])
            } else if bytesRead == 0 {
                // Connection closed
                return nil
            } else {
                // Error occurred
                #if os(Linux)
                let err = Darwin.errno
                #else
                let err = Darwin.errno
                #endif

                if err == EINTR {
                    // Interrupted system call, retry
                    continue
                } else {
                    throw SocketError.readFailed
                }
            }
        }
    }
}

// MARK: - Socket Output Stream

private class FileOutputStream {
    private let socket: Int32

    init(socket: Int32) {
        self.socket = socket
    }

    func writeMessage(_ data: Data) throws {
        // MCP framing: "Content-Length: {N}\r\n\r\n{payload}"
        let header = "Content-Length: \(data.count)\r\n\r\n"
        guard let headerData = header.data(using: .utf8) else {
            throw SocketError.writeFailed
        }

        // Write header
        var bytesWritten = 0
        while bytesWritten < headerData.count {
            let written = headerData.withUnsafeBytes { buffer in
                write(socket, buffer.baseAddress! + bytesWritten, headerData.count - bytesWritten)
            }

            if written > 0 {
                bytesWritten += written
            } else if written < 0 {
                // Error occurred
                #if os(Linux)
                let err = Darwin.errno
                #else
                let err = Darwin.errno
                #endif

                if err == EINTR {
                    // Interrupted system call, retry
                    continue
                } else {
                    throw SocketError.writeFailed
                }
            } else {
                // written == 0, which shouldn't happen on blocking sockets
                // but if it does, we should retry
                continue
            }
        }

        // Write payload
        bytesWritten = 0
        while bytesWritten < data.count {
            let written = data.withUnsafeBytes { buffer in
                write(socket, buffer.baseAddress! + bytesWritten, data.count - bytesWritten)
            }

            if written > 0 {
                bytesWritten += written
            } else if written < 0 {
                // Error occurred
                #if os(Linux)
                let err = Darwin.errno
                #else
                let err = Darwin.errno
                #endif

                if err == EINTR {
                    // Interrupted system call, retry
                    continue
                } else {
                    throw SocketError.writeFailed
                }
            } else {
                // written == 0, which shouldn't happen on blocking sockets
                // but if it does, we should retry
                continue
            }
        }
    }
}
