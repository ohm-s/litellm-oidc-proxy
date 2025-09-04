//
//  DatabaseMigrations.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 8/14/25.
//

import Foundation
import SQLite

struct DatabaseMigrations {
    static let currentVersion = 4
    
    static func migrate(db: Connection) throws {
        // Get current version
        let currentDBVersion = try db.scalar("PRAGMA user_version") as? Int64 ?? 0
        
        print("DatabaseMigrations: Current DB version: \(currentDBVersion), Target version: \(currentVersion)")
        
        if currentDBVersion >= currentVersion {
            print("DatabaseMigrations: Database is up to date")
            return
        }
        
        // Begin transaction for safety
        try db.transaction {
            // Run migrations
            for version in Int(currentDBVersion + 1)...currentVersion {
                print("DatabaseMigrations: Running migration to version \(version)")
                try runMigration(version: version, db: db)
            }
            
            // Update version
            try db.run("PRAGMA user_version = \(currentVersion)")
        }
        
        print("DatabaseMigrations: Migration completed successfully")
    }
    
    private static func runMigration(version: Int, db: Connection) throws {
        switch version {
        case 1:
            // Initial schema - create the base table
            print("DatabaseMigrations: Version 1 - Creating initial schema")
            try createInitialSchema(db: db)
            
        case 2:
            // Add truncation columns
            print("DatabaseMigrations: Version 2 - Adding truncation columns")
            try addTruncationColumns(db: db)
            
        case 3:
            // Add model column
            print("DatabaseMigrations: Version 3 - Adding model column")
            try addModelColumn(db: db)
            
        case 4:
            // Add token tracking columns
            print("DatabaseMigrations: Version 4 - Adding token tracking columns")
            try addTokenTrackingColumns(db: db)
            
        default:
            throw DatabaseError.unknownMigration(version)
        }
    }
    
