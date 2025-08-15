# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a macOS menu bar application that acts as an OIDC-authenticated proxy for LiteLLM endpoints. It intercepts HTTP requests, adds OIDC authentication tokens, and forwards them to a configured LiteLLM server.

## Build and Development Commands

### Building the Project
```bash
# Build using Xcode (GUI)
# Open litellm-oidc-proxy.xcodeproj in Xcode and press Cmd+B

# Build from command line
xcodebuild -project litellm-oidc-proxy.xcodeproj -scheme litellm-oidc-proxy -configuration Debug build

# Build for release
xcodebuild -project litellm-oidc-proxy.xcodeproj -scheme litellm-oidc-proxy -configuration Release build
```

### Running Tests
```bash
# Run unit tests
xcodebuild test -project litellm-oidc-proxy.xcodeproj -scheme litellm-oidc-proxy -destination 'platform=macOS'

# Test the proxy endpoints
./test-proxy.sh
./test-streaming.sh
```

### Running the Application
The application is a macOS menu bar app. After building:
1. Run from Xcode with Cmd+R
2. Or double-click the built .app file in the build directory

## Architecture

### Core Components

1. **HTTPServer** (`HTTPServer.swift`): 
   - Network listener that intercepts requests on the configured port
   - Handles token caching and automatic renewal
   - Supports both streaming and non-streaming endpoints
   - Forwards authenticated requests to LiteLLM

2. **OIDCClient** (`OIDCClient.swift`):
   - Manages OIDC authentication with Keycloak
   - Handles token acquisition and validation
   - Tests LiteLLM endpoint connectivity

3. **AppDelegate** (`litellm_oidc_proxyApp.swift`):
   - Menu bar integration and UI lifecycle
   - Auto-start functionality
   - Status icon management

4. **Settings Management** (`Settings.swift`):
   - UserDefaults for non-sensitive data
   - Keychain integration for client secrets
   - Configuration validation

5. **Database Layer** (`DatabaseManager.swift`):
   - SQLite-based request logging
   - Request/response history tracking

### Request Flow

1. Client sends request to `localhost:9000` (configurable)
2. HTTPServer intercepts the request
3. OIDCClient obtains/refreshes authentication token
4. Request is forwarded to LiteLLM with Bearer token
5. Response is streamed back to client
6. Request/response logged to SQLite database

### Supported Endpoints

The proxy supports all LiteLLM endpoints, including:
- `/v1/chat/completions` (OpenAI-compatible)
- `/v1/messages` (Anthropic-compatible)
- `/v1/models` (model listing)
- Both streaming and non-streaming requests

Additionally, the proxy provides a management endpoint:
- `/proxy/query` - SQL query interface for request logs (POST only)

### Key Features

- **Token Caching**: Tokens are cached and refreshed 1 minute before expiry
- **Auto-start**: Configurable automatic proxy startup on app launch
- **Request Logging**: All requests/responses stored in SQLite with viewer UI
- **Launch at Login**: macOS login item integration
- **Streaming Support**: Proper handling of SSE streams
- **SQL Query API**: Query request logs programmatically via HTTP

### SQL Query Endpoint

The proxy exposes a `/proxy/query` endpoint for querying request logs:

```bash
# Example: Get request counts by model
curl -X POST http://localhost:9000/proxy/query \
  -H "Content-Type: application/json" \
  -d '{
    "sql": "SELECT model, COUNT(*) as count FROM request_logs GROUP BY model"
  }'

# Example: Get recent errors
curl -X POST http://localhost:9000/proxy/query \
  -H "Content-Type: application/json" \
  -d '{
    "sql": "SELECT timestamp, path, response_status FROM request_logs WHERE response_status >= 400 ORDER BY timestamp DESC LIMIT 10"
  }'
```

**Security**: Only SELECT queries are allowed. The endpoint blocks dangerous SQL keywords to prevent data modification.

## Dependencies

- **SQLite.swift**: Database operations (v0.15.4)
- **SwiftUI**: User interface
- **Network.framework**: TCP/HTTP server implementation