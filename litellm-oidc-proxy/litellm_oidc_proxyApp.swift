//
//  litellm_oidc_proxyApp.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 7/29/25.
//

import SwiftUI
import AppKit

@main
struct litellm_oidc_proxyApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate, ObservableObject {
    var statusItem: NSStatusItem!
    var httpServer: HTTPServer!
    var anthropicServer: AnthropicHTTPServer!
    var settingsWindow: NSWindow?
    var logViewerWindow: NSWindow?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        httpServer = HTTPServer()
        anthropicServer = AnthropicHTTPServer()
        updateStatusIcon()
        
        if let button = statusItem.button {
            button.action = #selector(showMenu)
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: .settingsChanged, object: nil)
        
        // Register global hotkey
        HotKeyManager.shared.registerHotKey()
        
        // Listen for hotkey notification
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(showMenu),
            name: .showStatusMenu,
            object: nil
        )
        
        // Check for auto-start
        let settings = AppSettings.shared
        if settings.autoStartProxy && settings.isConfigurationValid {
            // Validate configuration before auto-starting
            Task {
                await validateAndAutoStart()
            }
        }
        
        // Always auto-start the Anthropic proxy
        anthropicServer.start()
        print("Anthropic proxy auto-started on port \(anthropicServer.currentPort)")
    }
    
    func updateStatusIcon() {
        if let button = statusItem.button {
            if let image = NSImage(named: "HoliduMenubar") {
                button.image = image
                // Don't use template mode to preserve the blue color
                button.image?.isTemplate = false
                
                // Add a visual indicator when server is not running
                if !httpServer.isRunning && !anthropicServer.isRunning {
                    button.alphaValue = 0.5
                } else {
                    button.alphaValue = 1.0
                }
            }
            
            var tooltip = "LiteLLM OIDC Proxy"
            if httpServer.isRunning && anthropicServer.isRunning {
                tooltip += " - Both proxies running"
            } else if httpServer.isRunning {
                tooltip += " - LiteLLM proxy running"
            } else if anthropicServer.isRunning {
                tooltip += " - Anthropic proxy running"
            } else {
                tooltip += " - Stopped"
            }
            button.toolTip = tooltip
        }
    }
    
    @objc func settingsChanged() {
        let settings = AppSettings.shared
        httpServer.restart(with: settings.port)
    }
    
    @objc func showMenu() {
        let menu = NSMenu()
        
        // LiteLLM Proxy Status
        let litellmTitle = httpServer.isRunning ? "LiteLLM Proxy: localhost:\(httpServer.currentPort)" : "LiteLLM Proxy: stopped"
        menu.addItem(NSMenuItem(title: litellmTitle, action: nil, keyEquivalent: ""))
        
        // Anthropic Proxy Status
        let anthropicTitle = anthropicServer.isRunning ? "Anthropic Proxy: localhost:\(anthropicServer.currentPort)" : "Anthropic Proxy: stopped"
        menu.addItem(NSMenuItem(title: anthropicTitle, action: nil, keyEquivalent: ""))
        
        menu.addItem(NSMenuItem.separator())
        
        // LiteLLM Toggle
        let litellmToggleTitle = httpServer.isRunning ? "Stop LiteLLM Proxy" : "Start LiteLLM Proxy"
        let litellmToggleItem = NSMenuItem(title: litellmToggleTitle, action: #selector(toggleServer), keyEquivalent: "")
        menu.addItem(litellmToggleItem)
        
        // Anthropic Toggle
        let anthropicToggleTitle = anthropicServer.isRunning ? "Stop Anthropic Proxy" : "Start Anthropic Proxy"
        let anthropicToggleItem = NSMenuItem(title: anthropicToggleTitle, action: #selector(toggleAnthropicServer), keyEquivalent: "")
        menu.addItem(anthropicToggleItem)
        
        menu.addItem(NSMenuItem(title: "View Logs...", action: #selector(openLogViewer), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        // Quick Stats section - below Quit
        if httpServer.isRunning || anthropicServer.isRunning {
            menu.addItem(NSMenuItem.separator())
            
            // Stats header
            let statsHeaderItem = NSMenuItem(title: "📊 Quick Stats", action: nil, keyEquivalent: "")
            statsHeaderItem.isEnabled = false
            menu.addItem(statsHeaderItem)
            
            // Get stats
            let logCount = DatabaseManager.shared.getLogCount()
            let dbSize = DatabaseManager.shared.getFormattedDatabaseSize()
            
            // Calculate recent stats
            let recentStats = calculateRecentStats()
            
            // Add stats items with better formatting
            let totalItem = NSMenuItem(title: "  Total: \(logCount.formatted()) requests", action: nil, keyEquivalent: "")
            totalItem.isEnabled = false
            menu.addItem(totalItem)
            
            if let avgDuration = recentStats.avgDuration {
                let durationItem = NSMenuItem(title: "  Avg response: \(avgDuration)", action: nil, keyEquivalent: "")
                durationItem.isEnabled = false
                menu.addItem(durationItem)
            }
            
            // Add token stats if available
            if let totalTokens = recentStats.totalTokens {
                let tokenItem = NSMenuItem(title: "  Recent tokens: \(totalTokens.formatted())", action: nil, keyEquivalent: "")
                tokenItem.isEnabled = false
                menu.addItem(tokenItem)
                
                if let avgTokens = recentStats.avgTokens {
                    let avgTokenItem = NSMenuItem(title: "  Avg per request: \(Int(avgTokens).formatted())", action: nil, keyEquivalent: "")
                    avgTokenItem.isEnabled = false
                    menu.addItem(avgTokenItem)
                }
            }
            
            let dbItem = NSMenuItem(title: "  Database: \(dbSize)", action: nil, keyEquivalent: "")
            dbItem.isEnabled = false
            menu.addItem(dbItem)
        }
        
        menu.delegate = self
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
    }
    
    @objc func toggleServer() {
        if httpServer.isRunning {
            httpServer.stop()
        } else {
            httpServer.start()
        }
        updateStatusIcon()
    }
    
    @objc func toggleAnthropicServer() {
        if anthropicServer.isRunning {
            anthropicServer.stop()
        } else {
            anthropicServer.start()
        }
        updateStatusIcon()
    }
    
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let hostingView = NSHostingView(rootView: SettingsView())
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
                styleMask: [.titled, .closable],
                backing: .buffered,
                defer: false
            )
            settingsWindow?.title = "Settings"
            settingsWindow?.center()
            settingsWindow?.contentView = hostingView
            settingsWindow?.isReleasedWhenClosed = false
            settingsWindow?.delegate = self
        }
        
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc func openLogViewer() {
        if logViewerWindow == nil {
            let hostingView = NSHostingView(rootView: LogViewerView())
            logViewerWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1600, height: 900),
                styleMask: [.titled, .closable, .resizable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            logViewerWindow?.title = "Request Logs"
            logViewerWindow?.center()
            logViewerWindow?.contentView = hostingView
            logViewerWindow?.isReleasedWhenClosed = false
            logViewerWindow?.delegate = self
            logViewerWindow?.minSize = NSSize(width: 1200, height: 600)
            logViewerWindow?.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        }
        
        logViewerWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == settingsWindow {
            settingsWindow = nil
        } else if notification.object as? NSWindow == logViewerWindow {
            logViewerWindow = nil
        }
    }
    
    private func validateAndAutoStart() async {
        let settings = AppSettings.shared
        
        // Validate OIDC configuration and test LiteLLM endpoint in one go
        let result = await OIDCClient.testLiteLLMEndpoint(
            keycloakURL: settings.keycloakURL,
            clientId: settings.keycloakClientId,
            clientSecret: settings.keycloakClientSecret,
            litellmEndpoint: settings.litellmEndpoint
        )
        
        switch result {
        case .success(_):
            // Both validations passed, start the LiteLLM proxy
            DispatchQueue.main.async { [weak self] in
                self?.httpServer.start()
                self?.updateStatusIcon()
                print("LiteLLM proxy auto-started successfully")
            }
        case .failure(let error):
            print("Auto-start failed: \(error.localizedDescription)")
        }
    }
    
    private func calculateRecentStats() -> (successRate: String, avgDuration: String?, sampleSize: String, totalTokens: Int?, avgTokens: Double?) {
        let logger = RequestLogger.shared
        let recentLogs = Array(logger.logs.prefix(100)) // Look at last 100 requests
        
        guard !recentLogs.isEmpty else {
            return (successRate: "N/A", avgDuration: nil, sampleSize: "0", totalTokens: nil, avgTokens: nil)
        }
        
        // Calculate success rate
        let successCount = recentLogs.filter { (200..<300).contains($0.responseStatus) }.count
        let rate = Double(successCount) / Double(recentLogs.count) * 100
        let successRate = String(format: "%.1f%%", rate)
        
        // Calculate average duration
        let totalDuration = recentLogs.reduce(0.0) { $0 + $1.duration }
        let avgDuration = totalDuration / Double(recentLogs.count)
        
        let avgDurationFormatted: String
        if avgDuration < 1.0 {
            avgDurationFormatted = String(format: "%.0fms", avgDuration * 1000)
        } else {
            avgDurationFormatted = String(format: "%.1fs", avgDuration)
        }
        
        // Calculate token statistics
        let logsWithTokens = recentLogs.compactMap { log -> Int? in
            return log.totalTokens
        }
        
        let totalTokens: Int? = logsWithTokens.isEmpty ? nil : logsWithTokens.reduce(0, +)
        let avgTokens: Double? = logsWithTokens.isEmpty ? nil : Double(totalTokens!) / Double(logsWithTokens.count)
        
        let sampleSize = recentLogs.count == 100 ? "100" : "\(recentLogs.count)"
        
        return (successRate: successRate, avgDuration: avgDurationFormatted, sampleSize: sampleSize, totalTokens: totalTokens, avgTokens: avgTokens)
    }
    
    // MARK: - NSMenuDelegate
    
    func menuDidClose(_ menu: NSMenu) {
        statusItem.menu = nil
    }
}
