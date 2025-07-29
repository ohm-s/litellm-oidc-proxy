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
    @Published var currentPort: Int = 8080
    
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
            connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let data = data {
                    requestData.append(data)
                    
                    // Check if we have complete headers
                    if let requestString = String(data: requestData, encoding: .utf8),
                       requestString.contains("\r\n\r\n") {
                        
                        let dataToProcess = requestData
                        Task {
                            await self.processRequest(dataToProcess, on: connection)
                        }
                        return
                    }
                }
                
                if isComplete {
                    connection.cancel()
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
        guard let requestString = String(data: requestData, encoding: .utf8) else {
            await sendErrorResponse(500, "Invalid request", on: connection)
            return
        }
        
        // Validate configuration
        guard !settings.litellmEndpoint.isEmpty,
              !settings.keycloakURL.isEmpty,
              !settings.keycloakClientId.isEmpty,
              !settings.keycloakClientSecret.isEmpty else {
            await sendErrorResponse(503, "Proxy not configured. Please configure LiteLLM and OIDC settings.", on: connection)
            return
        }
        
        // Parse HTTP request
        let lines = requestString.components(separatedBy: "\r\n")
        guard lines.count > 0 else {
            await sendErrorResponse(400, "Bad Request", on: connection)
            return
        }
        
        let requestLine = lines[0].components(separatedBy: " ")
        guard requestLine.count >= 3 else {
            await sendErrorResponse(400, "Bad Request", on: connection)
            return
        }
        
        let method = requestLine[0]
        let path = requestLine[1]
        let httpVersion = requestLine[2]
        
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
                token: token,
                on: connection
            )
        } catch {
            print("Failed to get OIDC token: \(error)")
            await sendErrorResponse(502, "Failed to authenticate with OIDC provider", on: connection)
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
        token: String,
        on connection: NWConnection
    ) async {
        // Build target URL
        guard var urlComponents = URLComponents(string: settings.litellmEndpoint) else {
            await sendErrorResponse(502, "Invalid LiteLLM endpoint", on: connection)
            return
        }
        
        // Append the request path
        if !urlComponents.path.hasSuffix("/") && !path.hasPrefix("/") {
            urlComponents.path.append("/")
        }
        urlComponents.path.append(path)
        
        // Parse query string from original path
        if let queryIndex = path.firstIndex(of: "?") {
            let queryString = String(path[path.index(after: queryIndex)...])
            urlComponents.query = queryString
        }
        
        guard let targetURL = urlComponents.url else {
            await sendErrorResponse(502, "Invalid target URL", on: connection)
            return
        }
        
        // Create URLRequest
        var request = URLRequest(url: targetURL)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        // Copy headers (skip the request line and Host header)
        var contentLength: Int?
        var isChunked = false
        
        for i in 1..<headers.count {
            let header = headers[i]
            if header.isEmpty {
                break // End of headers
            }
            
            if let colonIndex = header.firstIndex(of: ":") {
                let key = String(header[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(header[header.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                
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
        }
        
        // Extract body if present
        if let headerEndIndex = requestData.firstRange(of: Data("\r\n\r\n".utf8))?.upperBound {
            let bodyData = requestData[headerEndIndex...]
            if !bodyData.isEmpty {
                request.httpBody = bodyData
            }
        }
        
        // Handle streaming responses
        if path.contains("/chat/completions") && method == "POST" {
            await handleStreamingRequest(request, on: connection)
        } else {
            await handleRegularRequest(request, on: connection)
        }
    }
    
    private func handleRegularRequest(_ request: URLRequest, on connection: NWConnection) async {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await sendErrorResponse(502, "Invalid response from upstream", on: connection)
                return
            }
            
            // Build response
            var responseString = "HTTP/1.1 \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))\r\n"
            
            // Copy response headers
            for (key, value) in httpResponse.allHeaderFields {
                if let keyString = key as? String,
                   let valueString = value as? String {
                    responseString += "\(keyString): \(valueString)\r\n"
                }
            }
            
            responseString += "\r\n"
            
            // Send headers and body
            if var responseData = responseString.data(using: .utf8) {
                responseData.append(data)
                connection.send(content: responseData, completion: .contentProcessed { error in
                    if let error = error {
                        print("Send error: \(error)")
                    }
                    connection.cancel()
                })
            }
        } catch {
            print("Request failed: \(error)")
            await sendErrorResponse(502, "Request to upstream failed", on: connection)
        }
    }
    
    private func handleStreamingRequest(_ request: URLRequest, on connection: NWConnection) async {
        let session = URLSession(configuration: .default)
        
        let task = session.dataTask(with: request)
        let delegate = StreamingDelegate(connection: connection)
        task.delegate = delegate
        task.resume()
        
        // Wait for completion
        await delegate.waitForCompletion()
    }
    
    private func sendErrorResponse(_ code: Int, _ message: String, on connection: NWConnection) async {
        let response = """
        HTTP/1.1 \(code) \(HTTPURLResponse.localizedString(forStatusCode: code))\r
        Content-Type: text/plain\r
        Content-Length: \(message.count)\r
        Connection: close\r
        \r
        \(message)
        """
        
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    print("Send error: \(error)")
                }
                connection.cancel()
            })
        }
    }
}

