import Foundation

public enum MCPServerError: Error {
    case invalidRequest(message: String)
    case methodNotFound(method: String)
    case invalidParams(message: String)
    case internalError(message: String)
    case parseError(message: String)

    public var errorCode: Int {
        switch self {
        case .parseError:
            return -32700
        case .invalidRequest:
            return -32600
        case .methodNotFound:
            return -32601
        case .invalidParams:
            return -32602
        case .internalError:
            return -32603
        }
    }

    public var errorMessage: String {
        switch self {
        case .parseError(let msg):
            return "Parse error: \(msg)"
        case .invalidRequest(let msg):
            return "Invalid request: \(msg)"
        case .methodNotFound(let method):
            return "Method not found: \(method)"
        case .invalidParams(let msg):
            return "Invalid params: \(msg)"
        case .internalError(let msg):
            return "Internal error: \(msg)"
        }
    }
}

public struct ErrorResponse: Codable {
    public let jsonrpc: String
    public let id: String
    public let error: ErrorInfo

    enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case error
    }

    public init(id: String, error: ErrorInfo) {
        self.jsonrpc = "2.0"
        self.id = id
        self.error = error
    }

    public struct ErrorInfo: Codable {
        public let code: Int
        public let message: String
        public let data: String?

        public init(code: Int, message: String, data: String? = nil) {
            self.code = code
            self.message = message
            self.data = data
        }
    }
}
