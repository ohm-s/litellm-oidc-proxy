//
//  HTTPServer+Logging.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 7/29/25.
//

import Foundation
import Network

extension HTTPServer {
    
    func sendErrorResponse(
        _ code: Int,
        _ message: String,
        on connection: NWConnection,
        startTime: Date,
        method: String,
        path: String,
        requestHeaders: [String: String] = [:],
        requestBody: Data? = nil,
        error: String? = nil
    ) async {
        print("HTTPServer: Sending error response - \(code) for \(method) \(path)")
        let response = """
        HTTP/1.1 \(code) \(HTTPURLResponse.localizedString(forStatusCode: code))\r
        Content-Type: text/plain\r
        Content-Length: \(message.count)\r
        Connection: close\r
        \r
        \(message)
        """
        
        // Convert body to string for logging
        let requestBodyString = requestBody.flatMap { data in
            if data.count > 10000 {
                return String(data: data.prefix(10000), encoding: .utf8).map { $0 + "\n... (truncated)" }
            } else {
                return String(data: data, encoding: .utf8)
            }
        }
        
        // Log the error response
        RequestLogger.shared.updateResponse(
            method: method,
            path: path,
            requestHeaders: requestHeaders,
            requestBody: requestBodyString,
            responseStatus: code,
            responseHeaders: ["Content-Type": "text/plain"],
            responseBody: message.data(using: .utf8),
            startTime: startTime,
            error: error ?? message
        )
        
        if let data = response.data(using: .utf8) {
            connection.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    print("Send error: \(error)")
                }
                connection.cancel()
            })
        }
    }
    
    func handleRegularRequest(
        _ request: URLRequest,
        on connection: NWConnection,
        startTime: Date,
        method: String,
        path: String,
        requestHeaders: [String: String],
        requestBody: String?,
        token: String
    ) async {
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await sendErrorResponse(502, "Invalid response from upstream", on: connection, startTime: startTime, method: method, path: path)
                return
            }
            
            // Build response headers dictionary for logging
            var responseHeaders: [String: String] = [:]
            for (key, value) in httpResponse.allHeaderFields {
                if let keyString = key as? String,
                   let valueString = value as? String {
                    responseHeaders[keyString] = valueString
                }
            }
            
            // Log successful response
            RequestLogger.shared.updateResponse(
                method: method,
                path: path,
                requestHeaders: requestHeaders,
                requestBody: requestBody,
                responseStatus: httpResponse.statusCode,
                responseHeaders: responseHeaders,
                responseBody: data,
                startTime: startTime,
                tokenUsed: String(token.prefix(50)) + "..."
            )
            
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
            await sendErrorResponse(502, "Request to upstream failed", on: connection, startTime: startTime, method: method, path: path, error: error.localizedDescription)
        }
    }
    
    func handleStreamingRequest(
        _ request: URLRequest,
        on connection: NWConnection,
        startTime: Date,
        method: String,
        path: String,
        requestHeaders: [String: String],
        requestBody: String?,
        token: String
    ) async {
        let session = URLSession(configuration: .default)
        
        let task = session.dataTask(with: request)
        let delegate = StreamingDelegate(
            connection: connection,
            startTime: startTime,
            method: method,
            path: path,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            token: String(token.prefix(50)) + "..."
        )
        task.delegate = delegate
        task.resume()
        
        // Wait for completion
        await delegate.waitForCompletion()
    }
}

// Updated StreamingDelegate with logging
class StreamingDelegate: NSObject, URLSessionDataDelegate {
    private let connection: NWConnection
    private var headersSent = false
    private let semaphore = DispatchSemaphore(value: 0)
    
    // Logging properties
    private let startTime: Date
    private let method: String
    private let path: String
    private let requestHeaders: [String: String]
    private let requestBody: String?
    private let token: String
    private var responseStatus: Int = 0
    private var responseHeaders: [String: String] = [:]
    private var responseData = Data()
    
    init(connection: NWConnection, startTime: Date, method: String, path: String, requestHeaders: [String: String], requestBody: String?, token: String) {
        self.connection = connection
        self.startTime = startTime
        self.method = method
        self.path = path
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.token = token
    }
    
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse, completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        guard let httpResponse = response as? HTTPURLResponse else {
            completionHandler(.cancel)
            return
        }
        
        responseStatus = httpResponse.statusCode
        
        // Build response headers dictionary for logging
        for (key, value) in httpResponse.allHeaderFields {
            if let keyString = key as? String,
               let valueString = value as? String {
                responseHeaders[keyString] = valueString
            }
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
        // Store data for logging (limit size)
        if responseData.count < 10000 {
            responseData.append(data.prefix(10000 - responseData.count))
        }
        
        // Stream data chunks
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("Send data error: \(error)")
            }
        })
    }
    
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        // Log the completed request
        if let error = error {
            print("Stream error: \(error)")
            RequestLogger.shared.updateResponse(
                method: method,
                path: path,
                requestHeaders: requestHeaders,
                requestBody: requestBody,
                responseStatus: responseStatus,
                responseHeaders: responseHeaders,
                responseBody: nil,
                startTime: startTime,
                tokenUsed: token,
                error: error.localizedDescription
            )
        } else {
            RequestLogger.shared.updateResponse(
                method: method,
                path: path,
                requestHeaders: requestHeaders,
                requestBody: requestBody,
                responseStatus: responseStatus,
                responseHeaders: responseHeaders,
                responseBody: responseData,
                startTime: startTime,
                tokenUsed: token
            )
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