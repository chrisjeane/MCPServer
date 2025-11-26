import Foundation

public actor StdioTransport {
    private let handler: MCPRequestHandler
    private let verbose: Bool
    private var stdinBuffer = Data()

    public init(handler: MCPRequestHandler, verbose: Bool = false) {
        self.handler = handler
        self.verbose = verbose
    }

    public func start() async throws {
        if verbose {
            await logToStderr("MCPServer: Starting stdio transport")
        }

        let outputStream = FileHandle.standardOutput
        let inputStream = FileHandle.standardInput

        while true {
            // Read message with Content-Length header
            guard let messageData = readMessage(from: inputStream) else {
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
                writeMessage(responseData, to: outputStream)
            }
        }

        if verbose {
            await logToStderr("MCPServer: Stdio transport closed")
        }
    }

    private func readMessage(from inputStream: FileHandle) -> Data? {
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

                guard let contentLengthLine = headerStr.split(separator: "\r").first else {
                    return nil
                }

                let parts = contentLengthLine.split(separator: ":", maxSplits: 1)
                guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "Content-Length" else {
                    return nil
                }

                guard let contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
                    return nil
                }

                // Read exactly contentLength bytes
                while stdinBuffer.count < payloadStart + contentLength {
                    let data = inputStream.availableData
                    if data.isEmpty {
                        return nil  // EOF
                    }
                    stdinBuffer.append(data)
                }

                // Extract payload
                let payloadData = stdinBuffer.subdata(in: payloadStart..<(payloadStart + contentLength))
                stdinBuffer.removeFirst(payloadStart + contentLength)

                return payloadData
            }

            // Need more data for header
            let data = inputStream.availableData
            if data.isEmpty {
                return nil  // EOF
            }
            stdinBuffer.append(data)
        }
    }

    private func writeMessage(_ data: Data, to outputStream: FileHandle) {
        // MCP framing: "Content-Length: {N}\r\n\r\n{payload}"
        let header = "Content-Length: \(data.count)\r\n\r\n"
        if let headerData = header.data(using: .utf8) {
            outputStream.write(headerData)
        }
        outputStream.write(data)
    }

    private func logToStderr(_ message: String) async {
        let stderrHandle = FileHandle.standardError
        if let data = "\(message)\n".data(using: .utf8) {
            stderrHandle.write(data)
        }
    }
}
