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
}
