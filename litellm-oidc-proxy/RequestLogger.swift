//
//  RequestLogger.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 7/29/25.
//

import Foundation

struct RequestLog: Identifiable, Codable {
    let id: UUID
    let timestamp: Date
    let method: String
    let path: String
    let requestHeaders: [String: String]
    let requestBody: String?
    let responseStatus: Int
    let responseHeaders: [String: String]
    let responseBody: String?
    let duration: TimeInterval
    let tokenUsed: String?
    let error: String?
    let isRequestTruncated: Bool
    let isResponseTruncated: Bool
    
    init(id: UUID = UUID(), timestamp: Date, method: String, path: String, 
         requestHeaders: [String: String], requestBody: String?, 
         responseStatus: Int, responseHeaders: [String: String], 
         responseBody: String?, duration: TimeInterval, 
         tokenUsed: String?, error: String?,
         isRequestTruncated: Bool = false, isResponseTruncated: Bool = false) {
        self.id = id
        self.timestamp = timestamp
        self.method = method
        self.path = path
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.responseStatus = responseStatus
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.duration = duration
        self.tokenUsed = tokenUsed
        self.error = error
        self.isRequestTruncated = isRequestTruncated
        self.isResponseTruncated = isResponseTruncated
    }
    
    var statusColor: String {
        switch responseStatus {
        case 200..<300:
            return "green"
        case 300..<400:
            return "yellow"
        case 400..<500:
            return "orange"
        case 500..<600:
            return "red"
        default:
            return "gray"
        }
    }
    
    var formattedTimestamp: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: timestamp)
    }
    
    var formattedDuration: String {
        if duration < 1.0 {
            return String(format: "%.0fms", duration * 1000)
        } else {
            return String(format: "%.2fs", duration)
        }
    }
    
    var summary: String {
        "\(method) \(path)"
    }
}

class RequestLogger: ObservableObject {
    static let shared = RequestLogger()
    
    @Published var logs: [RequestLog] = []
    private let database = DatabaseManager.shared
    private let queue = DispatchQueue(label: "com.litellm-oidc-proxy.requestlogger", attributes: .concurrent)
    
    private init() {
        // Load initial logs from database
        refreshLogs()
    }
    
    func refreshLogs() {
        queue.async(flags: .barrier) {
            let fetchedLogs = self.database.fetchLogs()
            DispatchQueue.main.async {
                self.logs = fetchedLogs
                print("RequestLogger: Loaded \(fetchedLogs.count) logs from database")
                // Force UI update
                self.objectWillChange.send()
            }
        }
    }
    
    func logRequest(
        method: String,
        path: String,
        headers: [String],
        body: Data?,
        startTime: Date
    ) -> UUID {
        let requestId = UUID()
        
        // Don't add partial logs - we'll add the complete log when we have the response
        print("RequestLogger: Request started - \(method) \(path)")
        
        return requestId
    }
    
    func updateResponse(
        requestId: UUID? = nil,
        method: String,
        path: String,
        requestHeaders: [String: String],
        requestBody: String?,
        responseStatus: Int,
        responseHeaders: [String: String],
        responseBody: Data?,
        startTime: Date,
        tokenUsed: String? = nil,
        error: String? = nil
    ) {
        // Debug logging
        if method.isEmpty || path.isEmpty {
            print("RequestLogger: WARNING - updateResponse called with empty method/path")
            print("  Method: '\(method)' Path: '\(path)' Status: \(responseStatus)")
        }
        let duration = Date().timeIntervalSince(startTime)
        
        // Check if request body was truncated
        let isRequestTruncated = requestBody?.contains("... (truncated)") ?? false
        
        // Convert response body to string (truncate if enabled and too large)
        var isResponseTruncated = false
        let responseBodyString = responseBody.flatMap { data in
            let settings = AppSettings.shared
            if settings.truncateLogs && data.count > settings.logTruncationLimit {
                isResponseTruncated = true
                return String(data: data.prefix(settings.logTruncationLimit), encoding: .utf8).map { $0 + "\n... (truncated)" }
            } else {
                return String(data: data, encoding: .utf8)
            }
        }
        
        let log = RequestLog(
            timestamp: startTime,
            method: method,
            path: path,
            requestHeaders: requestHeaders,
            requestBody: requestBody,
            responseStatus: responseStatus,
            responseHeaders: responseHeaders,
            responseBody: responseBodyString,
            duration: duration,
            tokenUsed: tokenUsed,
            error: error,
            isRequestTruncated: isRequestTruncated,
            isResponseTruncated: isResponseTruncated
        )
        
        // Additional debug info
        if method.isEmpty || path.isEmpty {
            print("RequestLogger: Creating log with empty method/path:")
            print("  Caller info - check stack trace")
            print("  Request headers: \(requestHeaders)")
            print("  Response status: \(responseStatus)")
            print("  Error: \(error ?? "none")")
        }
        
        queue.async(flags: .barrier) {
            // Insert into database
            self.database.insertLog(log)
            
            // Update in-memory cache
            DispatchQueue.main.async {
                print("RequestLogger: Adding log - \(log.method) \(log.path) - Status: \(log.responseStatus)")
                self.logs.insert(log, at: 0)
                
                // Keep only the last N logs in memory
                if self.logs.count > 1000 {
                    self.logs = Array(self.logs.prefix(1000))
                }
                print("RequestLogger: Total logs in memory: \(self.logs.count)")
            }
        }
    }
    
    func clearLogs() {
        queue.async(flags: .barrier) {
            // Clear database
            self.database.deleteAllLogs()
            
            // Clear in-memory cache
            DispatchQueue.main.async {
                self.logs.removeAll()
                print("RequestLogger: All logs cleared")
            }
        }
    }
    
    func exportLogs() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .iso8601
        
        // Fetch all logs from database for export
        let allLogs = database.fetchLogs()
        
        if let data = try? encoder.encode(allLogs),
           let json = String(data: data, encoding: .utf8) {
            return json
        }
        return "[]"
    }
}