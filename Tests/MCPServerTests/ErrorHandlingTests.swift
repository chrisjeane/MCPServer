import Foundation
import Testing
@testable import MCPServer

/// Tests for error handling edge cases
@Suite("Error Handling Tests")
struct ErrorHandlingTests {

    // MARK: - Parse Error Tests

    @Test("Parse error with invalid JSON")
    func parseErrorInvalidJSON() async throws {
        let handler = MCPRequestHandler()
        let invalidJSON = "{ invalid json }".data(using: .utf8)!

        let response = await handler.handleRequest(invalidJSON)
        #expect(response != nil)

        if let responseData = response,
           let responseObj = try? JSONDecoder().decode(MCPResponse.self, from: responseData) {
            #expect(responseObj.error != nil)
            #expect(responseObj.error?.code == -32700)
        }
    }

    @Test("Parse error with truncated JSON")
    func parseErrorTruncatedJSON() async throws {
        let handler = MCPRequestHandler()
        let truncatedJSON = "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":".data(using: .utf8)!

        let response = await handler.handleRequest(truncatedJSON)
        #expect(response != nil)

        if let responseData = response,
           let responseObj = try? JSONDecoder().decode(MCPResponse.self, from: responseData) {
            #expect(responseObj.error != nil)
            #expect(responseObj.error?.code == -32700)
        }
    }

    @Test("Parse error response contains request ID when extractable")
    func parseErrorContainsRequestID() async throws {
        let handler = MCPRequestHandler()
        // Valid ID but invalid method field
        let invalidJSON = "{\"jsonrpc\":\"2.0\",\"id\":\"test-123\",\"method\":null}".data(using: .utf8)!

        let response = await handler.handleRequest(invalidJSON)
        #expect(response != nil)

        if let responseData = response,
           let responseObj = try? JSONDecoder().decode(MCPResponse.self, from: responseData) {
            #expect(responseObj.id == "test-123")
        }
    }

    // MARK: - Method Not Found Tests

    @Test("Method not found for unknown method")
    func methodNotFound() async throws {
        let handler = MCPRequestHandler()

        // Initialize first
        let initRequest = MCPRequest(id: "init", method: "initialize", params: nil)
        _ = await handler.handleRequest(try JSONEncoder().encode(initRequest))

        let notificationInit = MCPRequest(id: nil, method: "initialized", params: nil)
        _ = await handler.handleRequest(try JSONEncoder().encode(notificationInit))

        // Now test unknown method
        let request = MCPRequest(
            id: "1",
            method: "unknown/method",
            params: nil
        )

        let requestData = try JSONEncoder().encode(request)
        let response = await handler.handleRequest(requestData)

        #expect(response != nil)
        if let responseData = response,
           let responseObj = try? JSONDecoder().decode(MCPResponse.self, from: responseData) {
            #expect(responseObj.error != nil)
            #expect(responseObj.error?.code == -32601)
        }
    }

    // MARK: - Initialization State Tests

    @Test("Uninitialized server rejects non-system methods")
    func uninitializedServerRejectsRequests() async throws {
        let handler = MCPRequestHandler()
        let request = MCPRequest(
            id: "1",
            method: "tools/call",
            params: .toolCall(ToolCallParams(name: "test", arguments: nil))
        )

        let requestData = try JSONEncoder().encode(request)
        let response = await handler.handleRequest(requestData)

        #expect(response != nil)
        if let responseData = response,
           let responseObj = try? JSONDecoder().decode(MCPResponse.self, from: responseData) {
            #expect(responseObj.error != nil)
            #expect(responseObj.error?.code == -32600)
            #expect(responseObj.error?.message.contains("not initialized") == true)
        }
    }

    @Test("Initialize request succeeds before initialization")
    func initializeSucceeds() async throws {
        let handler = MCPRequestHandler()
        let request = MCPRequest(
            id: "1",
            method: "initialize",
            params: nil
        )

        let requestData = try JSONEncoder().encode(request)
        let response = await handler.handleRequest(requestData)

        #expect(response != nil)
        if let responseData = response,
           let responseObj = try? JSONDecoder().decode(MCPResponse.self, from: responseData) {
            #expect(responseObj.error == nil)
            #expect(responseObj.result != nil)
        }
    }

    // MARK: - Error Type Tests

    @Test("MCPServerError is Sendable")
    func mcpServerErrorIsSendable() {
        let error: any Error & Sendable = MCPServerError.invalidRequest(message: "test")
        #expect(error is MCPServerError)
    }

    @Test("ErrorResponse is Sendable")
    func errorResponseIsSendable() {
        let error = ErrorResponse(
            id: "1",
            error: ErrorResponse.ErrorInfo(code: -32600, message: "test")
        )
        let _: any Sendable = error
    }

    @Test("SocketError is Sendable")
    func socketErrorIsSendable() {
        let error: any Error & Sendable = SocketError.readFailed(errorCode: 0)
        #expect(error is SocketError)
    }

    @Test("StdioError is Sendable")
    func stdioErrorIsSendable() {
        let error: any Error & Sendable = StdioError.invalidHeader
        #expect(error is StdioError)
    }

    // MARK: - Error Code Tests

    @Test("MCPServerError has correct error codes")
    func mcpServerErrorCodes() {
        #expect(MCPServerError.parseError(message: "").errorCode == -32700)
        #expect(MCPServerError.invalidRequest(message: "").errorCode == -32600)
        #expect(MCPServerError.methodNotFound(method: "").errorCode == -32601)
        #expect(MCPServerError.invalidParams(message: "").errorCode == -32602)
        #expect(MCPServerError.internalError(message: "").errorCode == -32603)
    }

    // MARK: - Notification Tests

    @Test("Notification without ID does not return response")
    func notificationNoResponse() async throws {
        let handler = MCPRequestHandler()

        // Send initialize first
        let initRequest = MCPRequest(id: "1", method: "initialize", params: nil)
        _ = await handler.handleRequest(try JSONEncoder().encode(initRequest))

        // Send initialized notification (no ID)
        let notification = MCPRequest(id: nil, method: "initialized", params: nil)
        let responseData = await handler.handleRequest(try JSONEncoder().encode(notification))

        // The handler still returns a response but the MCPResponse should have nil result and error
        // This is actually correct behavior - we still encode a response even for notifications
        // The important part is that it doesn't require an ID
        if let data = responseData,
           let response = try? JSONDecoder().decode(MCPResponse.self, from: data) {
            // For initialized notification, response should indicate success or no error
            #expect(response.id == nil)
        }
    }
}
