import Foundation
import Darwin

public actor StdioTransport {
    private let handler: MCPRequestHandler
    private let verbose: Bool
    private var stdinBuffer = Data()
    private let stdinFd: Int32 = STDIN_FILENO
    private let stdoutFd: Int32 = STDOUT_FILENO
    private let stderrFd: Int32 = STDERR_FILENO

    public init(handler: MCPRequestHandler, verbose: Bool = false) {
        self.handler = handler
        self.verbose = verbose
    }

    public func start() async throws {
        if verbose {
            await logToStderr("MCPServer: Starting stdio transport")
        }

        while true {
            // Read message with Content-Length header
            guard let messageData = readMessage() else {
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
                writeMessage(responseData)
            }
        }

        if verbose {
            await logToStderr("MCPServer: Stdio transport closed")
        }
    }

    private func readMessage() -> Data? {
        // MCP uses Content-Length headers: "Content-Length: {N}\r\n\r\n{payload}"
        let doubleCrlfBytes: [UInt8] = [13, 10, 13, 10]  // \r\n\r\n

        while true {
            // Look for double CRLF in buffer
            if let range = stdinBuffer.range(of: Data(doubleCrlfBytes)) {
                let headerEnd = stdinBuffer.distance(from: stdinBuffer.startIndex, to: range.lowerBound)
                let headerData = stdinBuffer.subdata(in: 0..<headerEnd)
                let payloadStart = headerEnd + 4  // Skip \r\n\r\n

                // Parse Content-Length header
                guard let headerStr = String(data: headerData, encoding: .utf8) else {
                    return nil
                }

                let lines = headerStr.split(separator: "\r")
                guard let firstLine = lines.first else {
                    return nil
                }

                let parts = firstLine.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
                guard parts.count == 2, String(parts[0]).trimmingCharacters(in: .whitespaces) == "Content-Length" else {
                    return nil
                }

                guard let contentLength = Int(String(parts[1]).trimmingCharacters(in: .whitespaces)) else {
                    return nil
                }

                // Read exactly contentLength bytes
                let requiredBytes = payloadStart + contentLength
                while stdinBuffer.count < requiredBytes {
                    var buffer = [UInt8](repeating: 0, count: 4096)
                    let bytesRead = Darwin.read(stdinFd, &buffer, 4096)
                    if bytesRead < 0 {
                        // Check for EINTR (interrupted system call)
                        if errno == EINTR {
                            continue  // Retry on interrupt
                        }
                        return nil  // Error
                    } else if bytesRead == 0 {
                        return nil  // EOF
                    }
                    stdinBuffer.append(Data(buffer[0..<bytesRead]))
                }

                // Extract payload
                let payloadData = stdinBuffer.subdata(in: payloadStart..<requiredBytes)
                stdinBuffer = Data(stdinBuffer.dropFirst(requiredBytes))

                return payloadData
            }

            // Need more data for header
            var buffer = [UInt8](repeating: 0, count: 4096)
            let bytesRead = Darwin.read(stdinFd, &buffer, 4096)
            if bytesRead < 0 {
                // Check for EINTR (interrupted system call)
                if errno == EINTR {
                    continue  // Retry on interrupt
                }
                return nil  // Error
            } else if bytesRead == 0 {
                return nil  // EOF
            }
            stdinBuffer.append(Data(buffer[0..<bytesRead]))
        }
    }

    private func writeMessage(_ data: Data) {
        // MCP framing: "Content-Length: {N}\r\n\r\n{payload}"
        let header = "Content-Length: \(data.count)\r\n\r\n"
        if let headerData = header.data(using: .utf8) {
            let headerBytes = [UInt8](headerData)
            _ = Darwin.write(stdoutFd, headerBytes, headerBytes.count)
        }
        let dataBytes = [UInt8](data)
        _ = Darwin.write(stdoutFd, dataBytes, dataBytes.count)
    }

    private func logToStderr(_ message: String) async {
        let stderrHandle = FileHandle.standardError
        if let data = "\(message)\n".data(using: .utf8) {
            stderrHandle.write(data)
        }
    }
}
