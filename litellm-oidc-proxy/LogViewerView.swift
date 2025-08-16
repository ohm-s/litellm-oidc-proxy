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
    @State private var databaseSize = DatabaseManager.shared.getFormattedDatabaseSize()
    @State private var logCount = DatabaseManager.shared.getLogCount()
    
    init() {
        print("LogViewerView: Initialized, current logs: \(RequestLogger.shared.logs.count)")
    }
    
    var filteredLogs: [RequestLog] {
        // Use the logger's published logs property which updates automatically
        let filtered = logger.logs.filter { log in
            let matchesSearch = searchText.isEmpty || 
                log.path.localizedCaseInsensitiveContains(searchText) ||
                log.method.localizedCaseInsensitiveContains(searchText) ||
                String(log.responseStatus).contains(searchText)
            
            let matchesStatus = filterStatus == "all" || 
                (filterStatus == "success" && (200..<300).contains(log.responseStatus)) ||
                (filterStatus == "error" && log.responseStatus >= 400)
            
            return matchesSearch && matchesStatus
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
                        logger.refreshLogs()
                        databaseSize = DatabaseManager.shared.getFormattedDatabaseSize()
                        logCount = DatabaseManager.shared.getLogCount()
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                    
                    Button(action: { 
                        logger.clearLogs()
                        databaseSize = DatabaseManager.shared.getFormattedDatabaseSize()
                        logCount = DatabaseManager.shared.getLogCount()
                    }) {
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
                        if filteredLogs.isEmpty && !logger.isLoadingMore {
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
                            
                            // Load more button
                            if logger.hasMoreLogs && searchText.isEmpty && filterStatus == "all" {
                                HStack {
                                    if logger.isLoadingMore {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                            .padding(.trailing, 8)
                                    }
                                    
                                    Button(action: {
                                        logger.loadMoreLogs()
                                        // Update database info after loading more
                                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                            databaseSize = DatabaseManager.shared.getFormattedDatabaseSize()
                                            logCount = DatabaseManager.shared.getLogCount()
                                        }
                                    }) {
                                        Text(logger.isLoadingMore ? "Loading..." : "Load More")
                                            .font(.system(size: 13))
                                            .foregroundColor(.accentColor)
                                    }
                                    .disabled(logger.isLoadingMore)
                                    .buttonStyle(PlainButtonStyle())
                                }
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity)
                                .background(Color(NSColor.controlBackgroundColor))
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
                
                // Database info
                HStack(spacing: 12) {
                    Text("Total logs: \(logCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Divider()
                        .frame(height: 12)
                    
                    Text("Database size: \(databaseSize)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .onAppear {
            // Update database info when view appears
            databaseSize = DatabaseManager.shared.getFormattedDatabaseSize()
            logCount = DatabaseManager.shared.getLogCount()
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
    
    private func calculateTotalTokens(for log: RequestLog) -> Int? {
        // For Anthropic-style responses, calculate total including cache tokens
        if let promptTokens = log.promptTokens,
           let completionTokens = log.completionTokens {
            var total = promptTokens + completionTokens
            
            // Add cache creation tokens if present
            if let cacheCreation = log.cacheCreationInputTokens {
                total += cacheCreation
            }
            
            // Note: Cache read tokens are already included in promptTokens,
            // so we don't add them again to avoid double counting
            
            return total
        }
        
        // Fall back to totalTokens if available
        return log.totalTokens
    }
    
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
            
            // Model badge if available
            if let model = log.model {
                Text(model)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(4)
            }
            
            // Token count badge if available
            if let totalTokens = calculateTotalTokens(for: log), totalTokens > 0 {
                HStack(spacing: 2) {
                    Image(systemName: "number.square")
                        .font(.system(size: 10))
                    Text("\(totalTokens)")
                        .font(.system(size: 11, weight: .medium))
                }
                .foregroundColor(.purple)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(4)
            }
            
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
                    
                    // Model (if available)
                    if let model = log.model {
                        HStack(spacing: 6) {
                            Image(systemName: "cpu")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                            Text(model)
                                .font(.system(size: 14, weight: .medium))
                                .foregroundColor(.primary)
                        }
                    }
                }
                
                // Token usage summary if available
                if log.totalTokens != nil || log.promptTokens != nil || log.completionTokens != nil {
                    HStack(spacing: 20) {
                        if let prompt = log.promptTokens {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.right.square")
                                    .font(.system(size: 11))
                                    .foregroundColor(.blue)
                                Text("\(prompt)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.blue)
                                if let cacheRead = log.cacheReadInputTokens, cacheRead > 0 {
                                    Text("(\(cacheRead) from cache)")
                                        .font(.system(size: 11))
                                        .foregroundColor(.purple)
                                }
                            }
                        }
                        
                        if let completion = log.completionTokens {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.left.square")
                                    .font(.system(size: 11))
                                    .foregroundColor(.green)
                                Text("\(completion)")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.green)
                            }
                        }
                        
                        if let total = log.totalTokens {
                            HStack(spacing: 4) {
                                Image(systemName: "sum")
                                    .font(.system(size: 11))
                                    .foregroundColor(.primary)
                                Text("\(total) total")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                        }
                        
                        if let cacheCreation = log.cacheCreationInputTokens, cacheCreation > 0 {
                            HStack(spacing: 4) {
                                Image(systemName: "plus.square")
                                    .font(.system(size: 11))
                                    .foregroundColor(.orange)
                                Text("\(cacheCreation) to cache")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.orange)
                            }
                        }
                        
                        if let cost = log.litellmResponseCost ?? log.responseCost {
                            HStack(spacing: 4) {
                                Image(systemName: "dollarsign.square")
                                    .font(.system(size: 11))
                                    .foregroundColor(.primary)
                                Text(String(format: "$%.6f", cost))
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.primary)
                            }
                        }
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
                if log.totalTokens != nil || log.litellmCallId != nil {
                    Text("Tokens").tag(4)
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
                    case 4:
                        TokensTabView(log: log)
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
    @State private var isExpanded = false
    @State private var showingJSONViewer = false
    
    private let previewLimit = 1000 // Show first 1000 chars in preview
    private let webViewThreshold = 5000 // Use web view for bodies larger than 5KB
    
    private var isValidJSON: Bool {
        guard !formattedBody.isEmpty else { return false }
        let trimmed = formattedBody.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || 
               (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }
    
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
    
    var displayBody: String {
        if isExpanded || formattedBody.count <= previewLimit {
            return formattedBody
        } else {
            return String(formattedBody.prefix(previewLimit)) + "\n..."
        }
    }
    
    var isLargeBody: Bool {
        formattedBody.count > previewLimit
    }
    
    var shouldUseWebView: Bool {
        formattedBody.count > webViewThreshold
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            if let body = log.requestBody, !body.isEmpty {
                HStack {
                    Text("Body")
                        .font(.headline)
                    
                    if isLargeBody {
                        Text("(\(formattedBody.count) characters)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if shouldUseWebView && !log.isRequestTruncated && isValidJSON {
                        Button(action: {
                            showingJSONViewer = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "safari")
                                    .font(.system(size: 10))
                                Text("View in JSON Viewer")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.accentColor)
                    } else if isLargeBody {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10))
                                Text(isExpanded ? "Show Less" : "Show All")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.accentColor)
                    }
                }
                
                ScrollView {
                    Text(shouldUseWebView ? String(formattedBody.prefix(previewLimit)) + "\n\n[Content too large - use JSON Viewer to see full content]" : displayBody)
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
        .sheet(isPresented: $showingJSONViewer) {
            JSONViewerSheet(
                title: "Request Body - \(log.method) \(log.path)",
                jsonString: formattedBody,
                isPresented: $showingJSONViewer
            )
        }
    }
}

struct ResponseTabView: View {
    let log: RequestLog
    @State private var isExpanded = false
    @State private var showingJSONViewer = false
    @State private var showingStreamingConverter = false
    
    private let previewLimit = 1000 // Show first 1000 chars in preview
    private let webViewThreshold = 5000 // Use web view for bodies larger than 5KB
    
    private var isValidJSON: Bool {
        guard !formattedBody.isEmpty else { return false }
        let trimmed = formattedBody.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed.hasPrefix("{") && trimmed.hasSuffix("}")) || 
               (trimmed.hasPrefix("[") && trimmed.hasSuffix("]"))
    }
    
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
    
    var displayBody: String {
        if isExpanded || formattedBody.count <= previewLimit {
            return formattedBody
        } else {
            return String(formattedBody.prefix(previewLimit)) + "\n..."
        }
    }
    
    var isLargeBody: Bool {
        formattedBody.count > previewLimit
    }
    
    var shouldUseWebView: Bool {
        formattedBody.count > webViewThreshold
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
                HStack {
                    Text("Body")
                        .font(.headline)
                    
                    if isLargeBody {
                        Text("(\(formattedBody.count) characters)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    // Convert streaming response button for v1/messages
                    if log.path.contains("/v1/messages") && 
                       StreamingResponseParser.isAnthropicStreamingResponse(log.responseBody ?? "") {
                        Button(action: {
                            showingStreamingConverter = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                    .font(.system(size: 10))
                                Text("Convert Streaming Response")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.accentColor)
                    }
                    
                    if shouldUseWebView && !log.isResponseTruncated && isValidJSON {
                        Button(action: {
                            showingJSONViewer = true
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: "safari")
                                    .font(.system(size: 10))
                                Text("View in JSON Viewer")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.accentColor)
                    } else if isLargeBody {
                        Button(action: {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded.toggle()
                            }
                        }) {
                            HStack(spacing: 4) {
                                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 10))
                                Text(isExpanded ? "Show Less" : "Show All")
                                    .font(.caption)
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.accentColor)
                    }
                }
                
                ScrollView {
                    Text(shouldUseWebView ? String(formattedBody.prefix(previewLimit)) + "\n\n[Content too large - use JSON Viewer to see full content]" : displayBody)
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
        .sheet(isPresented: $showingJSONViewer) {
            JSONViewerSheet(
                title: "Response Body - \(log.method) \(log.path)",
                jsonString: formattedBody,
                isPresented: $showingJSONViewer
            )
        }
        .sheet(isPresented: $showingStreamingConverter) {
            StreamingResponseConverterSheet(
                title: "Converted Message - \(log.method) \(log.path)",
                sseData: log.responseBody ?? "",
                isPresented: $showingStreamingConverter
            )
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

struct TokensTabView: View {
    let log: RequestLog
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Basic Token Usage
                if log.totalTokens != nil || log.promptTokens != nil || log.completionTokens != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Token Usage")
                            .font(.headline)
                        
                        HStack(spacing: 40) {
                            if let prompt = log.promptTokens {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Prompt")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(prompt)")
                                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            if let completion = log.completionTokens {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Completion")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(completion)")
                                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                                        .foregroundColor(.green)
                                }
                            }
                            
                            if let total = log.totalTokens {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Total")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(total)")
                                        .font(.system(size: 20, weight: .medium, design: .monospaced))
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                
                // Cache Token Usage (Anthropic)
                if log.cacheCreationInputTokens != nil || log.cacheReadInputTokens != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cache Token Usage")
                            .font(.headline)
                        
                        HStack(spacing: 40) {
                            if let cacheCreation = log.cacheCreationInputTokens {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cache Creation")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(cacheCreation)")
                                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                                        .foregroundColor(.orange)
                                }
                            }
                            
                            if let cacheRead = log.cacheReadInputTokens {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Cache Read")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text("\(cacheRead)")
                                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                                        .foregroundColor(.purple)
                                }
                            }
                        }
                        .padding()
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                
                // Cost Information
                if log.responseCost != nil || log.litellmResponseCost != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Cost")
                            .font(.headline)
                        
                        HStack(spacing: 40) {
                            if let cost = log.litellmResponseCost ?? log.responseCost {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Total Cost")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "$%.6f", cost))
                                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                                        .foregroundColor(.primary)
                                }
                            }
                            
                            if let inputCost = log.inputCost {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Input Cost")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "$%.6f", inputCost))
                                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                                        .foregroundColor(.blue)
                                }
                            }
                            
                            if let outputCost = log.outputCost {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Output Cost")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "$%.6f", outputCost))
                                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                                        .foregroundColor(.green)
                                }
                            }
                        }
                        .padding()
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                
                // Performance Metrics
                if log.timeToFirstToken != nil || log.tokensPerSecond != nil || log.responseDurationMs != nil {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Performance")
                            .font(.headline)
                        
                        HStack(spacing: 40) {
                            if let ttft = log.timeToFirstToken {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Time to First Token")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.2f ms", ttft * 1000))
                                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                                        .foregroundColor(.primary)
                                }
                            }
                            
                            if let tps = log.tokensPerSecond {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Tokens/Second")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.1f", tps))
                                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                                        .foregroundColor(.primary)
                                }
                            }
                            
                            if let duration = log.responseDurationMs {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Response Duration")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    Text(String(format: "%.0f ms", duration))
                                        .font(.system(size: 16, weight: .medium, design: .monospaced))
                                        .foregroundColor(.primary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(8)
                    }
                }
                
                // Metadata
                VStack(alignment: .leading, spacing: 10) {
                    Text("Metadata")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if let callId = log.litellmCallId {
                            HStack(alignment: .top) {
                                Text("Call ID:")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 120, alignment: .trailing)
                                
                                Text(callId)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                
                                Spacer()
                            }
                        }
                        
                        if let modelId = log.litellmModelId {
                            HStack(alignment: .top) {
                                Text("Model ID:")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 120, alignment: .trailing)
                                
                                Text(modelId)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                
                                Spacer()
                            }
                        }
                        
                        if let tier = log.usageTier {
                            HStack(alignment: .top) {
                                Text("Usage Tier:")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 120, alignment: .trailing)
                                
                                Text(tier)
                                    .font(.system(.body, design: .monospaced))
                                    .textSelection(.enabled)
                                
                                Spacer()
                            }
                        }
                        
                        if let fallbacks = log.attemptedFallbacks, fallbacks > 0 {
                            HStack(alignment: .top) {
                                Text("Fallbacks:")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 120, alignment: .trailing)
                                
                                Text("\(fallbacks)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.orange)
                                
                                Spacer()
                            }
                        }
                        
                        if let retries = log.attemptedRetries, retries > 0 {
                            HStack(alignment: .top) {
                                Text("Retries:")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .frame(minWidth: 120, alignment: .trailing)
                                
                                Text("\(retries)")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundColor(.orange)
                                
                                Spacer()
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                }
            }
            .padding()
        }
    }
}
