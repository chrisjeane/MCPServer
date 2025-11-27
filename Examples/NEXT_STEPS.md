# DiceServer - Architectural Review & Next Steps

**Review Date**: November 26, 2025
**Project**: DiceServer - MCP (Model Context Protocol) Server
**Status**: Functional but requires critical fixes before production use

---

## Executive Summary

The DiceServer demonstrates solid understanding of MCP protocol and Swift concurrency fundamentals, with clean architectural separation. However, **four critical issues prevent functional use**:

1. Tool returns success but discards actual dice results
2. No input validation (crash/DoS vulnerability)
3. Incomplete TCP error handling (data loss risk)
4. Concurrency anti-pattern (resource exhaustion under load)

The codebase is excellent for educational purposes but needs hardening for any deployment.

---

## CRITICAL ISSUES - Must Fix Immediately

### 1. Missing Tool Response Results
**Location**: `DiceServer/main.swift:73-79`
**Severity**: CRITICAL - Tool is non-functional

The `handleToolCall` method computes dice results but returns only `{"success": true}` without the actual rolls:

```swift
let results = rollDice(count: count, sides: sides)  // Computed but discarded!

return MCPResponse(
    id: id,
    result: .success(SuccessResult(success: true)),  // Missing results
    error: nil
)
```

**Action Items**:
- [ ] Define proper response schema including roll results
- [ ] Modify response to include `results` array in the result object
- [ ] Test end-to-end that clients receive actual roll values
- [ ] Update README with expected response format

**Example Fix**:
```swift
// Ensure SuccessResult includes roll results
return MCPResponse(
    id: id,
    result: .success(SuccessResult(success: true, results: results)),  // Include results
    error: nil
)
```

---

### 2. No Input Validation
**Location**: `DiceServer/main.swift:69-73, 99-105`
**Severity**: CRITICAL - Crash/DoS vulnerability

The code accepts any integer input without validation:

```swift
let count = extractIntArgument(toolParams.arguments, key: "count") ?? 1
let sides = extractIntArgument(toolParams.arguments, key: "sides") ?? 6

// No validation before use
Int.random(in: 1...sides)  // Crashes if sides < 1
```

**Attack Vectors**:
- `sides: 0` or negative → Fatal error in range constructor
- `sides: Int.max` → Integer overflow issues
- `count: 1000000000` → Memory exhaustion
- `count: 0` or negative → Undefined behavior

**Action Items**:
- [ ] Add validation: `1 ≤ count ≤ 100`
- [ ] Add validation: `1 ≤ sides ≤ 10000`
- [ ] Return MCP error code -32602 for invalid params
- [ ] Write unit tests for all edge cases
- [ ] Document parameter constraints in tool definition

**Implementation**:
```swift
private func validateDiceParameters(_ count: Int, _ sides: Int) -> Bool {
    return count >= 1 && count <= 100 && sides >= 1 && sides <= 10000
}

// In handleToolCall:
let count = extractIntArgument(toolParams.arguments, key: "count") ?? 1
let sides = extractIntArgument(toolParams.arguments, key: "sides") ?? 6

guard validateDiceParameters(count, sides) else {
    return MCPResponse(
        id: id,
        result: nil,
        error: MCPError(code: -32602, message: "Invalid parameters: count must be 1-100, sides must be 1-10000")
    )
}
```

---

### 3. TCP Write Error Handling Incomplete
**Location**: `MCPServer/Sources/MCPServer/TCPServer.swift:336-361`
**Severity**: CRITICAL - Data loss and connection termination

The code treats `write() == 0` (should retry) the same as errors:

```swift
let written = data.withUnsafeBytes { buffer in
    write(socket, buffer.baseAddress! + bytesWritten, data.count - bytesWritten)
}

guard written > 0 else {
    throw SocketError.writeFailed  // Wrong! 0 means retry, <0 means error
}
```

**Issues**:
- No EINTR (interrupted system call) handling for writes
- `write() == 0` on non-blocking sockets should retry, not error
- `write() == -1` with EINTR should retry, not fail