// Helper class for streaming responses
class StreamingDelegate: NSObject, URLSessionDataDelegate {
    private let connection: NWConnection
    private var headersSent = false
    private let semaphore = DispatchSemaphore(value: 0)
    
    init(connection: NWConnection) {
        self.connection = connection
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        
        // Send headers
        var responseString = "HTTP/1.1 \(httpResponse.statusCode) \(HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode))\r\n"
        
        for (key, value) in httpResponse.allHeaderFields {
            if let keyString = key as? String,
               let valueString = value as? String {
                responseString += "\(keyString): \(valueString)\r\n"
            }
        }
        
        responseString += "\r\n"
        
        if let data = responseString.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    print("Send headers error: \(error)")
                }
            })
        }
        
        headersSent = true
        completionHandler(.allow)
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        // Stream data chunks
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("Send data error: \(error)")
            }
        })
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Stream error: \(error)")
        }
        connection.cancel()
        semaphore.signal()
    }
    
    func waitForCompletion() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                self.semaphore.wait()
                continuation.resume()
            }
        }
    }
}

// Extension to OIDCClient for token with expiry
extension OIDCClient {
    struct TokenInfo {
        let token: String
        let expiryDate: Date
    }
    
    static func getAccessTokenWithExpiry(keycloakURL: String, clientId: String, clientSecret: String) async -> Result<TokenInfo, OIDCError> {
        // Build token endpoint URL
        guard var urlComponents = URLComponents(string: keycloakURL) else {
            return .failure(.invalidURL)
        }
        
        // Ensure URL ends with /protocol/openid-connect/token
        let path = urlComponents.path
        if !path.contains("/protocol/openid-connect/token") {
            if path.hasSuffix("/") {
                urlComponents.path = path + "protocol/openid-connect/token"
            } else {
                urlComponents.path = path + "/protocol/openid-connect/token"
            }
        }
        
        guard let url = urlComponents.url else {
            return .failure(.invalidURL)
        }
        
        // Prepare request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Prepare body
        let bodyString = "grant_type=client_credentials&client_id=\(clientId)&client_secret=\(clientSecret)"
        request.httpBody = bodyString.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.unknownError)
            }
            
            if httpResponse.statusCode == 200 {
                // Success - try to decode token
                let decoder = JSONDecoder()
                if let tokenResponse = try? decoder.decode(TokenResponse.self, from: data) {
                    let expiresIn = tokenResponse.expires_in ?? 3600 // Default to 1 hour
                    let expiryDate = Date().addingTimeInterval(TimeInterval(expiresIn))
                    return .success(TokenInfo(token: tokenResponse.access_token, expiryDate: expiryDate))
                } else {
                    return .failure(.decodingError)
                }
            } else {
                // Error - try to decode error response
                let decoder = JSONDecoder()
                if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                    return .failure(.serverError(errorResponse.error_description ?? errorResponse.error))
                } else if let errorString = String(data: data, encoding: .utf8) {
                    return .failure(.serverError("HTTP \(httpResponse.statusCode): \(errorString)"))
                } else {
                    return .failure(.serverError("HTTP \(httpResponse.statusCode)"))
                }
            }
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }
}