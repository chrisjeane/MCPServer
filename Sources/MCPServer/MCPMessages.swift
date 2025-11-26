import Foundation

// MARK: - Log Level Enum

public enum LogLevel: String, Codable, Sendable {
    case trace = "TRACE"
    case debug = "DEBUG"
    case info = "INFO"
    case warn = "WARN"
    case error = "ERROR"
    case fatal = "FATAL"

    public var sortOrder: Int {
        switch self {
        case .trace: return 0
        case .debug: return 1
        case .info: return 2
        case .warn: return 3
        case .error: return 4
        case .fatal: return 5
        }
    }
}

// MARK: - MCP Protocol Constants

public let MCP_PROTOCOL_VERSION = "2024-11-05"

// MARK: - MCP Capabilities

public struct MCPCapabilities: Codable, Sendable {
    public struct Logging: Codable, Sendable {
        public init() {}
    }

    public struct Tools: Codable, Sendable {
        public let listChanged: Bool

        public init(listChanged: Bool = false) {
            self.listChanged = listChanged
        }
    }

    public let logging: Logging?
    public let tools: Tools?

    public init(logging: Logging? = nil, tools: Tools? = nil) {
        self.logging = logging
        self.tools = tools
    }
}

// MARK: - Server Info

public struct ServerInfo: Codable, Sendable {
    public let name: String
    public let version: String

    public init(name: String = "MCPServer", version: String = "1.0.0") {
        self.name = name
        self.version = version
    }
}

// MARK: - Tool Definitions

public struct Tool: Codable, Sendable {
    public let name: String
    public let description: String
    public let inputSchema: ToolInputSchema

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
    }

    public init(name: String, description: String, inputSchema: ToolInputSchema) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

public struct ToolInputSchema: Codable, Sendable {
    public let type: String
    public let properties: [String: PropertySchema]
    public let required: [String]

    public init(type: String = "object", properties: [String: PropertySchema], required: [String]) {
        self.type = type
        self.properties = properties
        self.required = required
    }
}

public struct PropertySchema: Codable, Sendable {
    public let type: String
    public let description: String
    public let `enum`: [String]?

    public init(type: String, description: String, enum: [String]? = nil) {
        self.type = type
        self.description = description
        self.`enum` = `enum`
    }
}

public struct ToolsListResult: Codable, Sendable {
    public let tools: [Tool]

    public init(tools: [Tool]) {
        self.tools = tools
    }
}

// MARK: - Protocol Messages

public struct MCPRequest: Codable, Sendable {
    public let jsonrpc: String = "2.0"
    public let id: String?  // Optional for notifications (system.initialized), stored as string
    public let method: String
    public let params: MCPParams?

    public enum CodingKeys: String, CodingKey, Sendable {
        case jsonrpc
        case id
        case method
        case params
    }

    public init(jsonrpc: String = "2.0", id: String?, method: String, params: MCPParams?) {
        self.id = id
        self.method = method
        self.params = params
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Handle id as any JSON type (string, number, or null) per JSON-RPC 2.0 spec
        var id: String? = nil
        if container.contains(.id) {
            // Try decoding as string first
            if let stringId = try? container.decodeIfPresent(String.self, forKey: .id) ?? nil {
                id = stringId
            } else if let intId = try? container.decodeIfPresent(Int.self, forKey: .id) ?? nil {
                id = String(intId)
            } else if let doubleId = try? container.decodeIfPresent(Double.self, forKey: .id) ?? nil {
                id = String(Int(doubleId))
            }
            // If id exists but is null, id remains nil
        }
        self.id = id
        self.method = try container.decode(String.self, forKey: .method)

        if container.contains(.params) {
            let paramsDecoder = try container.superDecoder(forKey: .params)
            self.params = try MCPParams(from: paramsDecoder, method: self.method)
        } else {
            self.params = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("2.0", forKey: .jsonrpc)
        try container.encodeIfPresent(id, forKey: .id)  // Encode if present
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(params, forKey: .params)
    }
}

public enum MCPParams: Codable, Sendable {
    case none  // For methods that don't require params (system.*, tools/list, etc)

    // Log4-specific cases
    case logMessage(LogMessageParams)
    case getEntries(GetEntriesParams)
    case clearLogs(ClearLogsParams)
    case setLogLevel(SetLogLevelParams)

    // Required for Codable protocol - this will be overridden by MCPRequest
    public init(from decoder: Decoder) throws {
        // This should not be used directly - MCPRequest uses init(from:method:)
        self = .none
    }

