//
//  LogViewerView.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 7/29/25.
//

import SwiftUI

struct LogViewerView: View {
    @ObservedObject var logger = RequestLogger.shared
    @State private var selectedLog: RequestLog?
    @State private var searchText = ""
    @State private var filterStatus: String = "all"
    @State private var refreshTrigger = UUID()
    
    init() {
        print("LogViewerView: Initialized, current logs: \(RequestLogger.shared.logs.count)")
    }
    
    var filteredLogs: [RequestLog] {
        // Always fetch fresh from database
        let allLogs = DatabaseManager.shared.fetchLogs()
        print("LogViewerView: Fetched \(allLogs.count) logs directly from database")
        
        let filtered = allLogs.filter { log in
            let matchesSearch = searchText.isEmpty || 
                log.path.localizedCaseInsensitiveContains(searchText) ||
                log.method.localizedCaseInsensitiveContains(searchText) ||
                String(log.responseStatus).contains(searchText)
            
            let matchesStatus = filterStatus == "all" || 
                (filterStatus == "success" && (200..<300).contains(log.responseStatus)) ||
                (filterStatus == "error" && log.responseStatus >= 400)
            
            return matchesSearch && matchesStatus
        }
        print("LogViewerView: Filtered logs count: \(filtered.count) from total: \(allLogs.count)")
        if !filtered.isEmpty {
            print("LogViewerView: First log: \(filtered[0].method) \(filtered[0].path)")
        }
        return filtered
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Title Bar
            HStack {
                Text("Request Logs")
                    .font(.title2)
                    .fontWeight(.semibold)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            HSplitView {
                // Left panel - Request list
                VStack(spacing: 0) {
                    // Toolbar
                    HStack {
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search requests...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    .frame(width: 250)
                    
                    Picker("", selection: $filterStatus) {
                        Label("All", systemImage: "list.bullet").tag("all")
                        Label("Success", systemImage: "checkmark.circle").tag("success")
                        Label("Errors", systemImage: "exclamationmark.triangle").tag("error")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 180)
                    
                    Spacer()
                    
                    // Log counter
                    HStack(spacing: 4) {
                        Image(systemName: "doc.text")
                            .foregroundColor(.secondary)
                        Text("\(filteredLogs.count)")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                        if filteredLogs.count != logger.logs.count {
                            Text("of \(logger.logs.count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    
                    Divider()
                        .frame(height: 20)
                    
                    Button(action: { 
                        print("LogViewerView: Refreshing logs from database...")
                        refreshTrigger = UUID() // This will trigger filteredLogs to re-compute
                        
                        // Show alert with most recent log directly from database
                        let freshLogs = DatabaseManager.shared.fetchLogs()
                        print("LogViewerView: Database contains \(freshLogs.count) total logs")
                        if let firstLog = freshLogs.first {
                            let alert = NSAlert()
                            alert.messageText = "Most Recent Log"
                            alert.informativeText = """
                            Method: \(firstLog.method)
                            Path: \(firstLog.path)
                            Status: \(firstLog.responseStatus)
                            Duration: \(firstLog.formattedDuration)
                            Timestamp: \(firstLog.formattedTimestamp)
                            ID: \(firstLog.id.uuidString)
                            
                            Total logs in database: \(freshLogs.count)
                            """
                            alert.alertStyle = .informational
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                        } else {
                            let alert = NSAlert()
                            alert.messageText = "No Logs"
                            alert.informativeText = "No logs found in database. Total count: \(freshLogs.count)"
                            alert.alertStyle = .warning
                            alert.addButton(withTitle: "OK")
                            alert.runModal()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                    
                    Button(action: { logger.clearLogs() }) {
                        Image(systemName: "trash")
                    }
                    .help("Clear all logs")
                    
                    Button(action: exportLogs) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .help("Export logs")
                    
                    // Debug button
                    Button(action: {
                        let alert = NSAlert()
                        alert.messageText = "Debug Info"
                        alert.informativeText = """
                        Total logs: \(logger.logs.count)
                        Filtered logs: \(filteredLogs.count)
                        Filter status: \(filterStatus)
                        Search text: "\(searchText)"
                        
                        First 3 logs:
                        \(logger.logs.prefix(3).map { "\($0.method) \($0.path) - \($0.responseStatus)" }.joined(separator: "\n"))
                        """
                        alert.alertStyle = .informational
                        alert.addButton(withTitle: "OK")
                        alert.runModal()
                    }) {
                        Image(systemName: "info.circle")
                    }
                    .help("Debug info")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Request list with proper scrolling
                ScrollView {
                    VStack(spacing: 0) {
                        if filteredLogs.isEmpty {
                            VStack {
                                Spacer()
                                Text("No logs to display")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .frame(maxHeight: .infinity)
                        } else {
                            ForEach(filteredLogs, id: \.id) { log in
                                RequestRowView(log: log, isSelected: selectedLog?.id == log.id)
                                    .onTapGesture {
                                        selectedLog = log
                                    }
                                
                                Divider()
                                    .opacity(0.5)
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .frame(minWidth: 400, idealWidth: 500, maxWidth: .infinity)
                
                // Right panel - Request details
            if let log = selectedLog {
                RequestDetailView(log: log)
                    .frame(minWidth: 400)
            } else {
                VStack {
                    Text("Select a request to view details")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 900, minHeight: 600)
        
        // Status bar at bottom
        Divider()
        HStack {
                // Success/Error breakdown
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 8, height: 8)
                        Text("\(successCount) successful")
                            .font(.caption)
                    }
                    
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("\(errorCount) errors")
                            .font(.caption)
                    }
                }
                
                Spacer()
                
                // Total database count
                Text("Total logs in database: \(DatabaseManager.shared.getLogCount())")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
    }
    
    var successCount: Int {
        filteredLogs.filter { (200..<300).contains($0.responseStatus) }.count
    }
    
    var errorCount: Int {
        filteredLogs.filter { $0.responseStatus >= 400 }.count
    }
    
    private func exportLogs() {
        let savePanel = NSSavePanel()
        savePanel.nameFieldStringValue = "litellm-proxy-logs.json"
        savePanel.allowedContentTypes = [.json]
        
        if savePanel.runModal() == .OK {
            if let url = savePanel.url {
                let json = logger.exportLogs()
                try? json.write(to: url, atomically: true, encoding: .utf8)
            }
        }
    }
}

struct RequestRowView: View {
    let log: RequestLog
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            // Status indicator with method
            HStack(spacing: 8) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
                
                Text(log.method)
                    .font(.system(size: 13, weight: .medium, design: .monospaced))
                    .foregroundColor(methodColor)
                    .frame(width: 55, alignment: .leading)
            }
            
            // Path
            Text(log.path)
                .font(.system(size: 13))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Status code with background
            Text("\(log.responseStatus)")
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundColor(statusTextColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(statusColor.opacity(0.2))
                .cornerRadius(4)
            
            // Duration
            HStack(spacing: 4) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Text(log.formattedDuration)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            .frame(width: 70, alignment: .trailing)
            
            // Timestamp
            Text(log.formattedTimestamp)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }
    
    var statusColor: Color {
        switch log.responseStatus {
        case 200..<300:
            return .green
        case 300..<400:
            return .yellow
        case 400..<500:
            return .orange
        case 500..<600:
            return .red
        default:
            return .gray
        }
    }
    
    var statusTextColor: Color {
        switch log.responseStatus {
        case 200..<300:
            return Color(red: 0, green: 0.5, blue: 0)
        case 300..<400:
            return Color(red: 0.7, green: 0.7, blue: 0)
        case 400..<500:
            return Color(red: 0.8, green: 0.4, blue: 0)
        case 500..<600:
            return Color(red: 0.7, green: 0, blue: 0)
        default:
            return Color.gray
        }
    }
    
    var methodColor: Color {
        switch log.method {
        case "GET":
            return .blue
        case "POST":
            return .green
        case "PUT", "PATCH":
            return .orange
        case "DELETE":
            return .red
        default:
            return .primary
        }
    }
}

struct RequestDetailView: View {
    let log: RequestLog
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .bottom, spacing: 16) {
                    // Method badge
                    Text(log.method)
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(methodBadgeColor)
                        .cornerRadius(6)
                    
                    // Path
                    Text(log.path)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundColor(.primary)
                        .lineLimit(2)
                    
                    Spacer()
                }
                
                HStack(spacing: 24) {
                    // Status
                    HStack(spacing: 6) {
                        Circle()
                            .fill(statusColor)
                            .frame(width: 12, height: 12)
                        Text("\(log.responseStatus)")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(statusColor)
                    }
                    
                    // Duration
                    HStack(spacing: 6) {
                        Image(systemName: "timer")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(log.formattedDuration)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    
                    // Timestamp
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Text(log.formattedTimestamp)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding(20)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Tabs
            Picker("", selection: $selectedTab) {
                Text("Request").tag(0)
                Text("Response").tag(1)
                Text("Headers").tag(2)
                if log.tokenUsed != nil {
                    Text("Auth").tag(3)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding(.horizontal)
            .padding(.top, 10)
            
            // Content
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    switch selectedTab {
                    case 0:
                        RequestTabView(log: log)
                    case 1:
                        ResponseTabView(log: log)
                    case 2:
                        HeadersTabView(log: log)
                    case 3:
                        AuthTabView(log: log)
                    default:
                        EmptyView()
                    }
                }
                .padding()
            }
        }
    }
    
    var statusColor: Color {
        switch log.responseStatus {
        case 200..<300:
            return .green
        case 300..<400:
            return .yellow
        case 400..<500:
            return .orange
        case 500..<600:
            return .red
        default:
            return .gray
        }
    }
    
    var methodBadgeColor: Color {
        switch log.method {
        case "GET":
            return .blue
        case "POST":
            return .green
        case "PUT", "PATCH":
            return .orange
        case "DELETE":
            return .red
        default:
            return .gray
        }
    }
}

struct RequestTabView: View {
    let log: RequestLog
    
    var formattedBody: String {
        guard let body = log.requestBody else { return "" }
        
        // Try to parse as JSON and format it
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data, options: []),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        
        return body
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if let body = log.requestBody, !body.isEmpty {
                Text("Body")
                    .font(.headline)
                
                ScrollView {
                    Text(formattedBody)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
            } else {
                Text("No request body")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct ResponseTabView: View {
    let log: RequestLog
    
    var formattedBody: String {
        guard let body = log.responseBody else { return "" }
        
        // Try to parse as JSON and format it
        if let data = body.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data, options: []),
           let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
           let prettyString = String(data: prettyData, encoding: .utf8) {
            return prettyString
        }
        
        return body
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if let error = log.error {
                Text("Error")
                    .font(.headline)
                    .foregroundColor(.red)
                
                ScrollView {
                    Text(error)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.3), lineWidth: 1)
                        )
                }
            }
            
            if let body = log.responseBody, !body.isEmpty {
                Text("Body")
                    .font(.headline)
                
                ScrollView {
                    Text(formattedBody)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                        )
                }
            } else {
                Text("No response body")
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct HeadersTabView: View {
    let log: RequestLog
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Request Headers")
                    .font(.headline)
                
                ForEach(log.requestHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack(alignment: .top) {
                        Text(key + ":")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(minWidth: 150, alignment: .trailing)
                        
                        Text(value)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        
                        Spacer()
                    }
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 10) {
                Text("Response Headers")
                    .font(.headline)
                
                ForEach(log.responseHeaders.sorted(by: { $0.key < $1.key }), id: \.key) { key, value in
                    HStack(alignment: .top) {
                        Text(key + ":")
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .frame(minWidth: 150, alignment: .trailing)
                        
                        Text(value)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        
                        Spacer()
                    }
                }
            }
        }
    }
}

struct AuthTabView: View {
    let log: RequestLog
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("OIDC Token Used")
                .font(.headline)
            
            if let token = log.tokenUsed {
                ScrollView(.horizontal) {
                    Text(token)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(5)
                }
            }
        }
    }
}
