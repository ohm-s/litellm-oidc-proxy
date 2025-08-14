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

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    var statusItem: NSStatusItem!
    var httpServer: HTTPServer!
    var settingsWindow: NSWindow?
    var logViewerWindow: NSWindow?
    var statsLastUpdated: Date?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        httpServer = HTTPServer()
        updateStatusIcon()
        
        if let button = statusItem.button {
            button.action = #selector(showMenu)
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: .settingsChanged, object: nil)
        
        // Check for auto-start
        let settings = AppSettings.shared
        if settings.autoStartProxy && settings.isConfigurationValid {
            // Validate configuration before auto-starting
            Task {
                await validateAndAutoStart()
            }
        }
    }
    
    func updateStatusIcon() {
        if let button = statusItem.button {
            if let image = NSImage(named: "HoliduMenubar") {
                button.image = image
                // Don't use template mode to preserve the blue color
                button.image?.isTemplate = false
                
                // Add a visual indicator when server is not running
                if !httpServer.isRunning {
                    button.alphaValue = 0.5
                } else {
                    button.alphaValue = 1.0
                }
            }
            button.toolTip = httpServer.isRunning ? "LiteLLM OIDC Proxy - Running" : "LiteLLM OIDC Proxy - Stopped"
        }
    }
    
    @objc func settingsChanged() {
        let settings = AppSettings.shared
        httpServer.restart(with: settings.port)
    }
    
    @objc func showMenu() {
        let menu = NSMenu()
        
        let statusTitle = httpServer.isRunning ? "Proxy running on localhost:\(httpServer.currentPort)" : "Proxy stopped"
        menu.addItem(NSMenuItem(title: statusTitle, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let toggleTitle = httpServer.isRunning ? "Stop Proxy" : "Start Proxy"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleServer), keyEquivalent: "")
        menu.addItem(toggleItem)
        
        menu.addItem(NSMenuItem(title: "View Logs...", action: #selector(openLogViewer), keyEquivalent: "l"))
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        
        // Quick Stats section - below Quit
        if httpServer.isRunning {
            menu.addItem(NSMenuItem.separator())
            
            // Stats header with refresh button
            let statsHeaderItem = NSMenuItem()
            let statsHeaderView = NSView(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
            
            let statsTitle = NSTextField(labelWithString: "📊 Quick Stats")
            statsTitle.font = .systemFont(ofSize: 13, weight: .medium)
            statsTitle.frame = NSRect(x: 8, y: 2, width: 120, height: 20)
            statsHeaderView.addSubview(statsTitle)
            
            // Refresh button
            let refreshButton = NSButton(frame: NSRect(x: 180, y: 2, width: 20, height: 20))
            refreshButton.bezelStyle = .texturedRounded
            refreshButton.image = NSImage(systemSymbolName: "arrow.clockwise", accessibilityDescription: "Refresh")
            refreshButton.imagePosition = .imageOnly
            refreshButton.isBordered = false
            refreshButton.target = self
            refreshButton.action = #selector(refreshStats)
            refreshButton.toolTip = "Refresh stats"
            statsHeaderView.addSubview(refreshButton)
            
            // Last updated label
            if let lastUpdated = statsLastUpdated {
                let formatter = RelativeDateTimeFormatter()
                formatter.unitsStyle = .abbreviated
                let relativeTime = formatter.localizedString(for: lastUpdated, relativeTo: Date())
                
                let updatedLabel = NSTextField(labelWithString: relativeTime)
                updatedLabel.font = .systemFont(ofSize: 10)
                updatedLabel.textColor = .secondaryLabelColor
                updatedLabel.frame = NSRect(x: 110, y: 2, width: 70, height: 20)
                updatedLabel.alignment = .right
                statsHeaderView.addSubview(updatedLabel)
            }
            
            statsHeaderItem.view = statsHeaderView
            menu.addItem(statsHeaderItem)
            
            // Get stats
            let logCount = DatabaseManager.shared.getLogCount()
            let dbSize = DatabaseManager.shared.getFormattedDatabaseSize()
            let logger = RequestLogger.shared
            
            // Calculate today's stats
            let calendar = Calendar.current
            let startOfDay = calendar.startOfDay(for: Date())
            let todayLogs = logger.logs.filter { $0.timestamp >= startOfDay }
            let todayCount = todayLogs.count
            let todayErrors = todayLogs.filter { $0.responseStatus >= 400 }.count
            
            // Calculate recent stats
            let recentStats = calculateRecentStats()
            
            // Add stats items with better formatting
            let todayItem = NSMenuItem(title: "  Today: \(todayCount) requests" + (todayErrors > 0 ? " (\(todayErrors) errors)" : ""), action: nil, keyEquivalent: "")
            todayItem.isEnabled = false
            menu.addItem(todayItem)
            
            let totalItem = NSMenuItem(title: "  Total: \(logCount.formatted()) requests", action: nil, keyEquivalent: "")
            totalItem.isEnabled = false
            menu.addItem(totalItem)
            
            let successItem = NSMenuItem(title: "  Success rate: \(recentStats.successRate) (last \(recentStats.sampleSize))", action: nil, keyEquivalent: "")
            successItem.isEnabled = false
            menu.addItem(successItem)
            
            if let avgDuration = recentStats.avgDuration {
                let durationItem = NSMenuItem(title: "  Avg response: \(avgDuration)", action: nil, keyEquivalent: "")
                durationItem.isEnabled = false
                menu.addItem(durationItem)
            }
            
            let dbItem = NSMenuItem(title: "  Database: \(dbSize)", action: nil, keyEquivalent: "")
            dbItem.isEnabled = false
            menu.addItem(dbItem)
            
            // Mark stats as updated
            statsLastUpdated = Date()
        }
        
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }
    
    @objc func toggleServer() {
        if httpServer.isRunning {
            httpServer.stop()
        } else {
            httpServer.start()
        }
        updateStatusIcon()
    }
    
    @objc func refreshStats() {
        // Force refresh logs from database
        RequestLogger.shared.refreshLogs()
        
        // Close and reopen menu to refresh stats
        statusItem.menu = nil
        
        // Small delay to ensure data is loaded
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.showMenu()
        }
    }
    
    @objc func openSettings() {
        if settingsWindow == nil {
            let hostingView = NSHostingView(rootView: SettingsView())
            settingsWindow = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 720),
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
            // Both validations passed, start the server
            DispatchQueue.main.async { [weak self] in
                self?.httpServer.start()
                self?.updateStatusIcon()
                print("Proxy server auto-started successfully")
            }
        case .failure(let error):
            print("Auto-start failed: \(error.localizedDescription)")
        }
    }
    
    private func calculateRecentStats() -> (successRate: String, avgDuration: String?, sampleSize: String) {
        let logger = RequestLogger.shared
        let recentLogs = Array(logger.logs.prefix(100)) // Look at last 100 requests
        
        guard !recentLogs.isEmpty else {
            return (successRate: "N/A", avgDuration: nil, sampleSize: "0")
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
        
        let sampleSize = recentLogs.count == 100 ? "100" : "\(recentLogs.count)"
        
        return (successRate: successRate, avgDuration: avgDurationFormatted, sampleSize: sampleSize)
    }
}
