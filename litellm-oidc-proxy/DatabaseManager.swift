//
//  DatabaseManager.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 7/29/25.
//

import Foundation
import SQLite

class DatabaseManager {
    static let shared = DatabaseManager()
    static var testInstance: DatabaseManager?
    
    private let db: Connection
    
    // Table definition
    private let logs = Table("request_logs")
    
    // Column definitions
    private let id = Expression<String>("id")
    private let timestamp = Expression<Double>("timestamp")
    private let method = Expression<String>("method")
    private let path = Expression<String>("path")
    private let requestHeaders = Expression<Data?>("request_headers")
    private let requestBody = Expression<String?>("request_body")
    private let responseStatus = Expression<Int?>("response_status")
    private let responseHeaders = Expression<Data?>("response_headers")
    private let responseBody = Expression<String?>("response_body")
    private let duration = Expression<Double?>("duration")
    private let tokenUsed = Expression<String?>("token_used")
    private let error = Expression<String?>("error")
    private let isRequestTruncated = Expression<Bool>("is_request_truncated")
    private let isResponseTruncated = Expression<Bool>("is_response_truncated")
    private let model = Expression<String?>("model")
    
    private init(isTest: Bool = false) {
        do {
            let dbPath: String
            
            if isTest {
                // Use temp directory for tests
                let tempDir = FileManager.default.temporaryDirectory
                dbPath = tempDir.appendingPathComponent("test_requests_\(UUID().uuidString).db").path
                print("DatabaseManager: Test database path: \(dbPath)")
            } else {
                // Create database in Application Support directory
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let appDir = appSupport.appendingPathComponent("litellm-oidc-proxy", isDirectory: true)
                
                // Create directory if it doesn't exist
                try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
                
                dbPath = appDir.appendingPathComponent("requests.db").path
                print("DatabaseManager: Database path: \(dbPath)")
            }
            
            // Create database connection
            db = try Connection(dbPath)
            
            // Run migrations first
            try DatabaseMigrations.migrate(db: db)
            
            // Setup database (creates table if it doesn't exist)
            try setupDatabase()
            
            // Test if we can read from the database
            let count = getLogCount()
            print("DatabaseManager: Total logs in database: \(count)")
            
        } catch {
            fatalError("DatabaseManager: Failed to initialize database: \(error)")
        }
    }
    
    static func createTestInstance() -> DatabaseManager {
        let instance = DatabaseManager(isTest: true)
        testInstance = instance
        return instance
    }
    
    private func setupDatabase() throws {
        // Create table
        try db.run(logs.create(ifNotExists: true) { t in
            t.column(id, primaryKey: true)
            t.column(timestamp)
            t.column(method)
            t.column(path)
            t.column(requestHeaders)
            t.column(requestBody)
            t.column(responseStatus)
            t.column(responseHeaders)
            t.column(responseBody)
            t.column(duration)
            t.column(tokenUsed)
            t.column(error)
            t.column(isRequestTruncated, defaultValue: false)
            t.column(isResponseTruncated, defaultValue: false)
            t.column(model)
        })
        
        // Create indices
        try db.run(logs.createIndex(timestamp, ifNotExists: true))
        try db.run(logs.createIndex(method, path, ifNotExists: true))
    }
    
    // MARK: - Public Methods
    
    func insertLog(_ log: RequestLog) {
        // Don't insert logs with empty method or path
        guard !log.method.isEmpty && !log.path.isEmpty else {
            print("DatabaseManager: Skipping insert of log with empty method/path - ID: \(log.id.uuidString)")
            return
        }
        
        do {
            let headerData = try? JSONEncoder().encode(log.requestHeaders)
            let responseHeaderData = try? JSONEncoder().encode(log.responseHeaders)
            
            let insert = logs.insert(or: .replace,
                id <- log.id.uuidString,
                timestamp <- log.timestamp.timeIntervalSince1970,
                method <- log.method,
                path <- log.path,
                requestHeaders <- headerData,
                requestBody <- log.requestBody,
                responseStatus <- log.responseStatus,
                responseHeaders <- responseHeaderData,
                responseBody <- log.responseBody,
                duration <- log.duration,
                tokenUsed <- log.tokenUsed,
                error <- log.error,
                isRequestTruncated <- log.isRequestTruncated,
                isResponseTruncated <- log.isResponseTruncated,
                model <- log.model
            )
            
            try db.run(insert)
            print("DatabaseManager: Successfully inserted log ID: \(log.id.uuidString)")
            print("  Method: '\(log.method)' Path: '\(log.path)'")
        } catch {
            print("DatabaseManager: Failed to insert log: \(error)")
        }
    }
    
