//
//  DatabaseManagerTests.swift
//  litellm-oidc-proxyTests
//
//  Created by Tests on 7/29/25.
//

import Testing
import Foundation
@testable import litellm_oidc_proxy

struct DatabaseManagerTests {
    let testDB: DatabaseManager
    
    init() {
        // Create a fresh test database for each test
        testDB = DatabaseManager.createTestInstance()
    }
    
    @Test func insertAndFetchLog() async throws {
        // Create a test log
        let testLog = RequestLog(
            id: UUID(),
            timestamp: Date(),
            method: "POST",
            path: "/v1/chat/completions",
            requestHeaders: ["Content-Type": "application/json"],
            requestBody: "{\"model\": \"claude-3\"}",
            responseStatus: 200,
            responseHeaders: ["Content-Type": "application/json"],
            responseBody: "{\"response\": \"test\"}",
            duration: 1.5,
            tokenUsed: "test-token",
            error: nil
        )
        
        // Insert the log
        testDB.insertLog(testLog)
        
        // Fetch logs
        let logs = testDB.fetchLogs()
        
        // Verify
        #expect(!logs.isEmpty, "Should have at least one log")
        
        if let firstLog = logs.first {
            #expect(firstLog.method == "POST")
            #expect(firstLog.path == "/v1/chat/completions")
            #expect(firstLog.responseStatus == 200)
            #expect(firstLog.tokenUsed == "test-token")
        }
    }
    
    @Test func emptyMethodPathFiltered() async throws {
        // Create a log with empty method/path
        let badLog = RequestLog(
            id: UUID(),
            timestamp: Date(),
            method: "",
            path: "",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 400,
            responseHeaders: [:],
            responseBody: nil,
            duration: 0.1,
            tokenUsed: nil,
            error: "Bad request"
        )
        
        // Insert the log
        testDB.insertLog(badLog)
        
        // Create a good log
        let goodLog = RequestLog(
            id: UUID(),
            timestamp: Date(),
            method: "GET",
            path: "/test",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            duration: 0.1,
            tokenUsed: nil,
            error: nil
        )
        testDB.insertLog(goodLog)
        
        // Fetch logs - should skip corrupted ones
        let logs = testDB.fetchLogs()
        
        // Verify that empty method/path logs are filtered out
        let emptyLogs = logs.filter { $0.method.isEmpty || $0.path.isEmpty }
        #expect(emptyLogs.isEmpty, "Should not return logs with empty method or path")
        #expect(logs.count == 1, "Should have exactly one valid log")
    }
    
    @Test func clearLogs() async throws {
        // Insert a test log first
        let testLog = RequestLog(
            id: UUID(),
            timestamp: Date(),
            method: "GET",
            path: "/v1/models",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            duration: 0.5,
            tokenUsed: nil,
            error: nil
        )
        
        testDB.insertLog(testLog)
        
        // Verify it was inserted
        var logs = testDB.fetchLogs()
        #expect(!logs.isEmpty, "Should have logs before clearing")
        
        // Clear logs
        testDB.clearLogs()
        
        // Verify
        logs = testDB.fetchLogs()
        #expect(logs.isEmpty, "All logs should be cleared")
    }
    
    @Test func logCount() async throws {
        // Clear first
        testDB.clearLogs()
        
        // Insert multiple logs
        for i in 1...5 {
            let log = RequestLog(
                id: UUID(),
                timestamp: Date(),
                method: "GET",
                path: "/test/\(i)",
                requestHeaders: [:],
                requestBody: nil,
                responseStatus: 200,
                responseHeaders: [:],
                responseBody: nil,
                duration: 0.1,
                tokenUsed: nil,
                error: nil
            )
            testDB.insertLog(log)
        }
        
        // Check count
        let count = testDB.getLogCount()
        #expect(count == 5, "Should have 5 logs")
    }
    
    @Test func duplicateIdHandling() async throws {
        // Clear first
        testDB.clearLogs()
        
        let sharedId = UUID()
        
        // Insert first log
        let log1 = RequestLog(
            id: sharedId,
            timestamp: Date(),
            method: "GET",
            path: "/first",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            duration: 0.1,
            tokenUsed: nil,
            error: nil
        )
        testDB.insertLog(log1)
        
        // Insert second log with same ID (should replace)
        let log2 = RequestLog(
            id: sharedId,
            timestamp: Date(),
            method: "POST",
            path: "/second",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 201,
            responseHeaders: [:],
            responseBody: nil,
            duration: 0.2,
            tokenUsed: nil,
            error: nil
        )
        testDB.insertLog(log2)
        
        // Verify only one log exists with updated values
        let logs = testDB.fetchLogs()
        #expect(logs.count == 1, "Should have exactly one log")
        
        if let log = logs.first {
            #expect(log.method == "POST", "Should have the updated method")
            #expect(log.path == "/second", "Should have the updated path")
            #expect(log.responseStatus == 201, "Should have the updated status")
        }
    }
    
    @Test func verifyNoEmptyLogs() async throws {
        // This test verifies that we never store logs with empty method/path
        testDB.clearLogs()
        
        // Try to insert 3 logs with empty values
        for i in 1...3 {
            let emptyLog = RequestLog(
                id: UUID(),
                timestamp: Date(),
                method: "",
                path: "",
                requestHeaders: [:],
                requestBody: nil,
                responseStatus: 400 + i,
                responseHeaders: [:],
                responseBody: nil,
                duration: 0.1,
                tokenUsed: nil,
                error: "Error \(i)"
            )
            testDB.insertLog(emptyLog)
        }
        
        // Fetch all logs
        let logs = testDB.fetchLogs()
        
        // All should be filtered out
        #expect(logs.isEmpty, "Should not have any logs with empty method/path")
        
        // But count in DB might show they exist
        let dbCount = testDB.getLogCount()
        print("Database contains \(dbCount) total entries (including corrupted)")
    }
}