    private static func createInitialSchema(db: Connection) throws {
        // Define table columns using the same structure as DatabaseManager
        let logs = Table("request_logs")
        let id = Expression<UUID>("id")
        let timestamp = Expression<Date>("timestamp")
        let method = Expression<String>("method")
        let path = Expression<String>("path")
        let requestHeaders = Expression<Data?>("request_headers")
        let requestBody = Expression<String?>("request_body")
        let responseStatus = Expression<Int>("response_status")
        let responseHeaders = Expression<Data?>("response_headers")
        let responseBody = Expression<String?>("response_body")
        let duration = Expression<Double>("duration")
        let tokenUsed = Expression<String?>("token_used")
        let error = Expression<String?>("error")
        
        // Create the initial table
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
        })
        
        // Create initial indices
        try db.run(logs.createIndex(timestamp, ifNotExists: true))
        try db.run(logs.createIndex(method, path, ifNotExists: true))
    }
    
    private static func addTruncationColumns(db: Connection) throws {
        // Check if columns already exist
        let tableInfo = try db.prepare("PRAGMA table_info(request_logs)")
        let existingColumns = tableInfo.compactMap { row in
            row[1] as? String
        }
        
        if !existingColumns.contains("is_request_truncated") {
            try db.run("ALTER TABLE request_logs ADD COLUMN is_request_truncated INTEGER DEFAULT 0")
            print("DatabaseMigrations: Added is_request_truncated column")
        }
        
        if !existingColumns.contains("is_response_truncated") {
            try db.run("ALTER TABLE request_logs ADD COLUMN is_response_truncated INTEGER DEFAULT 0")
            print("DatabaseMigrations: Added is_response_truncated column")
        }
    }
    
    private static func addModelColumn(db: Connection) throws {
        // Check if column already exists
        let tableInfo = try db.prepare("PRAGMA table_info(request_logs)")
        let existingColumns = tableInfo.compactMap { row in
            row[1] as? String
        }
        
        if !existingColumns.contains("model") {
            try db.run("ALTER TABLE request_logs ADD COLUMN model TEXT")
            print("DatabaseMigrations: Added model column")
        }
    }
    
    private static func addTokenTrackingColumns(db: Connection) throws {
        // Check if columns already exist
        let tableInfo = try db.prepare("PRAGMA table_info(request_logs)")
        let existingColumns = tableInfo.compactMap { row in
            row[1] as? String
        }
        
        // Core token fields
        if !existingColumns.contains("prompt_tokens") {
            try db.run("ALTER TABLE request_logs ADD COLUMN prompt_tokens INTEGER")
            print("DatabaseMigrations: Added prompt_tokens column")
        }
        
        if !existingColumns.contains("completion_tokens") {
            try db.run("ALTER TABLE request_logs ADD COLUMN completion_tokens INTEGER")
            print("DatabaseMigrations: Added completion_tokens column")
        }
        
        if !existingColumns.contains("total_tokens") {
            try db.run("ALTER TABLE request_logs ADD COLUMN total_tokens INTEGER")
            print("DatabaseMigrations: Added total_tokens column")
        }
        
        // Anthropic cache tokens
        if !existingColumns.contains("cache_creation_input_tokens") {
            try db.run("ALTER TABLE request_logs ADD COLUMN cache_creation_input_tokens INTEGER")
            print("DatabaseMigrations: Added cache_creation_input_tokens column")
        }
        
        if !existingColumns.contains("cache_read_input_tokens") {
            try db.run("ALTER TABLE request_logs ADD COLUMN cache_read_input_tokens INTEGER")
            print("DatabaseMigrations: Added cache_read_input_tokens column")
        }
        
        // Cost tracking
        if !existingColumns.contains("response_cost") {
            try db.run("ALTER TABLE request_logs ADD COLUMN response_cost REAL")
            print("DatabaseMigrations: Added response_cost column")
        }
        
        if !existingColumns.contains("input_cost") {
            try db.run("ALTER TABLE request_logs ADD COLUMN input_cost REAL")
            print("DatabaseMigrations: Added input_cost column")
        }
        
        if !existingColumns.contains("output_cost") {
            try db.run("ALTER TABLE request_logs ADD COLUMN output_cost REAL")
            print("DatabaseMigrations: Added output_cost column")
        }
        
        // Performance metrics
        if !existingColumns.contains("time_to_first_token") {
            try db.run("ALTER TABLE request_logs ADD COLUMN time_to_first_token REAL")
            print("DatabaseMigrations: Added time_to_first_token column")
        }
        
        if !existingColumns.contains("tokens_per_second") {
            try db.run("ALTER TABLE request_logs ADD COLUMN tokens_per_second REAL")
            print("DatabaseMigrations: Added tokens_per_second column")
        }
        
        // Additional metadata
        if !existingColumns.contains("litellm_call_id") {
            try db.run("ALTER TABLE request_logs ADD COLUMN litellm_call_id TEXT")
            print("DatabaseMigrations: Added litellm_call_id column")
        }
        
        if !existingColumns.contains("usage_tier") {
            try db.run("ALTER TABLE request_logs ADD COLUMN usage_tier TEXT")
            print("DatabaseMigrations: Added usage_tier column")
        }
        
        if !existingColumns.contains("litellm_model_id") {
            try db.run("ALTER TABLE request_logs ADD COLUMN litellm_model_id TEXT")
            print("DatabaseMigrations: Added litellm_model_id column")
        }
        
        if !existingColumns.contains("litellm_response_cost") {
            try db.run("ALTER TABLE request_logs ADD COLUMN litellm_response_cost REAL")
            print("DatabaseMigrations: Added litellm_response_cost column")
        }
        
        if !existingColumns.contains("response_duration_ms") {
            try db.run("ALTER TABLE request_logs ADD COLUMN response_duration_ms REAL")
            print("DatabaseMigrations: Added response_duration_ms column")
        }
        
        if !existingColumns.contains("attempted_fallbacks") {
            try db.run("ALTER TABLE request_logs ADD COLUMN attempted_fallbacks INTEGER")
            print("DatabaseMigrations: Added attempted_fallbacks column")
        }
        
        if !existingColumns.contains("attempted_retries") {
            try db.run("ALTER TABLE request_logs ADD COLUMN attempted_retries INTEGER")
            print("DatabaseMigrations: Added attempted_retries column")
        }
    }
}

enum DatabaseError: Error {
    case unknownMigration(Int)
    
    var localizedDescription: String {
        switch self {
        case .unknownMigration(let version):
            return "Unknown migration version: \(version)"
        }
    }
}