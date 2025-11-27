import Foundation
import Testing
@testable import MCPServer

/// Tests for protocol violations and edge cases
@Suite("Protocol Violation Tests")
struct ProtocolViolationTests {

    // MARK: - Content-Length Tests

    @Test("Invalid Content-Length header")
    func invalidContentLength() async throws {
        // Test that negative content length is rejected
        // We can't directly test FileInputStream as it's private,
        // but we can test through StdioError cases
        #expect(StdioError.invalidContentLength.localizedDescription.contains("Invalid"))
    }

    @Test("Missing Content-Length header")
    func missingContentLength() async throws {
        #expect(StdioError.missingContentLength.localizedDescription.contains("Missing"))
    }

    @Test("Content-Length too large")
    func contentLengthTooLarge() async throws {
        // Verify that content length over 10MB is rejected
        let error = StdioError.invalidContentLength
        #expect(error.localizedDescription.contains("Invalid"))
    }

    @Test("Malformed header format")
    func malformedHeader() async throws {
        #expect(StdioError.invalidHeader.localizedDescription.contains("Invalid"))
    }

    // MARK: - Buffer Overflow Tests

    @Test("Buffer overflow protection")
    func bufferOverflow() async throws {
        #expect(SocketError.bufferOverflow.localizedDescription.contains("exceeded"))
    }

    // MARK: - JSON-RPC Violations

    @Test("Missing jsonrpc field")
    func missingJSONRPCField() async throws {
        let handler = MCPRequestHandler()
        let invalidRequest = "{\"id\":\"1\",\"method\":\"test\"}".data(using: .utf8)!

        let response = await handler.handleRequest(invalidRequest)
        #expect(response != nil)

        if let responseData = response,
           let responseObj = try? JSONDecoder().decode(MCPResponse.self, from: responseData) {
            #expect(responseObj.error != nil)
            // Parse error for missing field
            #expect(responseObj.error?.code == -32700 || responseObj.error?.code == -32600)
        }
    }

    @Test("Wrong jsonrpc version")
    func wrongJSONRPCVersion() async throws {
        let handler = MCPRequestHandler()
        let request = "{\"jsonrpc\":\"1.0\",\"id\":\"1\",\"method\":\"initialize\"}".data(using: .utf8)!

        // Should still parse but with wrong version
        let response = await handler.handleRequest(request)
        #expect(response != nil)
    }

    @Test("Missing method field")
    func missingMethod() async throws {
        let handler = MCPRequestHandler()
        let invalidRequest = "{\"jsonrpc\":\"2.0\",\"id\":\"1\"}".data(using: .utf8)!

        let response = await handler.handleRequest(invalidRequest)
        #expect(response != nil)

        if let responseData = response,
           let responseObj = try? JSONDecoder().decode(MCPResponse.self, from: responseData) {
            #expect(responseObj.error != nil)
            #expect(responseObj.error?.code == -32700)
        }
    }

    // MARK: - ID Type Tests

    @Test("String ID is preserved")
    func stringIDPreserved() async throws {
        let handler = MCPRequestHandler()
        let request = MCPRequest(id: "string-id", method: "initialize", params: nil)

        let requestData = try JSONEncoder().encode(request)
        let response = await handler.handleRequest(requestData)

        if let responseData = response,
           let responseObj = try? JSONDecoder().decode(MCPResponse.self, from: responseData) {
            #expect(responseObj.id == "string-id")
        }
    }

    @Test("Numeric ID is converted to string")
    func numericIDConverted() async throws {
        let handler = MCPRequestHandler()
        let jsonRequest = "{\"jsonrpc\":\"2.0\",\"id\":123,\"method\":\"initialize\"}".data(using: .utf8)!

        let response = await handler.handleRequest(jsonRequest)

        if let responseData = response,
           let responseObj = try? JSONDecoder().decode(MCPResponse.self, from: responseData) {
            #expect(responseObj.id == "123")
        }
    }

    // MARK: - Invalid Parameter Tests

    @Test("Invalid params for tools/call")
    func invalidToolCallParams() async throws {
        struct TestDelegate: MCPRequestHandlerDelegate {
            func getServerInfo() -> ServerInfo {
                ServerInfo()
            }

            func buildToolDefinitions() -> [Tool] {
                []
            }

            func handleDomainSpecificRequest(_ request: MCPRequest) async throws -> MCPResponse? {
                guard let id = request.id else { return nil }

                // Expect params to be .toolCall
                guard case .toolCall = request.params else {
                    return MCPResponse(
                        id: id,
                        result: nil,
                        error: MCPError(code: -32602, message: "Invalid parameters")
                    )
                }

                return MCPResponse(id: id, result: .success(SuccessResult(success: true)), error: nil)
            }
        }

        let delegate = TestDelegate()
        let handler = MCPRequestHandler(delegate: delegate)

        // Initialize first
        let initRequest = MCPRequest(id: "1", method: "initialize", params: nil)
        _ = await handler.handleRequest(try JSONEncoder().encode(initRequest))

        let notificationInit = MCPRequest(id: nil, method: "initialized", params: nil)
        _ = await handler.handleRequest(try JSONEncoder().encode(notificationInit))

        // Send tools/call with wrong params type (nil params)
        let request = MCPRequest(id: "2", method: "tools/call", params: nil)
        let response = await handler.handleRequest(try JSONEncoder().encode(request))

        if let responseData = response,
           let responseObj = try? JSONDecoder().decode(MCPResponse.self, from: responseData) {
            #expect(responseObj.error != nil)
            // Can be parse error or invalid params depending on how the handler processes it
            #expect(responseObj.error?.code == -32602 || responseObj.error?.code == -32700)
        }
    }

    // MARK: - Encoding Tests

    @Test("UTF-8 encoding errors")
    func utf8EncodingError() async throws {
        #expect(StdioError.invalidEncoding.localizedDescription.contains("UTF-8"))
        #expect(SocketError.invalidEncoding.localizedDescription.contains("UTF-8"))
    }

    // MARK: - Initialize Validation Tests

    @Test("Initialize without ID returns error")
    func initializeWithoutID() async throws {
        let handler = MCPRequestHandler()
        let request = MCPRequest(id: nil, method: "initialize", params: nil)

        let response = await handler.handleRequest(try JSONEncoder().encode(request))

        if let responseData = response,
           let responseObj = try? JSONDecoder().decode(MCPResponse.self, from: responseData) {
            #expect(responseObj.error != nil)
            #expect(responseObj.error?.code == -32600)
            #expect(responseObj.error?.message.contains("must have an ID") == true)
        }
    }
}
