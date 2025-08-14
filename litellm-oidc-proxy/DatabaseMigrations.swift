//
//  DatabaseMigrations.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 8/14/25.
//

import Foundation
import SQLite

struct DatabaseMigrations {
    static let currentVersion = 3
    
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
            // Initial schema - already exists, just marking it
            print("DatabaseMigrations: Version 1 - Initial schema")
            
        case 2:
            // Add truncation columns
            print("DatabaseMigrations: Version 2 - Adding truncation columns")
            try addTruncationColumns(db: db)
            
        case 3:
            // Add model column
            print("DatabaseMigrations: Version 3 - Adding model column")
            try addModelColumn(db: db)
            
        default:
            throw DatabaseError.unknownMigration(version)
        }
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