//
//  AnthropicHTTPServer.swift
//  litellm-oidc-proxy
//
//  Created by Claude on 2025-09-04.
//

import Foundation
import Network

// Context for tracking data through CONNECT tunnels
class TunnelContext {
    let host: String
    let port: Int
    let startTime: Date
    var requestData = Data()
    var responseData = Data()
    var hasLoggedRequest = false
    var requestStartTime: Date?
    
    // Store parsed request data
    var requestMethod: String?
    var requestPath: String?
    var requestHeaders: [String: String]?
    var requestBody: Data?
    var requestModel: String?
    
    init(host: String, port: Int, startTime: Date) {
        self.host = host
        self.port = port
        self.startTime = startTime
    }
}

class AnthropicHTTPServer: ObservableObject {
    private var listener: NWListener?
    @Published var isRunning = false
    @Published var currentPort: Int = 9002
    @Published var mitmEnabled = true
    
    private let settings = AppSettings.shared
    private let certificateManager = CertificateManager.shared
    
    init() {
        currentPort = 9002 // Default port for Anthropic proxy (avoiding conflict with SSH)
    }
    
    func start(port: Int? = nil) {
        stop()
        
        if let port = port {
            currentPort = port
        }
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(currentPort)))
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.start(queue: .main)
            isRunning = true
            print("HTTP Proxy Server started on port \(currentPort)")
        } catch {
            print("Failed to start HTTP server: \(error)")
            isRunning = false
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        print("HTTP Proxy Server stopped")
    }
    
    func restart(with newPort: Int) {
        currentPort = newPort
        if isRunning {
            start(port: newPort)
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        
        var requestData = Data()
        
        func receiveData() {
            connection.receive(minimumIncompleteLength: 1, maximumLength: 1048576) { data, _, isComplete, error in
                if let data = data {
                    requestData.append(data)
                    
                    // Debug logging
                    if let requestString = String(data: requestData, encoding: .utf8) {
                        let firstLine = requestString.split(separator: "\r\n", maxSplits: 1).first ?? ""
                        print("HTTP Proxy: Received request starting with: \(firstLine)")
                    }
                    
                    // Check if we have complete headers
                    if let requestString = String(data: requestData, encoding: .utf8),
                       let headerEndRange = requestString.range(of: "\r\n\r\n") {
                        
                        // Check if this is a CONNECT request
                        let firstLine = requestString.split(separator: "\r\n", maxSplits: 1).first ?? ""
                        if firstLine.starts(with: "CONNECT") {
                            print("HTTP Proxy: Detected CONNECT request: \(firstLine)")
                            // Handle CONNECT immediately
                            Task {
                                await self.handleConnectRequest(requestString, on: connection)
                            }
                            return
                        }
                        
                        // For non-CONNECT requests, continue with existing logic
                        // Extract headers to check Content-Length
                        let headersPart = String(requestString[..<headerEndRange.lowerBound])
                        var contentLength: Int? = nil
                        
                        // Parse Content-Length header
                        let lines = headersPart.components(separatedBy: "\r\n")
                        for line in lines {
                            if line.lowercased().starts(with: "content-length:") {
                                let parts = line.split(separator: ":", maxSplits: 1)
                                if parts.count == 2 {
                                    contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces))
                                }
                                break
                            }
                        }
                        
                        // Calculate how much body we should have
                        let headerEndIndex = requestString.distance(from: requestString.startIndex, to: headerEndRange.upperBound)
                        let currentBodyLength = requestData.count - headerEndIndex
                        
                        // Check if we have the complete request
                        if let expectedBodyLength = contentLength {
                            if currentBodyLength >= expectedBodyLength {
                                // We have the complete request
                                let dataToProcess = requestData
                                Task {
                                    await self.processRequest(dataToProcess, on: connection)
                                }
                                return
                            }
                            // else continue receiving more data
                        } else {
                            // No Content-Length header, assume complete after headers for GET requests
                            // or if this is the end of the connection
                            if isComplete || lines[0].starts(with: "GET") || lines[0].starts(with: "DELETE") {
                                let dataToProcess = requestData
                                Task {
                                    await self.processRequest(dataToProcess, on: connection)
                                }
                                return
                            }
                        }
                    }
                }
                
                if isComplete && requestData.count > 0 {
                    // Connection closed, process what we have
                    let dataToProcess = requestData
                    Task {
                        await self.processRequest(dataToProcess, on: connection)
                    }
                } else if let error = error {
                    print("Connection error: \(error)")
                    connection.cancel()
                } else {
                    // Continue receiving data
                    receiveData()
                }
            }
        }
        
        receiveData()
    }
    
    private func handleConnectRequest(_ requestString: String, on clientConnection: NWConnection) async {
        let startTime = Date()
        print("HTTP Proxy: Handling CONNECT request")
        
        let lines = requestString.components(separatedBy: "\r\n")
        guard lines.count > 0 else {
            let response = "HTTP/1.1 400 Bad Request\r\n\r\n"
            if let data = response.data(using: .utf8) {
                clientConnection.send(content: data, completion: .contentProcessed { _ in
                    clientConnection.cancel()
                })
            }
            return
        }
        
        let requestLine = lines[0].components(separatedBy: " ")
        guard requestLine.count >= 3, requestLine[0] == "CONNECT" else {
            let response = "HTTP/1.1 400 Bad Request\r\n\r\n"
            if let data = response.data(using: .utf8) {
                clientConnection.send(content: data, completion: .contentProcessed { _ in
                    clientConnection.cancel()
                })
            }
            return
        }
        
        // Extract host and port from CONNECT request
        let hostPort = requestLine[1]
        let parts = hostPort.split(separator: ":", maxSplits: 1)
        guard parts.count == 2,
              let port = Int(parts[1]) else {
            let response = "HTTP/1.1 400 Bad Request\r\n\r\n"
            if let data = response.data(using: .utf8) {
                clientConnection.send(content: data, completion: .contentProcessed { _ in
                    clientConnection.cancel()
                })
            }
            return
        }
        
        let host = String(parts[0])
        print("HTTP Proxy: CONNECT to \(host):\(port)")
        
        // Create connection to target server
        // For CONNECT tunnels, we use plain TCP - the client will handle TLS
        let targetConnection = NWConnection(
            host: NWEndpoint.Host(host),
            port: NWEndpoint.Port(integerLiteral: UInt16(port)),
            using: .tcp
        )
        
        targetConnection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("HTTP Proxy: Connected to \(host):\(port)")
                
                // Log the CONNECT request
                RequestLogger.shared.updateResponse(
                    method: "CONNECT",
                    path: "\(host):\(port)",
                    requestHeaders: [:],
                    requestBody: nil,
                    responseStatus: 200,
                    responseHeaders: [:],
                    responseBody: nil,
                    startTime: startTime,
                    error: nil,
                    model: nil,
                    tokenUsage: nil
                )
                
                // Send 200 Connection Established response
                let response = "HTTP/1.1 200 Connection Established\r\n\r\n"
                if let data = response.data(using: .utf8) {
                    clientConnection.send(content: data, completion: .contentProcessed { [weak self] _ in
                        guard let self = self else { return }
                        
                        if self.mitmEnabled {
                            // MITM mode: decrypt and re-encrypt traffic
                            self.startMITMRelay(
                                clientConnection: clientConnection,
                                targetConnection: targetConnection,
                                host: host,
                                port: port,
                                startTime: startTime
                            )
                        } else {
                            // Regular mode: just relay encrypted data
                            let tunnelContext = TunnelContext(host: host, port: port, startTime: startTime)
                            self.startTunnelRelay(from: clientConnection, to: targetConnection, label: "client->target", context: tunnelContext)
                            self.startTunnelRelay(from: targetConnection, to: clientConnection, label: "target->client", context: tunnelContext)
                        }
                    })
                }
                
            case .failed(let error):
                print("Failed to connect to \(host):\(port): \(error)")
                
                // Log the failed CONNECT request
                RequestLogger.shared.updateResponse(
                    method: "CONNECT",
                    path: "\(host):\(port)",
                    requestHeaders: [:],
                    requestBody: nil,
                    responseStatus: 502,
                    responseHeaders: [:],
                    responseBody: nil,
                    startTime: startTime,
                    error: error.localizedDescription,
                    model: nil,
                    tokenUsage: nil
                )
                
                let response = "HTTP/1.1 502 Bad Gateway\r\n\r\n"
                if let data = response.data(using: .utf8) {
                    clientConnection.send(content: data, completion: .contentProcessed { _ in
                        clientConnection.cancel()
                    })
                }
                targetConnection.cancel()
                
            case .cancelled:
                clientConnection.cancel()
                
            default:
                break
            }
        }
        
        targetConnection.start(queue: .global())
    }
    
    private func startRelay(from source: NWConnection, to destination: NWConnection, label: String = "") {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                print("HTTP Proxy: Relaying \(data.count) bytes \(label)")
                destination.send(content: data, completion: .contentProcessed { _ in
                    if !isComplete {
                        self.startRelay(from: source, to: destination, label: label)
                    }
                })
            } else if isComplete || error != nil {
                print("HTTP Proxy: Relay complete or error \(label): \(error?.localizedDescription ?? "complete")")
                destination.cancel()
            } else {
                self.startRelay(from: source, to: destination, label: label)
            }
        }
    }
    
    private func startMITMRelay(
        clientConnection: NWConnection,
        targetConnection: NWConnection,
        host: String,
        port: Int,
        startTime: Date
    ) {
        print("HTTP Proxy: MITM mode activated for \(host):\(port)")
        
        // In MITM mode, we need to:
        // 1. Accept TLS from client using our certificate for the target host
        // 2. Establish TLS to the real server
        // 3. Decrypt from client, log, re-encrypt to server
        // 4. Decrypt from server, log, re-encrypt to client
        
        // For now, we'll use a simplified approach
        // In production, you'd need proper TLS handling with SecureTransport or Network.framework TLS
        
        // This is a placeholder - full MITM implementation would be complex
        print("HTTP Proxy: MITM certificate generation and TLS interception not yet implemented")
        
        // Fall back to regular relay for now
        let tunnelContext = TunnelContext(host: host, port: port, startTime: startTime)
        startTunnelRelay(from: clientConnection, to: targetConnection, label: "client->target", context: tunnelContext)
        startTunnelRelay(from: targetConnection, to: clientConnection, label: "target->client", context: tunnelContext)
    }
    
    private func startTunnelRelay(from source: NWConnection, to destination: NWConnection, label: String, context: TunnelContext) {
        source.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                // Forward the data immediately
                destination.send(content: data, completion: .contentProcessed { _ in
                    if !isComplete {
                        self?.startTunnelRelay(from: source, to: destination, label: label, context: context)
                    }
                })
                
                // Parse and log HTTP data
                if label.contains("client->target") {
                    // This is request data
                    context.requestData.append(data)
                    
                    // Try to parse HTTP request if we haven't logged it yet
                    if !context.hasLoggedRequest {
                        self?.parseAndLogTunnelRequest(context: context)
                    }
                } else {
                    // This is response data
                    context.responseData.append(data)
                    
                    // Try to parse HTTP response
                    if context.hasLoggedRequest && context.requestStartTime != nil {
                        self?.parseAndLogTunnelResponse(context: context)
                    }
                }
            } else if isComplete || error != nil {
                print("HTTP Proxy: Tunnel relay complete or error \(label): \(error?.localizedDescription ?? "complete")")
                destination.cancel()
            } else {
                self?.startTunnelRelay(from: source, to: destination, label: label, context: context)
            }
        }
    }
    
    private func parseAndLogTunnelRequest(context: TunnelContext) {
        // Look for HTTP request pattern
        guard let requestString = String(data: context.requestData, encoding: .utf8) else { return }
        
        // Check if we have complete headers
        guard let headerEndRange = requestString.range(of: "\r\n\r\n") else { return }
        
        // Parse the request line
        let lines = requestString.components(separatedBy: "\r\n")
        guard lines.count > 0 else { return }
        
        let requestLine = lines[0].components(separatedBy: " ")
        guard requestLine.count >= 3 else { return }
        
        let method = requestLine[0]
        let path = requestLine[1]
        
        // Parse headers
        var headers: [String: String] = [:]
        var contentLength: Int?
        
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty { break }
            
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
                
                if key.lowercased() == "content-length" {
                    contentLength = Int(value)
                }
            }
        }
        
        // Extract body if present
        var bodyData: Data?
        let headerEndIndex = requestString.distance(from: requestString.startIndex, to: headerEndRange.upperBound)
        if headerEndIndex < context.requestData.count {
            bodyData = context.requestData[headerEndIndex...]
            
            // Check if we have the complete body
            if let expectedLength = contentLength, bodyData?.count ?? 0 < expectedLength {
                return // Wait for more data
            }
        }
        
        // Mark that we've parsed a complete request
        context.hasLoggedRequest = true
        context.requestStartTime = Date()
        
        // Store request info in context for later
        context.requestMethod = method
        context.requestPath = path
        context.requestHeaders = headers
        context.requestBody = bodyData
        
        // Extract model from body if it's JSON
        var model: String?
        if let bodyData = bodyData,
           let json = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            model = json["model"] as? String
        }
        context.requestModel = model
        
        print("HTTP Proxy: Tunneled request - \(method) https://\(context.host)\(path)")
    }
    
    private func parseAndLogTunnelResponse(context: TunnelContext) {
        // Look for HTTP response pattern
        guard let responseString = String(data: context.responseData, encoding: .utf8) else { return }
        
        // Check if we have complete headers
        guard let headerEndRange = responseString.range(of: "\r\n\r\n") else { return }
        
        // Parse status line
        let lines = responseString.components(separatedBy: "\r\n")
        guard lines.count > 0 else { return }
        
        let statusLine = lines[0].components(separatedBy: " ")
        guard statusLine.count >= 2,
              let statusCode = Int(statusLine[1]) else { return }
        
        // Parse headers
        var headers: [String: String] = [:]
        var contentLength: Int?
        
        for i in 1..<lines.count {
            let line = lines[i]
            if line.isEmpty { break }
            
            if let colonIndex = line.firstIndex(of: ":") {
                let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                headers[key] = value
                
                if key.lowercased() == "content-length" {
                    contentLength = Int(value)
                }
            }
        }
        
        // Extract body if present
        var bodyData: Data?
        let headerEndIndex = responseString.distance(from: responseString.startIndex, to: headerEndRange.upperBound)
        if headerEndIndex < context.responseData.count {
            bodyData = context.responseData[headerEndIndex...]
            
            // Check if we have the complete body
            if let expectedLength = contentLength, bodyData?.count ?? 0 < expectedLength {
                return // Wait for more data
            }
        }
        
        // Log the complete request/response
        if let startTime = context.requestStartTime,
           let method = context.requestMethod,
           let path = context.requestPath,
           let requestHeaders = context.requestHeaders {
            
            let bodyString = context.requestBody.flatMap { String(data: $0, encoding: .utf8) }
            
            RequestLogger.shared.updateResponse(
                method: method,
                path: "https://\(context.host)\(path)",
                requestHeaders: requestHeaders,
                requestBody: bodyString,
                responseStatus: statusCode,
                responseHeaders: headers,
                responseBody: bodyData,
                startTime: startTime,
                error: nil,
                model: context.requestModel,
                tokenUsage: nil
            )
            
            print("HTTP Proxy: Tunneled response - \(statusCode) for \(method) https://\(context.host)\(path)")
        }
        
        // Reset for next request in the tunnel
        context.requestData = Data()
        context.responseData = Data()
        context.hasLoggedRequest = false
        context.requestStartTime = nil
    }
    
    private func processRequest(_ requestData: Data, on connection: NWConnection) async {
        let startTime = Date()
        print("HTTP Proxy: Processing request")
        
        guard let requestString = String(data: requestData, encoding: .utf8) else {
            let response = "HTTP/1.1 500 Internal Server Error\r\nContent-Type: text/plain\r\nContent-Length: 15\r\nConnection: close\r\n\r\nInvalid request"
            if let data = response.data(using: .utf8) {
                connection.send(content: data, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
            return
        }
        
        // Parse HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard lines.count > 0 else {
            let response = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: 11\r\nConnection: close\r\n\r\nBad Request"
            if let data = response.data(using: .utf8) {
                connection.send(content: data, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
            return
        }
        
        let requestLine = lines[0].components(separatedBy: " ")
        guard requestLine.count >= 3 else {
            let response = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: 11\r\nConnection: close\r\n\r\nBad Request"
            if let data = response.data(using: .utf8) {
                connection.send(content: data, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
            return
        }
        
        let method = requestLine[0]
        var path = requestLine[1]
        let httpVersion = requestLine[2]
        
        // Validate method and path
        guard !method.isEmpty && !path.isEmpty else {
            print("HTTP Proxy: Invalid request - empty method or path")
            let response = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: 11\r\nConnection: close\r\n\r\nBad Request"
            if let data = response.data(using: .utf8) {
                connection.send(content: data, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
            return
        }
        
        // Parse headers for logging and API key extraction
        var requestHeadersDict: [String: String] = [:]
        var apiKey: String?
        var hostHeader: String?
        
        for i in 1..<lines.count {
            let header = lines[i]
            if header.isEmpty {
                break // End of headers
            }
            
            if let colonIndex = header.firstIndex(of: ":") {
                let key = String(header[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(header[header.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                requestHeadersDict[key] = value
                
                // Extract API key
                if key.lowercased() == "x-api-key" {
                    apiKey = value
                }
                
                // Extract Host header
                if key.lowercased() == "host" {
                    hostHeader = value
                }
            }
        }
        
        // Determine target host from request
        var targetHost: String?
        var targetScheme = "https" // Default to HTTPS for API requests
        
        // Check if this is an Anthropic API path
        let anthropicPaths = ["/v1/messages", "/v1/complete", "/v1/models"]
        let isAnthropicPath = anthropicPaths.contains(where: { path.hasPrefix($0) })
        
        // Check if path contains full URL (for absolute URLs in HTTP proxy requests)
        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            print("HTTP Proxy: Processing absolute URL: \(path)")
            if let url = URL(string: path) {
                targetHost = url.host
                targetScheme = url.scheme ?? targetScheme
                path = url.path.isEmpty ? "/" : url.path
                if let query = url.query {
                    path += "?" + query
                }
                print("HTTP Proxy: Extracted - host: \(targetHost ?? "nil"), scheme: \(targetScheme), path: \(path)")
            }
        } else if isAnthropicPath {
            // This is a direct Anthropic API request - forward to api.anthropic.com
            targetHost = "api.anthropic.com"
            targetScheme = "https"
            print("HTTP Proxy: Detected Anthropic API path, forwarding to api.anthropic.com")
        } else if let host = hostHeader {
            // Use Host header if available
            targetHost = host
            print("HTTP Proxy: Using Host header: \(targetHost)")
        }
        
        // If we still don't have a target host, reject the request
        guard let finalHost = targetHost else {
            print("HTTP Proxy: No target host found in request")
            let response = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: 24\r\nConnection: close\r\n\r\nNo target host specified"
            if let data = response.data(using: .utf8) {
                connection.send(content: data, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
            return
        }
        
        // Extract body if present
        var bodyData: Data?
        if let headerEndIndex = requestData.firstRange(of: Data("\r\n\r\n".utf8))?.upperBound {
            let body = requestData[headerEndIndex...]
            if !body.isEmpty {
                bodyData = body
            }
        }
        
        print("HTTP Proxy: Request - \(method) \(path) -> \(targetScheme)://\(finalHost)")
        
        // Forward request to target host
        await forwardToTarget(
            targetHost: finalHost,
            targetScheme: targetScheme,
            method: method,
            path: path,
            httpVersion: httpVersion,
            headers: lines,
            requestData: requestData,
            requestHeadersDict: requestHeadersDict,
            requestBodyData: bodyData,
            apiKey: apiKey,
            on: connection,
            startTime: startTime
        )
    }
    
    private func forwardToTarget(
        targetHost: String,
        targetScheme: String,
        method: String,
        path: String,
        httpVersion: String,
        headers: [String],
        requestData: Data,
        requestHeadersDict: [String: String],
        requestBodyData: Data?,
        apiKey: String?,
        on connection: NWConnection,
        startTime: Date
    ) async {
        // Build target URL
        var urlComponents = URLComponents()
        urlComponents.scheme = targetScheme
        urlComponents.host = targetHost
        
        // Parse path and query separately
        let pathOnly: String
        let queryString: String?
        
        if let queryIndex = path.firstIndex(of: "?") {
            pathOnly = String(path[..<queryIndex])
            queryString = String(path[path.index(after: queryIndex)...])
        } else {
            pathOnly = path
            queryString = nil
        }
        
        urlComponents.path = pathOnly
        
        // Set query string if present
        if let queryString = queryString {
            urlComponents.query = queryString
        }
        
        guard let targetURL = urlComponents.url else {
            // Convert body data to string for error logging
            let bodyString = requestBodyData.flatMap { String(data: $0, encoding: .utf8) }
            await sendErrorResponse(502, "Invalid target URL", on: connection, startTime: startTime, method: method, path: path, requestHeaders: requestHeadersDict, requestBody: bodyString)
            return
        }
        
        // Create URLRequest
        var request = URLRequest(url: targetURL)
        request.httpMethod = method
        
        // Copy headers (skip the request line and Host header)
        for (key, value) in requestHeadersDict {
            // Skip certain headers
            if key.lowercased() == "host" ||
               key.lowercased() == "connection" {
                continue
            }
            
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Set the body
        request.httpBody = requestBodyData
        
        // Convert body to string for logging
        let requestBodyString = requestBodyData.flatMap { data in
            let settings = AppSettings.shared
            if settings.truncateLogs && data.count > settings.logTruncationLimit {
                return String(data: data.prefix(settings.logTruncationLimit), encoding: .utf8).map { $0 + "\n... (truncated)" }
            } else {
                return String(data: data, encoding: .utf8)
            }
        }
        
        // Extract model from request body
        var model: String? = nil
        var isStreaming = false
        if let bodyData = requestBodyData,
           let bodyJSON = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
            model = bodyJSON["model"] as? String
            isStreaming = bodyJSON["stream"] as? Bool ?? false
        }
        
        // Handle the request based on streaming preference
        if isStreaming {
            await handleStreamingRequest(request, on: connection, startTime: startTime, method: method, path: path, requestHeaders: requestHeadersDict, requestBody: requestBodyString, apiKey: apiKey, model: model)
        } else {
            await handleRegularRequest(request, on: connection, startTime: startTime, method: method, path: path, requestHeaders: requestHeadersDict, requestBody: requestBodyString, apiKey: apiKey, model: model)
        }
    }
    
    private func handleRegularRequest(
        _ request: URLRequest,
        on connection: NWConnection,
        startTime: Date,
        method: String,
        path: String,
        requestHeaders: [String: String],
        requestBody: String?,
        apiKey: String?,
        model: String?
    ) async {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                await sendErrorResponse(502, "Invalid response from target server", on: connection, startTime: startTime, method: method, path: path, requestHeaders: requestHeaders, requestBody: requestBody)
                return
            }
            
            // Build response
            var responseLines = ["HTTP/1.1 \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"]
            
            // Copy response headers
            var responseHeadersDict: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let keyString = key as? String,
                   let valueString = value as? String {
                    responseLines.append("\(keyString): \(valueString)")
                    responseHeadersDict[keyString] = valueString
                }
            }
            
            // Add content length if not present
            if responseHeadersDict["Content-Length"] == nil {
                responseLines.append("Content-Length: \(data.count)")
            }
            
            responseLines.append("")
            
            // Send headers
            let headerData = responseLines.joined(separator: "\r\n").data(using: .utf8)!
            
            // Send complete response
            var completeResponse = headerData
            completeResponse.append(data)
            
            // Convert response body to string for logging
            let _: String? = {
                let settings = AppSettings.shared
                if settings.truncateLogs && data.count > settings.logTruncationLimit {
                    return String(data: data.prefix(settings.logTruncationLimit), encoding: .utf8).map { $0 + "\n... (truncated)" }
                } else {
                    return String(data: data, encoding: .utf8)
                }
            }()
            
            // Log the request and response
            RequestLogger.shared.updateResponse(
                method: method,
                path: path,
                requestHeaders: requestHeaders,
                requestBody: requestBody,
                responseStatus: httpResponse.statusCode,
                responseHeaders: responseHeadersDict,
                responseBody: data,
                startTime: startTime,
                error: nil,
                model: model,
                tokenUsage: nil
            )
            
            connection.send(content: completeResponse, completion: .contentProcessed { _ in
                connection.cancel()
            })
            
        } catch {
            print("HTTP Proxy: Request failed: \(error)")
            await sendErrorResponse(502, "Failed to forward request", on: connection, startTime: startTime, method: method, path: path, requestHeaders: requestHeaders, requestBody: requestBody, error: error.localizedDescription, model: model)
        }
    }
    
    private func handleStreamingRequest(
        _ request: URLRequest,
        on connection: NWConnection,
        startTime: Date,
        method: String,
        path: String,
        requestHeaders: [String: String],
        requestBody: String?,
        apiKey: String?,
        model: String?
    ) async {
        print("HTTP Proxy: Handling streaming request")
        
        let session = URLSession(configuration: .default)
        let _ = session.dataTask(with: request)
        
        var hasReceivedHeaders = false
        var responseStatusCode = 0
        var responseHeadersDict: [String: String] = [:]
        var accumulatedData = Data()
        
        let delegate = AnthropicStreamingDelegate { data, response, error in
            if let error = error {
                print("HTTP Proxy: Streaming error: \(error)")
                if !hasReceivedHeaders {
                    Task {
                        await self.sendErrorResponse(502, "Streaming request failed", on: connection, startTime: startTime, method: method, path: path, requestHeaders: requestHeaders, requestBody: requestBody, error: error.localizedDescription, model: model)
                    }
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse, !hasReceivedHeaders {
                hasReceivedHeaders = true
                responseStatusCode = httpResponse.statusCode
                
                // Build response headers
                var responseLines = ["HTTP/1.1 \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))"]
                
                // Copy response headers
                for (key, value) in httpResponse.allHeaderFields {
                    if let keyString = key as? String,
                       let valueString = value as? String {
                        responseLines.append("\(keyString): \(valueString)")
                        responseHeadersDict[keyString] = valueString
                    }
                }
                
                responseLines.append("")
                responseLines.append("")
                
                // Send headers
                let headerString = responseLines.joined(separator: "\r\n")
                if let headerData = headerString.data(using: .utf8) {
                    connection.send(content: headerData, completion: .contentProcessed { _ in })
                }
            }
            
            if let data = data {
                accumulatedData.append(data)
                
                // Forward the data chunk
                connection.send(content: data, completion: .contentProcessed { _ in })
            }
        }
        
        delegate.onComplete = {
            // Convert accumulated response to string for logging
            let _: String? = {
                let settings = AppSettings.shared
                if settings.truncateLogs && accumulatedData.count > settings.logTruncationLimit {
                    return String(data: accumulatedData.prefix(settings.logTruncationLimit), encoding: .utf8).map { $0 + "\n... (truncated)" }
                } else {
                    return String(data: accumulatedData, encoding: .utf8)
                }
            }()
            
            // Log the complete request/response
            Task {
                RequestLogger.shared.updateResponse(
                    method: method,
                    path: path,
                    requestHeaders: requestHeaders,
                    requestBody: requestBody,
                    responseStatus: responseStatusCode,
                    responseHeaders: responseHeadersDict,
                    responseBody: accumulatedData,
                    startTime: startTime,
                    error: nil,
                    model: model,
                    tokenUsage: nil
                )
            }
            
            connection.cancel()
        }
        
        // Create a custom session with the delegate
        let sessionConfig = URLSessionConfiguration.default
        let customSession = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        let streamingTask = customSession.dataTask(with: request)
        streamingTask.resume()
    }
    
    private func sendErrorResponse(
        _ statusCode: Int,
        _ message: String,
        on connection: NWConnection,
        startTime: Date,
        method: String,
        path: String,
        requestHeaders: [String: String],
        requestBody: String?,
        error: String? = nil,
        model: String? = nil
    ) async {
        let statusText = HTTPURLResponse.localizedString(forStatusCode: statusCode)
        let response = "HTTP/1.1 \(statusCode) \(statusText)\r\nContent-Type: text/plain\r\nContent-Length: \(message.count)\r\nConnection: close\r\n\r\n\(message)"
        
        // Log the error
        RequestLogger.shared.updateResponse(
            method: method,
            path: path,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseStatus: statusCode,
            responseHeaders: ["Content-Type": "text/plain"],
            responseBody: message.data(using: .utf8),
            startTime: startTime,
            error: error ?? message,
            model: model,
            tokenUsage: nil
        )
        
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        }
    }
}

// MARK: - Streaming Support

private class AnthropicStreamingDelegate: NSObject, URLSessionDataDelegate {
    let onDataReceived: (Data?, URLResponse?, Error?) -> Void
    var onComplete: (() -> Void)?
    
    init(onDataReceived: @escaping (Data?, URLResponse?, Error?) -> Void) {
        self.onDataReceived = onDataReceived
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        onDataReceived(nil, response, nil)
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        onDataReceived(data, nil, nil)
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            onDataReceived(nil, nil, error)
        }
        onComplete?()
    }
}

