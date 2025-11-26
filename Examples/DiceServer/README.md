# Dice Server

A simple MCP (Model Context Protocol) server example that provides a dice rolling tool. This example demonstrates how to:

- Implement a custom MCP server delegate
- Define and expose tools through the MCP protocol
- Support multiple transport mechanisms (stdio and HTTP)
- Handle tool calls with parameters

## Features

- **roll_dice tool**: Roll one or more dice with configurable sides
  - `count`: Number of dice to roll (default: 1)
  - `sides`: Number of sides on each die (default: 6)

## Building

```bash
swift build -c release
```

The binary will be located at `.build/release/dice-server`.

## Running

### Default (Stdio Transport)

```bash
.build/release/dice-server
```

### HTTP Transport

```bash
.build/release/dice-server --transport http --port 8080
```

#### Options

- `--transport <type>`: Choose transport type - `stdio` (default) or `http`
- `--host <address>`: Host address for HTTP transport (default: 127.0.0.1)
- `--port <number>`: Port number for HTTP transport (default: 3000)
- `--help, -h`: Display help information

## Testing with HTTP Transport

The Dice Server communicates using the MCP protocol with Content-Length framing. Follow these steps to test:

### Step-by-Step Test Commands

**Start the server:**
```bash
/Users/chris/Code/MCP/MCPServer/.build/release/dice-server --transport http --port 8080 &
sleep 2
```

**Step 1: Initialize the server**
```bash
INIT='{"jsonrpc":"2.0","id":"1","method":"initialize","params":{}}'
echo -e "Content-Length: $(echo -n "$INIT" | wc -c)\r\n\r\n$INIT" | nc localhost 8080
```

Expected response:
```json
{"jsonrpc":"2.0","id":"1","result":{"protocolVersion":"2024-11-05","capabilities":{"logging":{},"tools":{"listChanged":false}},"serverInfo":{"name":"Dice Server","version":"1.0.0"}}}
```

**Step 2: Send initialized notification** (Required - no ID, server won't respond)
```bash
NOTIF='{"jsonrpc":"2.0","method":"initialized","params":{}}'
echo -e "Content-Length: $(echo -n "$NOTIF" | wc -c)\r\n\r\n$NOTIF" | nc localhost 8080
```

**Step 3: List available tools**
```bash
TOOLS='{"jsonrpc":"2.0","id":"2","method":"tools/list","params":{}}'
echo -e "Content-Length: $(echo -n "$TOOLS" | wc -c)\r\n\r\n$TOOLS" | nc localhost 8080
```

**Step 4: Roll dice (default 1d6)**
```bash
ROLL='{"jsonrpc":"2.0","id":"3","method":"tools/call","params":{"name":"roll_dice"}}'
echo -e "Content-Length: $(echo -n "$ROLL" | wc -c)\r\n\r\n$ROLL" | nc localhost 8080
```

Expected response:
```json
{"jsonrpc":"2.0","result":{"success":true},"id":"3"}
```

**Step 5: Roll dice with custom parameters (e.g., 3d20)**
```bash
ROLL='{"jsonrpc":"2.0","id":"4","method":"tools/call","params":{"name":"roll_dice","arguments":{"count":3,"sides":20}}}'
echo -e "Content-Length: $(echo -n "$ROLL" | wc -c)\r\n\r\n$ROLL" | nc localhost 8080
```

### Complete Test Script

Copy and paste this entire script to run all tests:

```bash
#!/bin/bash

# Start server
/Users/chris/Code/MCP/MCPServer/.build/release/dice-server --transport http --port 8080 &
SERVER_PID=$!
sleep 2

echo "=== Step 1: Initialize ==="
INIT='{"jsonrpc":"2.0","id":"1","method":"initialize","params":{}}'
echo -e "Content-Length: $(echo -n "$INIT" | wc -c)\r\n\r\n$INIT" | nc localhost 8080
sleep 1

echo ""
echo "=== Step 2: Send initialized notification ==="
NOTIF='{"jsonrpc":"2.0","method":"initialized","params":{}}'
echo -e "Content-Length: $(echo -n "$NOTIF" | wc -c)\r\n\r\n$NOTIF" | nc localhost 8080
sleep 1

echo ""
echo "=== Step 3: List tools ==="
TOOLS='{"jsonrpc":"2.0","id":"2","method":"tools/list","params":{}}'
echo -e "Content-Length: $(echo -n "$TOOLS" | wc -c)\r\n\r\n$TOOLS" | nc localhost 8080
sleep 1

echo ""
echo "=== Step 4: Roll Dice (1d6) ==="
ROLL='{"jsonrpc":"2.0","id":"3","method":"tools/call","params":{"name":"roll_dice"}}'
echo -e "Content-Length: $(echo -n "$ROLL" | wc -c)\r\n\r\n$ROLL" | nc localhost 8080
sleep 1

echo ""
echo "=== Step 5: Roll Dice (3d20) ==="
ROLL='{"jsonrpc":"2.0","id":"4","method":"tools/call","params":{"name":"roll_dice","arguments":{"count":3,"sides":20}}}'
echo -e "Content-Length: $(echo -n "$ROLL" | wc -c)\r\n\r\n$ROLL" | nc localhost 8080

# Cleanup
kill $SERVER_PID 2>/dev/null || true
```

## MCP Protocol Notes

The Dice Server uses the MCP (Model Context Protocol) which requires:

1. **Initialization Handshake**: Client must send `initialize` request first
2. **Initialization Notification**: Client must send `initialized` notification before calling tools
3. **Content-Length Framing**: All messages use `Content-Length: {N}\r\n\r\n{payload}` format
4. **JSON-RPC 2.0**: Messages follow JSON-RPC 2.0 specification

## Implementation Details

- `DiceServerDelegate`: Implements the MCP request handler delegate
- `rollDice()`: Generates random dice rolls
- Supports both stdio (for stdin/stdout) and HTTP (TCP socket) transports