    func updateLog(_ log: RequestLog) {
        do {
            let responseHeaderData = try? JSONEncoder().encode(log.responseHeaders)
            
            let logToUpdate = logs.filter(id == log.id.uuidString)
            try db.run(logToUpdate.update(
                responseStatus <- log.responseStatus,
                responseHeaders <- responseHeaderData,
                responseBody <- log.responseBody,
                duration <- log.duration,
                tokenUsed <- log.tokenUsed,
                error <- log.error,
                isRequestTruncated <- log.isRequestTruncated,
                isResponseTruncated <- log.isResponseTruncated,
                model <- log.model
            ))
            print("DatabaseManager: Successfully updated log ID: \(log.id.uuidString)")
        } catch {
            print("DatabaseManager: Failed to update log: \(error)")
        }
    }
    
    func fetchLogs() -> [RequestLog] {
        return fetchLogs(limit: Int.max, offset: 0)
    }
    
    func fetchLogs(limit: Int = 100, offset: Int = 0) -> [RequestLog] {
        do {
            var fetchedLogs: [RequestLog] = []
            
            let query = logs.order(timestamp.desc).limit(limit, offset: offset)
            for row in try db.prepare(query) {
                let requestHeadersDict = row[requestHeaders].flatMap { data in
                    try? JSONDecoder().decode([String: String].self, from: data)
                } ?? [:]
                
                let responseHeadersDict = row[responseHeaders].flatMap { data in
                    try? JSONDecoder().decode([String: String].self, from: data)
                } ?? [:]
                
                let log = RequestLog(
                    id: UUID(uuidString: row[id]) ?? UUID(),
                    timestamp: Date(timeIntervalSince1970: row[timestamp]),
                    method: row[method],
                    path: row[path],
                    requestHeaders: requestHeadersDict,
                    requestBody: row[requestBody],
                    responseStatus: row[responseStatus] ?? 0,
                    responseHeaders: responseHeadersDict,
                    responseBody: row[responseBody],
                    duration: row[duration] ?? 0,
                    tokenUsed: row[tokenUsed],
                    error: row[error],
                    isRequestTruncated: (try? row.get(isRequestTruncated)) ?? false,
                    isResponseTruncated: (try? row.get(isResponseTruncated)) ?? false,
                    model: (try? row.get(model)) ?? nil
                )
                
                fetchedLogs.append(log)
            }
            
            print("DatabaseManager: Fetched \(fetchedLogs.count) logs from database")
            return fetchedLogs
        } catch {
            print("DatabaseManager: Failed to fetch logs: \(error)")
            return []
        }
    }
    
    func fetchLog(by logId: UUID) -> RequestLog? {
        do {
            let logQuery = logs.filter(id == logId.uuidString)
            
            if let row = try db.pluck(logQuery) {
                let requestHeadersDict = row[requestHeaders].flatMap { data in
                    try? JSONDecoder().decode([String: String].self, from: data)
                } ?? [:]
                
                let responseHeadersDict = row[responseHeaders].flatMap { data in
                    try? JSONDecoder().decode([String: String].self, from: data)
                } ?? [:]
                
                let log = RequestLog(
                    id: UUID(uuidString: row[id]) ?? UUID(),
                    timestamp: Date(timeIntervalSince1970: row[timestamp]),
                    method: row[method],
                    path: row[path],
                    requestHeaders: requestHeadersDict,
                    requestBody: row[requestBody],
                    responseStatus: row[responseStatus] ?? 0,
                    responseHeaders: responseHeadersDict,
                    responseBody: row[responseBody],
                    duration: row[duration] ?? 0,
                    tokenUsed: row[tokenUsed],
                    error: row[error],
                    isRequestTruncated: (try? row.get(isRequestTruncated)) ?? false,
                    isResponseTruncated: (try? row.get(isResponseTruncated)) ?? false,
                    model: (try? row.get(model)) ?? nil
                )
                
                return log
            }
            
            return nil
        } catch {
            print("DatabaseManager: Failed to fetch log by ID: \(error)")
            return nil
        }
    }
    
    func deleteAllLogs() {
        do {
            try db.run(logs.delete())
            print("DatabaseManager: Deleted all logs")
        } catch {
            print("DatabaseManager: Failed to delete all logs: \(error)")
        }
    }
    
    func getLogCount() -> Int {
        do {
            return try db.scalar(logs.count)
        } catch {
            print("DatabaseManager: Failed to get log count: \(error)")
            return 0
        }
    }
    
    func getDatabaseSize() -> Int64 {
        do {
            let dbPath: String
            if DatabaseManager.testInstance != nil {
                // For test instance, return 0
                return 0
            } else {
                let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                let appDir = appSupport.appendingPathComponent("litellm-oidc-proxy", isDirectory: true)
                dbPath = appDir.appendingPathComponent("requests.db").path
            }
            
            let attributes = try FileManager.default.attributesOfItem(atPath: dbPath)
            if let fileSize = attributes[.size] as? Int64 {
                return fileSize
            }
            return 0
        } catch {
            print("DatabaseManager: Failed to get database size: \(error)")
            return 0
        }
    }
    
    func getFormattedDatabaseSize() -> String {
        let size = getDatabaseSize()
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: size)
    }
}