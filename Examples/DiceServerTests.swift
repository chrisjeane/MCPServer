import Foundation
import MCPServer

// Test suite for DiceServer fixes

class DiceServerTestSuite {
    private let delegate = DiceServerDelegate()

    // MARK: - Test: Tool Returns Results

    func testToolReturnsActualResults() async {
        print("Test 1: Tool returns actual dice results...")

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

        let response = await delegate.handleDomainSpecificRequest(request)

        guard let response = response else {
            print("❌ FAILED: Response is nil")
            return
        }

        guard case .success(let successResult) = response.result else {
            print("❌ FAILED: Result is not success type. Got: \(String(describing: response.result))")
            return
        }

        guard let results = successResult.results else {
            print("❌ FAILED: Success result has no results field")
            return
        }

        guard case .array(let resultsArray) = results["results"] else {
            print("❌ FAILED: Results field is not an array")
            return
        }

        guard resultsArray.count == 3 else {
            print("❌ FAILED: Expected 3 results, got \(resultsArray.count)")
            return
        }

        // Verify all results are valid dice values (1-6)
        for (index, result) in resultsArray.enumerated() {
            guard case .int(let value) = result else {
                print("❌ FAILED: Result at index \(index) is not an integer")
                return
            }
            guard value >= 1 && value <= 6 else {
                print("❌ FAILED: Result value \(value) is outside range 1-6")
                return
            }
        }

        print("✅ PASSED: Tool correctly returns \(resultsArray.count) dice rolls")
    }

    // MARK: - Test: Invalid Count Parameter Rejected

    func testRejectsInvalidCountTooHigh() async {
        print("Test 2: Rejects count > 100...")

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

        let response = await delegate.handleDomainSpecificRequest(request)

        guard let response = response else {
            print("❌ FAILED: Response is nil")
            return
        }

        guard let error = response.error else {
            print("❌ FAILED: Expected error, got success response")
            return
        }

        guard error.code == -32602 else {
            print("❌ FAILED: Expected error code -32602, got \(error.code)")
            return
        }

        print("✅ PASSED: Correctly rejected count=1000 with error: \(error.message)")
    }

    // MARK: - Test: Invalid Sides Parameter Rejected

    func testRejectsInvalidSidesZero() async {
        print("Test 3: Rejects sides = 0...")

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

        let response = await delegate.handleDomainSpecificRequest(request)

        guard let response = response else {
            print("❌ FAILED: Response is nil")
            return
        }

        guard let error = response.error else {
            print("❌ FAILED: Expected error, got success response")
            return
        }

        guard error.code == -32602 else {
            print("❌ FAILED: Expected error code -32602, got \(error.code)")
            return
        }

        print("✅ PASSED: Correctly rejected sides=0 with error: \(error.message)")
    }

    // MARK: - Test: Invalid Sides Parameter Too High

    func testRejectsInvalidSidesTooHigh() async {
        print("Test 4: Rejects sides > 10000...")

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

        let response = await delegate.handleDomainSpecificRequest(request)

        guard let response = response else {
            print("❌ FAILED: Response is nil")
            return
        }

        guard let error = response.error else {
            print("❌ FAILED: Expected error, got success response")
            return
        }

        guard error.code == -32602 else {
            print("❌ FAILED: Expected error code -32602, got \(error.code)")
            return
        }

        print("✅ PASSED: Correctly rejected sides=100000 with error: \(error.message)")
    }

    // MARK: - Test: Negative Count Parameter Rejected

    func testRejectsNegativeCount() async {
        print("Test 5: Rejects negative count...")

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

        let response = await delegate.handleDomainSpecificRequest(request)

        guard let response = response else {
            print("❌ FAILED: Response is nil")
            return
        }

        guard let error = response.error else {
            print("❌ FAILED: Expected error, got success response")
            return
        }

        guard error.code == -32602 else {
            print("❌ FAILED: Expected error code -32602, got \(error.code)")
            return
        }

        print("✅ PASSED: Correctly rejected count=-5 with error: \(error.message)")
    }

    // MARK: - Test: Default Parameters

    func testDefaultParameters() async {
        print("Test 6: Uses default parameters when not provided...")

        let request = MCPRequest(
            jsonrpc: "2.0",
            id: "test-6",
            method: "tools/call",
            params: .toolCall(
                ToolCallParams(
                    name: "roll_dice",
                    arguments: nil  // No parameters provided
                )
            )
        )

        let response = await delegate.handleDomainSpecificRequest(request)

        guard let response = response else {
            print("❌ FAILED: Response is nil")
            return
        }

        guard case .success(let successResult) = response.result else {
            print("❌ FAILED: Expected success result")
            return
        }

        guard let results = successResult.results else {
            print("❌ FAILED: Success result has no results field")
            return
        }

        guard case .array(let resultsArray) = results["results"] else {
            print("❌ FAILED: Results field is not an array")
            return
        }

        // Default should be 1d6
        guard resultsArray.count == 1 else {
            print("❌ FAILED: Expected 1 result (default count), got \(resultsArray.count)")
            return
        }

        guard case .int(let value) = resultsArray[0] else {
            print("❌ FAILED: Result is not an integer")
            return
        }

        guard value >= 1 && value <= 6 else {
            print("❌ FAILED: Result value \(value) is outside default range 1-6")
            return
        }

        print("✅ PASSED: Correctly used default parameters (1d6), got: \(resultsArray)")
    }

    // MARK: - Test: Tool Definition Accurate

    func testToolDefinition() {
        print("Test 7: Tool definition is accurate...")

        let tools = delegate.buildToolDefinitions()

        guard tools.count == 1 else {
            print("❌ FAILED: Expected 1 tool, got \(tools.count)")
            return
        }

        let tool = tools[0]
        guard tool.name == "roll_dice" else {
            print("❌ FAILED: Expected tool name 'roll_dice', got '\(tool.name)'")
            return
        }

        guard tool.inputSchema.properties.keys.contains("count") else {
            print("❌ FAILED: Tool schema missing 'count' parameter")
            return
        }

        guard tool.inputSchema.properties.keys.contains("sides") else {
            print("❌ FAILED: Tool schema missing 'sides' parameter")
            return
        }

        print("✅ PASSED: Tool definition is accurate")
    }

    // MARK: - Run All Tests

    func runAllTests() async {
        print("\n🧪 Running DiceServer Test Suite\n")
        print("=" * 50)

        testToolDefinition()
        await testToolReturnsActualResults()
        await testRejectsInvalidCountTooHigh()
        await testRejectsInvalidSidesZero()
        await testRejectsInvalidSidesTooHigh()
        await testRejectsNegativeCount()
        await testDefaultParameters()

        print("=" * 50)
        print("\n✅ All tests completed!")
    }
}

// Extension for string repetition
extension String {
    static func * (lhs: String, rhs: Int) -> String {
        return String(repeating: lhs, count: rhs)
    }
}

// MARK: - Main Test Runner

@main
struct DiceServerTestRunner {
    static func main() async {
        let testSuite = DiceServerTestSuite()
        await testSuite.runAllTests()
    }
}
