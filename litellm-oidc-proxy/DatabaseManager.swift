//
//  DatabaseManager.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 7/29/25.
//

import Foundation
import SQLite3

class DatabaseManager {
    static let shared = DatabaseManager()
    static var testInstance: DatabaseManager?
    
    private var db: OpaquePointer?
    private let dbPath: String
    
    private init(isTest: Bool = false) {
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
            try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true, attributes: nil)
            
            dbPath = appDir.appendingPathComponent("requests.db").path
            print("DatabaseManager: Database path: \(dbPath)")
        }
        
        openDatabase()
        createTables()
        
        // Check how many logs exist before cleanup
        let countBefore = getLogCount()
        print("DatabaseManager: Total logs before cleanup: \(countBefore)")
        
        cleanupCorruptedLogs()
        
        // Check how many logs exist after cleanup
        let countAfter = getLogCount()
        print("DatabaseManager: Total logs after cleanup: \(countAfter)")
    }
    
    deinit {
        if db != nil {
            sqlite3_close(db)
        }
    }
    
    static func createTestInstance() -> DatabaseManager {
        let instance = DatabaseManager(isTest: true)
        testInstance = instance
        return instance
    }
    
    private func openDatabase() {
        if sqlite3_open(dbPath, &db) != SQLITE_OK {
            print("DatabaseManager: Unable to open database")
        } else {
            print("DatabaseManager: Database opened successfully")
        }
    }
    
    private func createTables() {
        let createTableString = """
            CREATE TABLE IF NOT EXISTS request_logs (
                id TEXT PRIMARY KEY NOT NULL,
                timestamp REAL NOT NULL,
                method TEXT NOT NULL,
                path TEXT NOT NULL,
                request_headers TEXT,
                request_body TEXT,
                response_status INTEGER NOT NULL,
                response_headers TEXT,
                response_body TEXT,
                duration REAL NOT NULL,
                token_used TEXT,
                error TEXT
            );
            
            CREATE INDEX IF NOT EXISTS idx_timestamp ON request_logs (timestamp DESC);
            CREATE INDEX IF NOT EXISTS idx_status ON request_logs (response_status);
        """
        
        if sqlite3_exec(db, createTableString, nil, nil, nil) != SQLITE_OK {
            print("DatabaseManager: Error creating table: \(String(cString: sqlite3_errmsg(db)))")
        } else {
            print("DatabaseManager: Table created successfully")
        }
    }
    
    func insertLog(_ log: RequestLog) {
        // Don't insert logs with empty method or path
        if log.method.isEmpty || log.path.isEmpty {
            print("DatabaseManager: Skipping insert of log with empty method/path - ID: \(log.id.uuidString)")
            return
        }
        
        let insertSQL = """
            INSERT OR REPLACE INTO request_logs (
                id, timestamp, method, path, request_headers, request_body,
                response_status, response_headers, response_body, duration,
                token_used, error
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """
        
        var statement: OpaquePointer?
        
        if sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK {
            // Convert headers dictionaries to JSON strings
            let requestHeadersJSON = try? JSONSerialization.data(withJSONObject: log.requestHeaders, options: [])
            let requestHeadersString = requestHeadersJSON.flatMap { String(data: $0, encoding: .utf8) }
            
            let responseHeadersJSON = try? JSONSerialization.data(withJSONObject: log.responseHeaders, options: [])
            let responseHeadersString = responseHeadersJSON.flatMap { String(data: $0, encoding: .utf8) }
            
            sqlite3_bind_text(statement, 1, log.id.uuidString, -1, nil)
            sqlite3_bind_double(statement, 2, log.timestamp.timeIntervalSince1970)
            sqlite3_bind_text(statement, 3, log.method, -1, nil)
            sqlite3_bind_text(statement, 4, log.path, -1, nil)
            sqlite3_bind_text(statement, 5, requestHeadersString, -1, nil)
            sqlite3_bind_text(statement, 6, log.requestBody, -1, nil)
            sqlite3_bind_int(statement, 7, Int32(log.responseStatus))
            sqlite3_bind_text(statement, 8, responseHeadersString, -1, nil)
            sqlite3_bind_text(statement, 9, log.responseBody, -1, nil)
            sqlite3_bind_double(statement, 10, log.duration)
            sqlite3_bind_text(statement, 11, log.tokenUsed, -1, nil)
            sqlite3_bind_text(statement, 12, log.error, -1, nil)
            
            if sqlite3_step(statement) == SQLITE_DONE {
                print("DatabaseManager: Log inserted successfully - ID: \(log.id.uuidString)")
                // Force a checkpoint to ensure data is written to disk
                sqlite3_exec(db, "PRAGMA wal_checkpoint(TRUNCATE)", nil, nil, nil)
            } else {
                print("DatabaseManager: Error inserting log: \(String(cString: sqlite3_errmsg(db)))")
            }
        } else {
            print("DatabaseManager: INSERT statement preparation failed: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
    }
    
    func fetchLogs(limit: Int = 1000) -> [RequestLog] {
        let querySQL = "SELECT * FROM request_logs ORDER BY timestamp DESC LIMIT ?"
        var statement: OpaquePointer?
        var logs: [RequestLog] = []
        
        print("DatabaseManager: Fetching logs with limit \(limit)")
        
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            sqlite3_bind_int(statement, 1, Int32(limit))
            
            while sqlite3_step(statement) == SQLITE_ROW {
                let idString = String(cString: sqlite3_column_text(statement, 0))
                let id = UUID(uuidString: idString) ?? UUID()
                let timestamp = Date(timeIntervalSince1970: sqlite3_column_double(statement, 1))
                let method = sqlite3_column_text(statement, 2).map { String(cString: $0) } ?? ""
                let path = sqlite3_column_text(statement, 3).map { String(cString: $0) } ?? ""
                
                // Parse headers from JSON
                var requestHeaders: [String: String] = [:]
                if let headerText = sqlite3_column_text(statement, 4) {
                    let headerString = String(cString: headerText)
                    if let data = headerString.data(using: .utf8),
                       let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                        requestHeaders = headers
                    }
                }
                
                let requestBody = sqlite3_column_text(statement, 5).map { String(cString: $0) }
                let responseStatus = Int(sqlite3_column_int(statement, 6))
                
                var responseHeaders: [String: String] = [:]
                if let headerText = sqlite3_column_text(statement, 7) {
                    let headerString = String(cString: headerText)
                    if let data = headerString.data(using: .utf8),
                       let headers = try? JSONSerialization.jsonObject(with: data) as? [String: String] {
                        responseHeaders = headers
                    }
                }
                
                let responseBody = sqlite3_column_text(statement, 8).map { String(cString: $0) }
                let duration = sqlite3_column_double(statement, 9)
                let tokenUsed = sqlite3_column_text(statement, 10).map { String(cString: $0) }
                let error = sqlite3_column_text(statement, 11).map { String(cString: $0) }
                
                let log = RequestLog(
                    id: id,
                    timestamp: timestamp,
                    method: method,
                    path: path,
                    requestHeaders: requestHeaders,
                    requestBody: requestBody,
                    responseStatus: responseStatus,
                    responseHeaders: responseHeaders,
                    responseBody: responseBody,
                    duration: duration,
                    tokenUsed: tokenUsed,
                    error: error
                )
                
                // Skip logs with empty method or path (corrupted entries)
                if !method.isEmpty && !path.isEmpty {
                    logs.append(log)
                } else {
                    print("DatabaseManager: Skipping corrupted log entry with empty method/path - ID: \(id)")
                }
            }
        } else {
            print("DatabaseManager: SELECT statement preparation failed: \(String(cString: sqlite3_errmsg(db)))")
        }
        
        sqlite3_finalize(statement)
        return logs
    }
    
    func clearLogs() {
        let deleteSQL = "DELETE FROM request_logs"
        
        if sqlite3_exec(db, deleteSQL, nil, nil, nil) == SQLITE_OK {
            print("DatabaseManager: Logs cleared successfully")
        } else {
            print("DatabaseManager: Error clearing logs: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
    
    func cleanupCorruptedLogs() {
        let deleteSQL = "DELETE FROM request_logs WHERE method = '' OR path = '' OR method IS NULL OR path IS NULL"
        
        if sqlite3_exec(db, deleteSQL, nil, nil, nil) == SQLITE_OK {
            let changes = sqlite3_changes(db)
            if changes > 0 {
                print("DatabaseManager: Cleaned up \(changes) corrupted log entries")
            }
        } else {
            print("DatabaseManager: Error cleaning up corrupted logs: \(String(cString: sqlite3_errmsg(db)))")
        }
    }
    
    func getLogCount() -> Int {
        let querySQL = "SELECT COUNT(*) FROM request_logs"
        var statement: OpaquePointer?
        var count = 0
        
        if sqlite3_prepare_v2(db, querySQL, -1, &statement, nil) == SQLITE_OK {
            if sqlite3_step(statement) == SQLITE_ROW {
                count = Int(sqlite3_column_int(statement, 0))
            }
        }
        
        sqlite3_finalize(statement)
        return count
    }
}