**Action Items**:
- [ ] Implement write retry loop for EINTR
- [ ] Handle `write() == 0` by continuing the loop
- [ ] Check `errno == EINTR` for -1 returns
- [ ] Handle EAGAIN/EWOULDBLOCK for non-blocking sockets
- [ ] Write test cases for partial writes

**Implementation**:
```swift
private func writeData(_ data: Data, to socket: Int32) throws {
    var totalWritten = 0
    let bytes = [UInt8](data)

    while totalWritten < bytes.count {
        let result = write(socket, bytes + totalWritten, bytes.count - totalWritten)

        if result > 0 {
            totalWritten += result
        } else if result == 0 {
            // Shouldn't happen with blocking socket, but retry if it does
            continue
        } else if errno == EINTR {
            // Interrupted system call, retry
            continue
        } else {
            throw SocketError.writeFailed
        }
    }
}
```

---

### 4. TCP Connection Concurrency Anti-Pattern
**Location**: `MCPServer/Sources/MCPServer/TCPServer.swift:52-62`
**Severity**: CRITICAL - Thread exhaustion, resource leak

The code blocks a DispatchQueue thread on a semaphore while waiting for async Task:

```swift
DispatchQueue.global(qos: .userInitiated).async { [self] in
    let semaphore = DispatchSemaphore(value: 0)
    Task {
        await self.handleClient(socket: clientSocket)
        semaphore.signal()  // Signal when done
    }
    semaphore.wait()  // ⚠️ BLOCKS concurrent queue thread!
}
```

**Problems**:
1. Thread is blocked until Task completes (defeats async/await purpose)
2. Global queue can be starved under concurrent connections
3. No structured ownership of connection lifecycle
4. No graceful shutdown mechanism

**Impact**: With 100 concurrent connections, all 100 global queue threads are blocked.

**Action Items**:
- [ ] Replace DispatchQueue + semaphore with TaskGroup
- [ ] Use structured concurrency for connection lifetime
- [ ] Implement connection limit to prevent exhaustion
- [ ] Add graceful shutdown with connection draining
- [ ] Write concurrency stress tests

**Implementation**:
```swift
public func start() async throws {
    let serverSocket = try createServerSocket()
    defer { close(serverSocket) }

    try await withThrowingTaskGroup(of: Void.self) { group in
        // Limit concurrent connections
        let maxConnections = 100
        var activeConnections = 0

        while !Task.isCancelled {
            if activeConnections < maxConnections {
                let clientSocket = try acceptConnection(on: serverSocket)
                activeConnections += 1

                group.addTask { [self] in
                    defer { activeConnections -= 1 }
                    await self.handleClient(socket: clientSocket)
                }
            }
        }

        try await group.waitForAll()
    }
}
```

---

## HIGH PRIORITY - Production Readiness

### 5. Add Connection Limits
**Location**: `MCPServer/Sources/MCPServer/TCPServer.swift:43-69`
**Priority**: HIGH

Unbounded connection acceptance allows resource exhaustion attacks.

**Action Items**:
- [ ] Set max concurrent connections (recommend 100-500)
- [ ] Use TaskGroup bounded capacity or semaphore
- [ ] Return proper error when limit reached
- [ ] Add CLI arg `--max-connections` for configuration
- [ ] Log connection count metrics

**Rationale**: Prevents accidental or malicious resource exhaustion via connection flooding.

---

### 6. Implement Socket Lifecycle Management
**Location**: `MCPServer/Sources/MCPServer/TCPServer.swift:32-69`
**Priority**: HIGH

Server socket is never closed and client connections don't shutdown gracefully.

**Action Items**:
- [ ] Add `defer { close(serverSocket) }` in `start()` method
- [ ] Call `shutdown(socket, SHUT_RDWR)` before `close()` in handleClient
- [ ] Handle cleanup on server shutdown signal (SIGINT/SIGTERM)
- [ ] Write cleanup tests to verify no fd leaks

