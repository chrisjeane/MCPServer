import Foundation
import Testing
@testable import MCPServer

// Helper to get DiceServer delegate
struct DiceServerTestDelegate: MCPRequestHandlerDelegate {
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

            // Validate input parameters
            guard validateDiceParameters(count, sides) else {
                return MCPResponse(
                    id: id,
                    result: nil,
                    error: MCPError(
                        code: -32602,
                        message: "Invalid parameters: count must be 1-100, sides must be 1-10000"
                    )
                )
            }

            let results = rollDice(count: count, sides: sides)

            // Create response with actual roll results
            let resultDict: [String: AnyCodable] = [
                "success": .bool(true),
                "results": .array(results.map { .int($0) })
            ]

            return MCPResponse(
                id: id,
                result: .success(SuccessResult(success: true, results: resultDict)),
                error: nil
            )
        }

        return MCPResponse(
            id: id,
            result: nil,
            error: MCPError(code: -32601, message: "Tool not found")
        )
    }

    nonisolated private func validateDiceParameters(_ count: Int, _ sides: Int) -> Bool {
        return count >= 1 && count <= 100 && sides >= 1 && sides <= 10000
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

// MARK: - Tests

@Suite("Dice Server Tests")
struct DiceServerTests {
    let delegate = DiceServerTestDelegate()

    @Test("Tool returns actual dice results")
    func toolReturnsResults() async throws {
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: "test-1",
            method: "tools/call",
            params: .toolCall(
                ToolCallParams(
                    name: "roll_dice",
                    arguments: [
                        "count": .int(3),
                        "sides": .int(6)
                    ]
                )
            )
        )

        let response = try await delegate.handleDomainSpecificRequest(request)

        #expect(response != nil)
        guard let response else { return }

        guard case .success(let successResult) = response.result else {
            Issue.record("Result is not success type")
            return
        }

        guard let results = successResult.results else {
            Issue.record("Success result has no results field")
            return
        }

        guard case .array(let resultsArray) = results["results"] else {
            Issue.record("Results field is not an array")
            return
        }

        #expect(resultsArray.count == 3)

        // Verify all results are valid dice values (1-6)
        for (index, result) in resultsArray.enumerated() {
            guard case .int(let value) = result else {
                Issue.record("Result at index \(index) is not an integer")
                return
            }
            #expect(value >= 1 && value <= 6, "Result value \(value) is outside range 1-6")
        }
    }

    @Test("Rejects count > 100")
    func rejectsCountTooHigh() async throws {
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: "test-2",
            method: "tools/call",
            params: .toolCall(
                ToolCallParams(
                    name: "roll_dice",
                    arguments: [
                        "count": .int(1000),
                        "sides": .int(6)
                    ]
                )
            )
        )

        let response = try await delegate.handleDomainSpecificRequest(request)

        #expect(response != nil)
        guard let response else { return }
        #expect(response.error != nil, "Expected error for invalid count")
        #expect(response.error?.code == -32602)
    }

    @Test("Rejects sides = 0")
    func rejectsSidesZero() async throws {
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: "test-3",
            method: "tools/call",
            params: .toolCall(
                ToolCallParams(
                    name: "roll_dice",
                    arguments: [
                        "count": .int(1),
                        "sides": .int(0)
                    ]
                )
            )
        )

        let response = try await delegate.handleDomainSpecificRequest(request)

        #expect(response != nil)
        guard let response else { return }
        #expect(response.error != nil, "Expected error for sides=0")
        #expect(response.error?.code == -32602)
    }

    @Test("Rejects sides > 10000")
    func rejectsSidesTooHigh() async throws {
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: "test-4",
            method: "tools/call",
            params: .toolCall(
                ToolCallParams(
                    name: "roll_dice",
                    arguments: [
                        "count": .int(1),
                        "sides": .int(100000)
                    ]
                )
            )
        )

        let response = try await delegate.handleDomainSpecificRequest(request)

        #expect(response != nil)
        guard let response else { return }
        #expect(response.error != nil, "Expected error for sides > 10000")
        #expect(response.error?.code == -32602)
    }

    @Test("Rejects negative count")
    func rejectsNegativeCount() async throws {
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: "test-5",
            method: "tools/call",
            params: .toolCall(
                ToolCallParams(
                    name: "roll_dice",
                    arguments: [
                        "count": .int(-5),
                        "sides": .int(6)
                    ]
                )
            )
        )

        let response = try await delegate.handleDomainSpecificRequest(request)

        #expect(response != nil)
        guard let response else { return }
        #expect(response.error != nil, "Expected error for negative count")
        #expect(response.error?.code == -32602)
    }

    @Test("Uses default parameters when not provided")
    func defaultParameters() async throws {
        let request = MCPRequest(
            jsonrpc: "2.0",
            id: "test-6",
            method: "tools/call",
            params: .toolCall(
                ToolCallParams(
                    name: "roll_dice",
                    arguments: nil
                )
            )
        )

        let response = try await delegate.handleDomainSpecificRequest(request)

        #expect(response != nil)
        guard let response else { return }

        guard case .success(let successResult) = response.result else {
            Issue.record("Expected success result")
            return
        }

        guard let results = successResult.results else {
            Issue.record("Success result has no results field")
            return
        }

        guard case .array(let resultsArray) = results["results"] else {
            Issue.record("Results field is not an array")
            return
        }

        #expect(resultsArray.count == 1, "Default should be 1d6")

        if case .int(let value) = resultsArray[0] {
            #expect(value >= 1 && value <= 6, "Result outside range 1-6")
        }
    }

    @Test("Tool definition is accurate")
    func toolDefinition() {
        let tools = delegate.buildToolDefinitions()

        #expect(tools.count == 1)
        #expect(tools[0].name == "roll_dice")
        #expect(tools[0].inputSchema.properties.keys.contains("count"))
        #expect(tools[0].inputSchema.properties.keys.contains("sides"))
    }
}
