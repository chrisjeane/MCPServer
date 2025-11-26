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
        guard request.params != nil else {
            return MCPResponse(
                id: id,
                result: nil,
                error: MCPError(code: -32602, message: "Missing parameters")
            )
        }

        if let toolName = extractToolName(from: request),
           toolName == "roll_dice" {
            _ = rollDice(count: 1, sides: 6)
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

    nonisolated private func extractToolName(from request: MCPRequest) -> String? {
        // This is a simplified extraction - in a real implementation,
        // you'd properly parse the params structure
        nil
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
        let transport = StdioTransport(handler: handler)

        do {
            try await transport.start()
        } catch {
            FileHandle.standardError.write("Error: \(error)\n".data(using: .utf8) ?? Data())
        }
    }
}
