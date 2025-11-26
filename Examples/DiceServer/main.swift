import Foundation
import MCPServer

// MARK: - Dice Server Implementation

final class DiceServerDelegate: MCPRequestHandlerDelegate {
    func getServerInfo() -> ServerInfo {
        ServerInfo(name: "Dice Server", version: "1.0.0")
    }

    func buildToolDefinitions() -> [Tool] {
        [
            Tool(
                name: "roll_dice",
                description: "Roll one or more dice and return the results",
                inputSchema: ToolInputSchema(
                    properties: [
                        "count": PropertySchema(
                            type: "integer",
                            description: "Number of dice to roll (default: 1)",
                            enum: nil
                        ),
                        "sides": PropertySchema(
                            type: "integer",
                            description: "Number of sides on each die (default: 6)",
                            enum: nil
                        )
                    ],
                    required: []
                )
            )
        ]
    }

    nonisolated func handleDomainSpecificRequest(_ request: MCPRequest) async throws -> MCPResponse? {
        guard let id = request.id else {
            return nil
        }

        switch request.method {
        case "tools/call":
            return await handleToolCall(request, id: id)
        default:
            return MCPResponse(
                id: id,
                result: nil,
                error: MCPError(code: -32601, message: "Method not found: \(request.method)")
            )
        }
    }

    nonisolated private func handleToolCall(_ request: MCPRequest, id: String) async -> MCPResponse {
        guard let params = request.params else {
            return MCPResponse(
                id: id,
                result: nil,
                error: MCPError(code: -32602, message: "Missing parameters")
            )
        }

        guard case .toolCall(let toolParams) = params else {
            return MCPResponse(
                id: id,
                result: nil,
                error: MCPError(code: -32602, message: "Invalid parameters for tools/call")
            )
        }

        if toolParams.name == "roll_dice" {
            let count = extractIntArgument(toolParams.arguments, key: "count") ?? 1
            let sides = extractIntArgument(toolParams.arguments, key: "sides") ?? 6

            let results = rollDice(count: count, sides: sides)

            return MCPResponse(
                id: id,
                result: .success(SuccessResult(success: true)),
                error: nil
            )
        }

        return MCPResponse(
            id: id,
            result: nil,
            error: MCPError(code: -32601, message: "Tool not found")
        )
    }

    nonisolated private func extractIntArgument(_ arguments: [String: AnyCodable]?, key: String) -> Int? {
        guard let arguments = arguments else { return nil }
        guard let value = arguments[key] else { return nil }

        if case .int(let intValue) = value {
            return intValue
        }
        return nil
    }

    nonisolated private func rollDice(count: Int, sides: Int) -> [Int] {
        var results: [Int] = []
        for _ in 0..<count {
            results.append(Int.random(in: 1...sides))
        }
        return results
    }
}

// MARK: - Main Server

@main
struct DiceServer {
    static func main() async {
        let delegate = DiceServerDelegate()
        let handler = MCPRequestHandler(delegate: delegate)

        // Parse command-line arguments
        let arguments = CommandLine.arguments
        var transportType = "stdio"  // Default transport
        var host = "127.0.0.1"
        var port = 3000

        var i = 1
        while i < arguments.count {
            let arg = arguments[i]

            switch arg {
            case "--transport":
                if i + 1 < arguments.count {
                    transportType = arguments[i + 1]
                    i += 2
                } else {
                    printUsage()
                    return
                }
            case "--host":
                if i + 1 < arguments.count {
                    host = arguments[i + 1]
                    i += 2
                } else {
                    printUsage()
                    return
                }
            case "--port":
                if i + 1 < arguments.count {
                    if let parsedPort = Int(arguments[i + 1]) {
                        port = parsedPort
                        i += 2
                    } else {
                        FileHandle.standardError.write("Error: Invalid port number\n".data(using: .utf8) ?? Data())
                        return
                    }
                } else {
                    printUsage()
                    return
                }
            case "--help", "-h":
                printUsage()
                return
            default:
                FileHandle.standardError.write("Error: Unknown argument '\(arg)'\n".data(using: .utf8) ?? Data())
                printUsage()
                return
            }
        }

        // Start the appropriate transport
        do {
            switch transportType.lowercased() {
            case "stdio":
                let transport = StdioTransport(handler: handler, verbose: true)
                try await transport.start()

            case "http":
                let transport = TCPServer(handler: handler, host: host, port: port, verbose: true)
                try await transport.start()

            default:
                FileHandle.standardError.write("Error: Unknown transport type '\(transportType)'. Use 'stdio' or 'http'.\n".data(using: .utf8) ?? Data())
            }
        } catch {
            FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8) ?? Data())
        }
    }

    private static func printUsage() {
        let usage = """
        Dice Server - MCP Server Example

        Usage: DiceServer [OPTIONS]

        Options:
          --transport <type>    Transport type: 'stdio' (default) or 'http'
          --host <address>      Host address for HTTP transport (default: 127.0.0.1)
          --port <number>       Port number for HTTP transport (default: 3000)
          --help, -h            Display this help message

        Examples:
          DiceServer                                    # Start with stdio transport
          DiceServer --transport http --port 8080      # Start HTTP server on port 8080
          DiceServer --transport http --host 0.0.0.0   # Start HTTP server on all interfaces
        """

        if let data = usage.data(using: .utf8) {
            FileHandle.standardOutput.write(data)
        }
    }
}
