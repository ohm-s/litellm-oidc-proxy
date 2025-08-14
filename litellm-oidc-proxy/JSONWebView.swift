//
//  JSONWebView.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 8/13/25.
//

import SwiftUI
import WebKit

struct JSONWebView: NSViewRepresentable {
    let jsonString: String
    let isDarkMode: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground") // Make background transparent
        return webView
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        // Navigation delegate methods can be added here if needed
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        let html = generateHTML(for: jsonString, isDarkMode: isDarkMode)
        webView.loadHTMLString(html, baseURL: nil)
    }
    
    private func escapeJSONForJavaScript(_ json: String) -> String {
        // Handle empty or invalid JSON
        guard !json.isEmpty else {
            return "'{}'"
        }
        
        // Try to validate the JSON first
        if let data = json.data(using: .utf8),
           let _ = try? JSONSerialization.jsonObject(with: data, options: []) {
            // Valid JSON - escape for JavaScript string literal
            let escaped = json
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
                .replacingOccurrences(of: "\r", with: "\\r")
                .replacingOccurrences(of: "\t", with: "\\t")
            return "'\(escaped)'"
        } else {
            // Invalid JSON - return empty object
            return "'{}'"
        }
    }
    
    private func generateHTML(for json: String, isDarkMode: Bool) -> String {
        let backgroundColor = isDarkMode ? "#1e1e1e" : "#ffffff"
        let textColor = isDarkMode ? "#d4d4d4" : "#333333"
        
        // Theme configuration for json-formatter-js
        let theme = isDarkMode ? "dark" : ""
        
        return """
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
            <link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/json-formatter-js@2.5.23/dist/json-formatter.min.css">
            <style>
                body {
                    font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace;
                    font-size: 13px;
                    margin: 0;
                    padding: 20px;
                    background-color: \(backgroundColor);
                    color: \(textColor);
                }
                
                /* Toolbar */
                .toolbar {
                    position: sticky;
                    top: 0;
                    background-color: \(backgroundColor);
                    padding: 10px 0;
                    margin-bottom: 20px;
                    border-bottom: 1px solid \(isDarkMode ? "#333333" : "#e0e0e0");
                    z-index: 100;
                }
                
                .toolbar button {
                    background-color: \(isDarkMode ? "#2d2d2d" : "#f0f0f0");
                    color: \(textColor);
                    border: 1px solid \(isDarkMode ? "#444444" : "#cccccc");
                    padding: 5px 15px;
                    margin-right: 10px;
                    border-radius: 4px;
                    cursor: pointer;
                    font-size: 12px;
                    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Segoe UI', sans-serif;
                }
                
                .toolbar button:hover {
                    background-color: \(isDarkMode ? "#3d3d3d" : "#e0e0e0");
                }
                
                .error {
                    color: #ff6b6b;
                    padding: 20px;
                    background-color: \(isDarkMode ? "#2d1515" : "#ffe0e0");
                    border-radius: 4px;
                    margin: 20px 0;
                }
                
                /* Override json-formatter styles for better integration */
                .json-formatter-row {
                    font-family: 'SF Mono', Monaco, 'Cascadia Code', 'Roboto Mono', Consolas, 'Courier New', monospace !important;
                    font-size: 13px !important;
                    line-height: 1.5 !important;
                }
                
                /* Dark theme overrides */
                \(isDarkMode ? """
                .json-formatter-dark.json-formatter-row {
                    background-color: transparent !important;
                }
                
                .json-formatter-dark.json-formatter-row .json-formatter-key {
                    color: #9cdcfe !important;
                }
                
                .json-formatter-dark.json-formatter-row .json-formatter-string {
                    color: #ce9178 !important;
                }
                
                .json-formatter-dark.json-formatter-row .json-formatter-number {
                    color: #b5cea8 !important;
                }
                
                .json-formatter-dark.json-formatter-row .json-formatter-boolean {
                    color: #569cd6 !important;
                }
                
                .json-formatter-dark.json-formatter-row .json-formatter-null {
                    color: #569cd6 !important;
                }
                
                .json-formatter-dark.json-formatter-row .json-formatter-toggler-link {
                    color: #808080 !important;
                }
                """ : "")
            </style>
            <script src="https://cdn.jsdelivr.net/npm/json-formatter-js@2.5.23/dist/json-formatter.umd.min.js" 
                    onerror="console.error('Failed to load JSONFormatter from CDN')"></script>
        </head>
        <body>
            <div class="toolbar">
                <button onclick="expandAll()">Expand All</button>
                <button onclick="collapseAll()">Collapse All</button>
                <button onclick="expandToLevel(1)">Level 1</button>
                <button onclick="expandToLevel(2)">Level 2</button>
                <button onclick="expandToLevel(3)">Level 3</button>
            </div>
            <div id="json-container"></div>
            
            <script>
                let formatter;
                const jsonString = \(escapeJSONForJavaScript(json));
                
                function displayJSON() {
                    try {
                        const jsonData = JSON.parse(jsonString);
                        
                        // Clear any existing content
                        document.getElementById('json-container').innerHTML = '';
                        
                        // Check if JSONFormatter is loaded
                        if (typeof JSONFormatter === 'undefined') {
                            // Fallback: display formatted JSON as text
                            const prettyJSON = JSON.stringify(jsonData, null, 2);
                            document.getElementById('json-container').innerHTML = '<pre style="overflow: auto; padding: 20px;">' + escapeHtml(prettyJSON) + '</pre>';
                            return;
                        }
                        
                        // Create formatter with all levels expanded initially
                        formatter = new JSONFormatter(jsonData, Infinity, {
                            theme: '\(theme)',
                            animateOpen: true,
                            animateClose: true,
                            hoverPreviewEnabled: true,
                            hoverPreviewArrayCount: 100,
                            hoverPreviewFieldCount: 5
                        });
                        
                        document.getElementById('json-container').appendChild(formatter.render());
                    } catch (e) {
                        document.getElementById('json-container').innerHTML = '<div class="error">Error: ' + e.message + '</div>';
                    }
                }
                
                function escapeHtml(text) {
                    const div = document.createElement('div');
                    div.textContent = text;
                    return div.innerHTML;
                }
                
                // Wait for page to load and JSONFormatter library
                if (document.readyState === 'loading') {
                    document.addEventListener('DOMContentLoaded', displayJSON);
                } else {
                    // Try immediately if DOM is ready
                    displayJSON();
                    // Also try after a short delay in case library is still loading
                    if (typeof JSONFormatter === 'undefined') {
                        setTimeout(displayJSON, 500);
                    }
                }
                
                function expandAll() {
                    if (formatter) {
                        formatter.openAtDepth(Infinity);
                    }
                }
                
                function collapseAll() {
                    if (formatter) {
                        formatter.openAtDepth(0);
                    }
                }
                
                function expandToLevel(level) {
                    if (formatter) {
                        formatter.openAtDepth(level);
                    }
                }
            </script>
        </body>
        </html>
        """
    }
}

struct JSONViewerSheet: View {
    let title: String
    let jsonString: String
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    // Copy to clipboard
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(jsonString, forType: .string)
                }) {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(PlainButtonStyle())
                .help("Copy to clipboard")
                
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // JSON content
            JSONWebView(jsonString: jsonString, isDarkMode: colorScheme == .dark)
                .frame(minWidth: 600, minHeight: 400)
        }
        .frame(width: 1400, height: 900)
    }
}
