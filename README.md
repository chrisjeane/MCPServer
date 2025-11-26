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

## Setup and Installation

### Prerequisites

- Swift 6.2 or later
- macOS 15 or later
- Xcode 16 or later (for development)

### Building the Library

To build the MCPServer library:

```bash
cd MCPServer
swift build
```

To build a specific example (e.g., DiceServer):

```bash
swift build --product DiceServer
```

## Running with Claude MCP

Claude CLI integrates with MCP servers to extend its capabilities. Here's how to use MCPServer with `claude mcp`:

### 1. Build Your MCP Server

First, build your MCP server executable:

```bash
swift build -c release
```

The executable will be located at `.build/release/YourServerName`.

### 2. Configure Claude CLI

Add your MCP server to Claude's configuration file at `~/.claude/mcp-servers.json`:

```json
{
  "mcpServers": {
    "dice": {
      "command": "/path/to/.build/release/DiceServer"
    }
  }
}
```

Replace `/path/to/.build/release/DiceServer` with the full path to your built executable.

### 3. Run Claude with MCP Server

Start Claude CLI with your MCP server:

```bash
claude mcp start
```

This will start the Claude CLI with your configured MCP servers loaded. You can then interact with Claude and use the tools provided by your MCP server.

### 4. Using Tools in Claude

Once your MCP server is running, you can ask Claude to use its tools:

```
> roll_dice sides:6
```

Claude will route tool calls to your MCP server and return the results.

## Requirements

- Swift 6.2 or later
- macOS 15 or later

## License

[Your License Here]
