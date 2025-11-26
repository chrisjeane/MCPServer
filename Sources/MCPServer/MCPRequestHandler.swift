import Foundation

public enum InitializationState {
    case uninitialized
    case initialized
}

/// Protocol for handling domain-specific MCP requests
public protocol MCPRequestHandlerDelegate: Sendable {
    /// Return custom server information
    func getServerInfo() -> ServerInfo

    /// Define available tools for this server
    func buildToolDefinitions() -> [Tool]

    /// Handle domain-specific methods after initialization
    func handleDomainSpecificRequest(_ request: MCPRequest) async throws -> MCPResponse?
}

/// Base class for handling MCP protocol requests
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

    private func extractIdFromData(_ data: Data) -> String? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return json["id"] as? String
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
        case "system.initialize":
            return await handleSystemInitialize(request)

        case "system.initialized":
            // Mark as initialized (notification - no response)
            initializationState = .initialized
            return nil  // Don't send response for notifications

        case "system.capabilities":
            return await handleSystemCapabilities(request)

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

    private func handleSystemInitialize(_ request: MCPRequest) async -> MCPResponse {
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
            id: request.id,
            result: .initialize(result),
            error: nil
        )
    }

    private func handleSystemCapabilities(_ request: MCPRequest) async -> MCPResponse {
        return MCPResponse(
            id: request.id,
            result: .success(SuccessResult(success: true)),
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