**Example**:
```swift
defer {
    shutdown(clientSocket, SHUT_RDWR)  // Graceful termination
    close(clientSocket)
}
```

---

### 7. Complete EINTR Handling for All Socket Operations
**Location**: `MCPServer/Sources/MCPServer/TCPServer.swift:282-312`
**Priority**: HIGH

Read operations lack EINTR handling; write operations already lack it (see Critical Issue #3).

**Action Items**:
- [ ] Add EINTR retry for read operations
- [ ] Add EINTR retry for write operations (covered in Critical #3)
- [ ] Capture errno immediately after syscalls
- [ ] Document EINTR handling in comments
- [ ] Test with signal interruption scenarios

---

### 8. Add Socket Timeouts
**Location**: `MCPServer/Sources/MCPServer/TCPServer.swift`
**Priority**: HIGH

Unbounded socket I/O allows slow clients to hang connections indefinitely.

**Action Items**:
- [ ] Set `SO_RCVTIMEO` socket option (recommend 30s)
- [ ] Set `SO_SNDTIMEO` socket option (recommend 10s)
- [ ] Make timeouts configurable via CLI args
- [ ] Document timeout behavior
- [ ] Test timeout handling with slow client

**Example**:
```swift
var timeout = timeval(tv_sec: 30, tv_usec: 0)
setsockopt(socket, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
```

---

### 9. Optimize MCPRequestHandler Actor Isolation
**Location**: `MCPServer/Sources/MCPServer/MCPRequestHandler.swift:35-50`
**Priority**: MEDIUM (performance)

All request handling serializes through actor, but encoding/decoding is pure computation.

**Action Items**:
- [ ] Mark encoding/decoding operations as `nonisolated`
- [ ] Only serialize access to `initializationState`
- [ ] Benchmark request throughput before/after
- [ ] Profile to verify actor contention reduced

**Expected Impact**: 10-30% improvement in request throughput.

---

## MEDIUM PRIORITY - Code Quality

### 10. Remove or Gate Debug Logging
**Location**: `MCPServer/Sources/MCPServer/TCPServer.swift:45-66`
**Priority**: MEDIUM

Hardcoded `DEBUG:` logs to stderr are noisy in production.

**Action Items**:
- [ ] Remove hardcoded logs or gate behind `verbose` flag
- [ ] Implement structured logging with log levels
- [ ] Use os.Logger or swift-log for consistency
- [ ] Add request tracing with request IDs

---

### 11. Adopt ArgumentParser for CLI
**Location**: `DiceServer/main.swift:116-164`
**Priority**: MEDIUM

Manual argument parsing is verbose and error-prone.

**Action Items**:
- [ ] Add `swift-argument-parser` dependency
- [ ] Define command structure with `ParsableCommand`
- [ ] Use property wrappers for arguments/options
- [ ] Get automatic help and validation
- [ ] Update README with generated help output

---

### 12. Convert DiceServerDelegate to Struct
**Location**: `DiceServer/main.swift:6`
**Priority**: LOW

Stateless class should be a struct for clarity and minor performance gain.

**Action Items**:
- [ ] Change `final class DiceServerDelegate` to `struct`
- [ ] Verify Sendable conformance
- [ ] Benchmark memory usage

---

### 13. Add Comprehensive Test Suite
**Location**: New files to create
**Priority**: MEDIUM

No tests exist for critical functionality.

**Action Items**:
- [ ] Add unit tests for input validation
- [ ] Add unit tests for dice rolling randomness
- [ ] Add integration tests for MCP protocol flows
- [ ] Add concurrency tests (multiple connections)
- [ ] Add stress tests (connection limits, timeouts)
- [ ] Aim for 80%+ code coverage

---

### 14. Implement Graceful Shutdown
**Location**: `MCPServer/Sources/MCPServer/TCPServer.swift`
**Priority**: MEDIUM

Server has no shutdown mechanism for clean resource cleanup.

**Action Items**:
- [ ] Capture SIGINT/SIGTERM signals
- [ ] Stop accepting new connections
- [ ] Drain active connections with timeout
- [ ] Close server socket cleanly
- [ ] Log shutdown progress

---

## LOW PRIORITY - Nice to Have

### 15. Implement Structured Logging
- Use `os.Logger` or `swift-log` for consistency
- Add request IDs for end-to-end tracing
- Log key metrics (latency, errors, connection count)

### 16. Add Observability/Metrics
- Connection count gauge
- Request latency histogram
- Error rate counter
- Export via `/metrics` endpoint or StatsD

### 17. Document Concurrency Model
- Add comments explaining actor isolation
- Document thread-safety guarantees
- Explain transport lifecycle and cleanup

### 18. Add Configuration File Support
- Support `.json` or `.toml` config files
- Override with command-line arguments
- Environment variable support

### 19. Implement Health Check Endpoint
- Add `/health` HTTP endpoint
- Return server status and stats
- Enable load balancer integration

### 20. Add Request Rate Limiting
- Per-connection request rate limits
- Token bucket or sliding window algorithm
- Prevent abuse scenarios

---

## Strengths of Current Implementation

✅ **Clean Protocol Separation**: `MCPRequestHandlerDelegate` provides excellent abstraction
✅ **Transport Abstraction**: Modular design for stdio and HTTP transports
✅ **Content-Length Framing**: Correctly implements MCP framing protocol
✅ **JSON-RPC 2.0 Compliance**: Proper id handling and error codes
✅ **Sendable Conformance**: Safe concurrent usage across threads
✅ **Actor Isolation**: Thread-safe state management for initialization
✅ **EINTR Handling (Partial)**: Stdio transport handles interrupts correctly
✅ **SO_REUSEADDR Enabled**: Avoids bind errors on rapid restarts
✅ **Type-Safe Parameters**: `AnyCodable` avoids fragile dictionaries

---

## Implementation Timeline Recommendation

### Phase 1: Critical Fixes (1-2 days)
1. Fix tool response to include results
2. Add input validation
3. Fix TCP write error handling
4. Refactor connection concurrency

**Blocking**: Do not use in any capacity until these are complete.

### Phase 2: Production Hardening (3-5 days)
5. Add connection limits
6. Implement socket lifecycle management
7. Complete EINTR handling
8. Add socket timeouts
9. Optimize actor isolation

**Outcome**: Safe for development/testing use.

### Phase 3: Quality & Testing (1 week)
10. Remove debug logging
11. Adopt ArgumentParser
12. Write comprehensive tests
13. Implement graceful shutdown
14. Review error handling

**Outcome**: Production-ready code.

### Phase 4: Operations (Optional)
15-20. Add logging, metrics, observability

**Outcome**: Production-deployable service.

---

## Testing Checklist

- [ ] Tool returns actual dice results to client
- [ ] Invalid parameters (count=1000000, sides=0) are rejected with proper error
- [ ] 100 concurrent connections succeed with reasonable latency
- [ ] Slow client (10-second silent read) times out gracefully
- [ ] Server socket closes cleanly on shutdown
- [ ] No file descriptor leaks (check with `lsof`)
- [ ] SIGINT (Ctrl+C) drains connections and exits cleanly
- [ ] All EINTR scenarios tested (send SIGALRM during I/O)
- [ ] Read and write timeouts trigger properly
- [ ] Debug logging is quiet in production mode

---

## References

- [MCP Specification](https://modelcontextprotocol.io/)
- [Swift Concurrency Guide](https://developer.apple.com/documentation/swift/concurrency)
- [POSIX Signal Safety](https://man7.org/linux/man-pages/man7/signal-safety.7.html)
- [EINTR Handling Best Practices](https://man7.org/linux/man-pages/man2/write.2.html)
- [Swift Argument Parser](https://github.com/apple/swift-argument-parser)

---

**Document Version**: 1.0
**Last Updated**: November 26, 2025
**Status**: Ready for Implementation
