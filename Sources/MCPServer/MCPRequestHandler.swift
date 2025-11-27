import Foundation

/// Represents the initialization state of the MCP server.
public enum InitializationState: Sendable {
    case uninitialized
    case initialized
}

/// Protocol for handling domain-specific MCP requests.
/// Implement this protocol to provide custom server functionality.
public protocol MCPRequestHandlerDelegate: Sendable {
    /// Return custom server information displayed during initialization.
    func getServerInfo() -> ServerInfo

    /// Define available tools for this server.
    /// Called during tools/list requests.
    func buildToolDefinitions() -> [Tool]

    /// Handle domain-specific methods after initialization.
    /// Return nil for notifications (no response expected).
    func handleDomainSpecificRequest(_ request: MCPRequest) async throws -> MCPResponse?
}

/// Actor-based handler for MCP protocol requests.
/// Provides thread-safe request processing with proper initialization sequencing.
public actor MCPRequestHandler {
    private var initializationState: InitializationState = .uninitialized
    nonisolated let encoder: JSONEncoder
    nonisolated let decoder: JSONDecoder
    nonisolated let delegate: MCPRequestHandlerDelegate?

    public init(delegate: MCPRequestHandlerDelegate? = nil) {
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.delegate = delegate
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    /// Handles a raw request data and returns response data.
    /// Returns nil for notifications or on unrecoverable errors.
    public func handleRequest(_ requestData: Data) async -> Data? {
        do {
            let request = try decoder.decode(MCPRequest.self, from: requestData)
            let response = try await processRequest(request)

            let responseData = try encoder.encode(response)
            return responseData
        } catch {
            let id = extractIdFromData(requestData) ?? "unknown"
            return try? encodeErrorResponse(
                id: id,
                code: -32700,
                message: "Parse error: \(error.localizedDescription)"
            )
        }
    }

    /// Extracts the request ID from raw JSON data using Codable.
    /// This is more efficient and type-safe than JSONSerialization.
    private func extractIdFromData(_ data: Data) -> String? {
        // Define a minimal struct to extract just the ID field
        struct RequestID: Codable {
            let id: String?
        }

        guard let requestID = try? decoder.decode(RequestID.self, from: data) else {
            return nil
        }
        return requestID.id
    }

    public func handleRequest(_ requestString: String) async -> String? {
        guard let requestData = requestString.data(using: .utf8) else {
            return nil
        }

        guard let responseData = await handleRequest(requestData) else {
            return nil
        }

        return String(data: responseData, encoding: .utf8)
    }

    private func processRequest(_ request: MCPRequest) async throws -> MCPResponse? {
        // System protocol methods don't require initialization
        switch request.method {
        case "initialize":
            return await handleSystemInitialize(request)

        case "initialized":
            // Mark as initialized (notification - no response)
            initializationState = .initialized
            return nil  // Don't send response for notifications

        case "tools/list":
            return await handleToolsList(request)

        default:
            break
        }

        // All other methods require initialization
        guard case .initialized = initializationState else {
            guard let id = request.id else {
                return nil  // Don't respond to uninitialized notifications
            }
            return MCPResponse(
                id: id,
                result: nil,
                error: MCPError(code: -32600, message: "Invalid Request: server not initialized")
            )
        }

        // Delegate domain-specific method handling to delegate
        if let delegate = delegate {
            return try await delegate.handleDomainSpecificRequest(request)
        }

        // Default: method not found
        guard let id = request.id else {
            return nil  // Don't respond to unknown notifications
        }
        return MCPResponse(
            id: id,
            result: nil,
            error: MCPError(code: -32601, message: "Method not found: \(request.method)")
        )
    }

    // MARK: - System Protocol Methods

    /// Handles the initialize request with proper validation.
    /// The initialize request should include client capabilities and protocol version.
    private func handleSystemInitialize(_ request: MCPRequest) async -> MCPResponse {
        // Validate that we have a request ID (initialize is not a notification)
        guard let id = request.id else {
            // This shouldn't happen for initialize, but handle gracefully
            return MCPResponse(
                id: "unknown",
                result: nil,
                error: MCPError(code: -32600, message: "Invalid Request: initialize must have an ID")
            )
        }

        // Build server capabilities
        let capabilities = MCPCapabilities(
            logging: MCPCapabilities.Logging(),
            tools: MCPCapabilities.Tools(listChanged: false)
        )
        let serverInfo = delegate?.getServerInfo() ?? ServerInfo()
        let result = InitializeResult(
            protocolVersion: MCP_PROTOCOL_VERSION,
            capabilities: capabilities,
            serverInfo: serverInfo
        )

        return MCPResponse(
            id: id,
            result: .initialize(result),
            error: nil
        )
    }

    private func handleToolsList(_ request: MCPRequest) async -> MCPResponse {
        let tools = delegate?.buildToolDefinitions() ?? []
        let result = ToolsListResult(tools: tools)

        return MCPResponse(
            id: request.id,
            result: .toolsList(result),
            error: nil
        )
    }

    nonisolated private func encodeErrorResponse(id: String, code: Int, message: String) throws -> Data {
        let response = MCPResponse(
            id: id,
            result: nil,
            error: MCPError(code: code, message: message)
        )
        return try encoder.encode(response)
    }
}
