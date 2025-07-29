//
//  HTTPServer.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 7/29/25.
//

import Foundation
import Network

class HTTPServer: ObservableObject {
    private var listener: NWListener?
    @Published var isRunning = false
    @Published var currentPort: Int = 9000
    
    // Token cache
    private var cachedToken: String?
    private var tokenExpiryDate: Date?
    private let tokenRefreshBuffer: TimeInterval = 60 // Refresh 1 minute before expiry
    
    private let settings = AppSettings.shared
    
    init() {
        currentPort = AppSettings.shared.port
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
        cachedToken = nil
        tokenExpiryDate = nil
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
                    
                    // Check if we have complete headers
                    if let requestString = String(data: requestData, encoding: .utf8),
                       let headerEndRange = requestString.range(of: "\r\n\r\n") {
                        
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
    
    private func processRequest(_ requestData: Data, on connection: NWConnection) async {
        let startTime = Date()
        print("HTTPServer: Processing request")
        
        guard let requestString = String(data: requestData, encoding: .utf8) else {
            // Simple error response without logging for malformed requests
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
            // Simple error response without logging for malformed requests
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
            // Simple error response without logging for malformed requests
            let response = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: 11\r\nConnection: close\r\n\r\nBad Request"
            if let data = response.data(using: .utf8) {
                connection.send(content: data, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
            return
        }
        
        let method = requestLine[0]
        let path = requestLine[1]
        let httpVersion = requestLine[2]
        
        // Validate method and path
        guard !method.isEmpty && !path.isEmpty else {
            print("HTTPServer: Invalid request - empty method or path")
            let response = "HTTP/1.1 400 Bad Request\r\nContent-Type: text/plain\r\nContent-Length: 11\r\nConnection: close\r\n\r\nBad Request"
            if let data = response.data(using: .utf8) {
                connection.send(content: data, completion: .contentProcessed { _ in
                    connection.cancel()
                })
            }
            return
        }
        
        // Parse headers for logging
        var requestHeadersDict: [String: String] = [:]
        for i in 1..<lines.count {
            let header = lines[i]
            if header.isEmpty {
                break // End of headers
            }
            
            if let colonIndex = header.firstIndex(of: ":") {
                let key = String(header[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(header[header.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                requestHeadersDict[key] = value
            }
        }
        
        // Extract body if present
        var bodyData: Data?
        if let headerEndIndex = requestData.firstRange(of: Data("\r\n\r\n".utf8))?.upperBound {
            let body = requestData[headerEndIndex...]
            if !body.isEmpty {
                bodyData = body
            }
        }
        
        // Don't log the request here - we'll log the complete request/response together
        print("HTTPServer: Request - \(method) \(path)")
        
        // Validate configuration
        guard !settings.litellmEndpoint.isEmpty,
              !settings.keycloakURL.isEmpty,
              !settings.keycloakClientId.isEmpty,
              !settings.keycloakClientSecret.isEmpty else {
            await sendErrorResponse(503, "Proxy not configured. Please configure LiteLLM and OIDC settings.", on: connection, startTime: startTime, method: method, path: path, requestHeaders: requestHeadersDict, requestBody: bodyData)
            return
        }
        
        // Get OIDC token
        do {
            let token = try await getOIDCToken()
            
            // Forward request to LiteLLM
            await forwardRequest(
                method: method,
                path: path,
                httpVersion: httpVersion,
                headers: lines,
                requestData: requestData,
                requestHeadersDict: requestHeadersDict,
                requestBodyData: bodyData,
                token: token,
                on: connection,
                startTime: startTime
            )
        } catch {
            print("Failed to get OIDC token: \(error)")
            await sendErrorResponse(502, "Failed to authenticate with OIDC provider", on: connection, startTime: startTime, method: method, path: path, requestHeaders: requestHeadersDict, requestBody: bodyData, error: error.localizedDescription)
        }
    }
    
    private func getOIDCToken() async throws -> String {
        // Check if we have a valid cached token
        if let cachedToken = cachedToken,
           let expiryDate = tokenExpiryDate,
           Date().addingTimeInterval(tokenRefreshBuffer) < expiryDate {
            return cachedToken
        }
        
        // Fetch new token
        let result = await OIDCClient.getAccessTokenWithExpiry(
            keycloakURL: settings.keycloakURL,
            clientId: settings.keycloakClientId,
            clientSecret: settings.keycloakClientSecret
        )
        
        switch result {
        case .success(let tokenInfo):
            cachedToken = tokenInfo.token
            tokenExpiryDate = tokenInfo.expiryDate
            return tokenInfo.token
        case .failure(let error):
            throw error
        }
    }
    
    private func forwardRequest(
        method: String,
        path: String,
        httpVersion: String,
        headers: [String],
        requestData: Data,
        requestHeadersDict: [String: String],
        requestBodyData: Data?,
        token: String,
        on connection: NWConnection,
        startTime: Date
    ) async {
        // Build target URL
        guard var urlComponents = URLComponents(string: settings.litellmEndpoint) else {
            await sendErrorResponse(502, "Invalid LiteLLM endpoint", on: connection, startTime: startTime, method: method, path: path, requestHeaders: requestHeadersDict, requestBody: requestBodyData)
            return
        }
        
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
        
        // Append the request path (without query)
        if !urlComponents.path.hasSuffix("/") && !pathOnly.hasPrefix("/") {
            urlComponents.path.append("/")
        }
        urlComponents.path.append(pathOnly)
        
        // Set query string if present
        if let queryString = queryString {
            urlComponents.query = queryString
        }
        
        guard let targetURL = urlComponents.url else {
            await sendErrorResponse(502, "Invalid target URL", on: connection, startTime: startTime, method: method, path: path, requestHeaders: requestHeadersDict, requestBody: requestBodyData)
            return
        }
        
        // Create URLRequest
        var request = URLRequest(url: targetURL)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // Copy headers (skip the request line and Host header)
        var contentLength: Int?
        var isChunked = false
        
        for (key, value) in requestHeadersDict {
            // Skip certain headers
            if key.lowercased() == "host" || 
               key.lowercased() == "authorization" ||
               key.lowercased() == "connection" {
                continue
            }
            
            if key.lowercased() == "content-length" {
                contentLength = Int(value)
            }
            
            if key.lowercased() == "transfer-encoding" && value.lowercased().contains("chunked") {
                isChunked = true
            }
            
            request.setValue(value, forHTTPHeaderField: key)
        }
        
        // Extract body if present
        if let headerEndIndex = requestData.firstRange(of: Data("\r\n\r\n".utf8))?.upperBound {
            let bodyData = requestData[headerEndIndex...]
            if !bodyData.isEmpty {
                request.httpBody = bodyData
            }
        }
        
        // Convert body to string for logging
        let requestBodyString = request.httpBody.flatMap { data in
            if data.count > 10000 {
                return String(data: data.prefix(10000), encoding: .utf8).map { $0 + "\n... (truncated)" }
            } else {
                return String(data: data, encoding: .utf8)
            }
        }
        
        // Handle streaming responses
        if method == "POST" && (path.contains("/chat/completions") || path.contains("/messages")) {
            // Check if request wants streaming
            var isStreaming = false
            if let bodyData = request.httpBody,
               let bodyJSON = try? JSONSerialization.jsonObject(with: bodyData) as? [String: Any] {
                isStreaming = bodyJSON["stream"] as? Bool ?? false
            }
            
            if isStreaming {
                await handleStreamingRequest(request, on: connection, startTime: startTime, method: method, path: path, requestHeaders: requestHeadersDict, requestBody: requestBodyString, token: token)
            } else {
                await handleRegularRequest(request, on: connection, startTime: startTime, method: method, path: path, requestHeaders: requestHeadersDict, requestBody: requestBodyString, token: token)
            }
        } else {
            await handleRegularRequest(request, on: connection, startTime: startTime, method: method, path: path, requestHeaders: requestHeadersDict, requestBody: requestBodyString, token: token)
        }
    }
}