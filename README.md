# MCPServer

A Swift library for building Model Context Protocol (MCP) servers. This library provides the core MCP protocol handling, transport layers, and request handling infrastructure.

## Features

- **MCP Protocol Implementation**: Full support for JSON-RPC 2.0 based MCP protocol
- **Multiple Transports**: Built-in support for TCP and Stdio transports
- **Extensible Design**: Delegate pattern for implementing domain-specific functionality
- **Type-Safe**: Strongly typed message handling with Codable support

## Components

### Core Protocol
- **MCPMessages.swift**: Protocol definitions and types
  - `MCPRequest`: JSON-RPC request structure
  - `MCPResponse`: JSON-RPC response structure
  - `MCPParams`: Parameter enumeration for various methods
  - `MCPResult`: Result enumeration for responses
  - Tool definitions and capabilities

### Request Handling
- **MCPRequestHandler**: Base actor for processing MCP requests
  - Handles system protocol methods (initialize, capabilities, tools/list)
  - Delegates domain-specific requests to a handler implementation
  - Manages initialization state and error handling

### Transport Layers
- **TCPServer.swift**: TCP socket-based transport
  - Implements MCP message framing with Content-Length headers
  - Handles multiple concurrent client connections
  - Cross-platform socket support

- **StdioTransport.swift**: Standard input/output transport
  - Implements MCP message framing on stdin/stdout
  - Suitable for tool integration and CLI usage

### Error Handling
- **Errors.swift**: MCP error types with JSON-RPC error codes

## Usage

To build an MCP server, implement the `MCPRequestHandlerDelegate` protocol:

```swift
import MCPServer

struct MyServerDelegate: MCPRequestHandlerDelegate {
    func getServerInfo() -> ServerInfo {
        return ServerInfo(name: "MyServer", version: "1.0.0")
    }

    func buildToolDefinitions() -> [Tool] {
        // Define your tools here
        return []
    }

    func handleDomainSpecificRequest(_ request: MCPRequest) async throws -> MCPResponse? {
        // Handle your domain-specific methods
        return nil
    }
}

// Create and run the server
let delegate = MyServerDelegate()
let handler = MCPRequestHandler(delegate: delegate)
let transport = StdioTransport(handler: handler)
try await transport.start()
```

## Requirements

- Swift 6.2 or later
- macOS 15 or later

## License

[Your License Here]