    public init(from decoder: Decoder, method: String) throws {
        switch method {
        case "log.message":
            let params = try LogMessageParams(from: decoder)
            self = .logMessage(params)
        case "log.getEntries":
            let params = try GetEntriesParams(from: decoder)
            self = .getEntries(params)
        case "log.setLevel":
            let params = try SetLogLevelParams(from: decoder)
            self = .setLogLevel(params)
        case "log.clear":
            let params = try ClearLogsParams(from: decoder)
            self = .clearLogs(params)
        case "initialize", "initialized", "tools/list":
            // These methods don't require params
            self = .none
        default:
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown method type for params: \(method)"
                )
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .logMessage(let params):
            try params.encode(to: encoder)
        case .getEntries(let params):
            try params.encode(to: encoder)
        case .clearLogs(let params):
            try params.encode(to: encoder)
        case .setLogLevel(let params):
            try params.encode(to: encoder)
        case .none:
            // No params to encode
            break
        }
    }

    public enum CodingKeys: String, CodingKey, Sendable {
        case message
        case loggerId
        case level
    }
}

// MARK: - Log4-Specific MCP Parameters

// Forward declarations - these types are protocol-compatible
// LogLevel and LogEntry are defined in Log4MCPLib/Logger.swift

public struct LogMessageParams: Codable, Sendable {
    public let loggerId: String
    public let level: LogLevel
    public let message: String

    public init(loggerId: String, level: LogLevel, message: String) {
        self.loggerId = loggerId
        self.level = level
        self.message = message
    }
}

public struct GetEntriesParams: Codable, Sendable {
    public let loggerId: String
    public let level: LogLevel?

    public init(loggerId: String, level: LogLevel? = nil) {
        self.loggerId = loggerId
        self.level = level
    }
}

public struct ClearLogsParams: Codable, Sendable {
    public let loggerId: String

    public init(loggerId: String) {
        self.loggerId = loggerId
    }
}

public struct SetLogLevelParams: Codable, Sendable {
    public let loggerId: String
    public let level: LogLevel

    public init(loggerId: String, level: LogLevel) {
        self.loggerId = loggerId
        self.level = level
    }
}

public struct MCPResponse: Codable, Sendable {
    public let jsonrpc: String
    public let id: String?  // Optional for notifications
    public let result: MCPResult?
    public let error: MCPError?

    public enum CodingKeys: String, CodingKey, Sendable {
        case jsonrpc
        case id
        case result
        case error
    }

    public init(id: String?, result: MCPResult?, error: MCPError?) {
        self.jsonrpc = "2.0"
        self.id = id
        self.result = result
        self.error = error
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        jsonrpc = try container.decode(String.self, forKey: .jsonrpc)

        // Handle id as any JSON type (string, number, or null)
        var id: String? = nil
        if container.contains(.id) {
            if let stringId = try? container.decodeIfPresent(String.self, forKey: .id) ?? nil {
                id = stringId
            } else if let intId = try? container.decodeIfPresent(Int.self, forKey: .id) ?? nil {
                id = String(intId)
            } else if let doubleId = try? container.decodeIfPresent(Double.self, forKey: .id) ?? nil {
                id = String(Int(doubleId))
            }
        }
        self.id = id

        result = try container.decodeIfPresent(MCPResult.self, forKey: .result)
        error = try container.decodeIfPresent(MCPError.self, forKey: .error)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encodeIfPresent(result, forKey: .result)
        try container.encodeIfPresent(error, forKey: .error)
    }
}

public enum MCPResult: Codable, Sendable {
    case success(SuccessResult)
    case initialize(InitializeResult)
    case toolsList(ToolsListResult)

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if container.contains(.protocolVersion) {
            let result = try InitializeResult(from: decoder)
            self = .initialize(result)
        } else if container.contains(.tools) {
            let result = try ToolsListResult(from: decoder)
            self = .toolsList(result)
        } else {
            let result = try SuccessResult(from: decoder)
            self = .success(result)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .success(let result):
            try result.encode(to: encoder)
        case .initialize(let result):
            try result.encode(to: encoder)
        case .toolsList(let result):
            try result.encode(to: encoder)
        }
    }

    public enum CodingKeys: String, CodingKey, Sendable {
        case success
        case protocolVersion
        case capabilities
        case serverInfo
        case tools
    }
}

public struct InitializeResult: Codable, Sendable {
    public let protocolVersion: String
    public let capabilities: MCPCapabilities
    public let serverInfo: ServerInfo

    public init(protocolVersion: String, capabilities: MCPCapabilities, serverInfo: ServerInfo) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.serverInfo = serverInfo
    }
}

public struct SuccessResult: Codable, Sendable {
    public let success: Bool

    public init(success: Bool) {
        self.success = success
    }
}

public struct MCPError: Codable, Sendable {
    public let code: Int
    public let message: String

    public init(code: Int, message: String) {
        self.code = code
        self.message = message
    }
}
