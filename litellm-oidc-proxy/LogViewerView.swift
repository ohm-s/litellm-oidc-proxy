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
            HSplitView {
                // Left panel - Request list
                VStack(spacing: 0) {
                // Toolbar
                HStack {
                    TextField("Search...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 200)
                    
                    Picker("Filter", selection: $filterStatus) {
                        Text("All").tag("all")
                        Text("Success").tag("success")
                        Text("Errors").tag("error")
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 200)
                    
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
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(6)
                    
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
                .padding(10)
                
                Divider()
                
                // Request list - Simple approach
                VStack {
                    if filteredLogs.isEmpty {
                        Spacer()
                        Text("No logs to display")
                            .foregroundColor(.secondary)
                        Spacer()
                    } else {
                        // Just show first 5 logs as text
                        ForEach(filteredLogs.prefix(5), id: \.id) { log in
                            Text("\(log.method) \(log.path) - Status: \(log.responseStatus)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(Color.blue.opacity(0.1))
                                .onTapGesture {
                                    selectedLog = log
                                }
                        }
                        Spacer()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            }
            .frame(minWidth: 400, idealWidth: 500)
            
            Divider()
            
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
        HStack(spacing: 10) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            
            // Method
            Text(log.method)
                .font(.system(.body, design: .monospaced))
                .foregroundColor(.primary)
                .frame(width: 60, alignment: .leading)
            
            // Path
            Text(log.path)
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundColor(.primary)
            
            Spacer()
            
            // Status code
            Text("\(log.responseStatus)")
                .font(.system(.body, design: .monospaced))
                .foregroundColor(statusColor)
            
            // Duration
            Text(log.formattedDuration)
                .font(.caption)
                .foregroundColor(.secondary)
                .frame(width: 60, alignment: .trailing)
            
            // Timestamp
            Text(log.formattedTimestamp)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(isSelected ? Color.accentColor.opacity(0.2) : Color.clear)
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
}

struct RequestDetailView: View {
    let log: RequestLog
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 10) {
                Text("\(log.method) \(log.path)")
                    .font(.title3)
                    .bold()
                
                HStack(spacing: 20) {
                    Label("\(log.responseStatus)", systemImage: "circle.fill")
                        .foregroundColor(statusColor)
                    
                    Label(log.formattedDuration, systemImage: "timer")
                    
                    Label(log.formattedTimestamp, systemImage: "clock")
                }
                .font(.caption)
            }
            .padding()
            
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
}

struct RequestTabView: View {
    let log: RequestLog
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if let body = log.requestBody, !body.isEmpty {
                Text("Body")
                    .font(.headline)
                
                ScrollView(.horizontal) {
                    Text(body)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(5)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if let error = log.error {
                Text("Error")
                    .font(.headline)
                    .foregroundColor(.red)
                
                Text(error)
                    .font(.system(.body, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
                    .background(Color.red.opacity(0.1))
                    .cornerRadius(5)
            }
            
            if let body = log.responseBody, !body.isEmpty {
                Text("Body")
                    .font(.headline)
                
                ScrollView(.horizontal) {
                    Text(body)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(10)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(5)
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