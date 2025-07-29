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
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        httpServer = HTTPServer()
        updateStatusIcon()
        
        if let button = statusItem.button {
            button.action = #selector(showMenu)
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(settingsChanged), name: .settingsChanged, object: nil)
    }
    
    func updateStatusIcon() {
        if let button = statusItem.button {
            let imageName = httpServer.isRunning ? "network" : "network.slash"
            button.image = NSImage(systemSymbolName: imageName, accessibilityDescription: "LiteLLM OIDC Proxy")
        }
    }
    
    @objc func settingsChanged() {
        let settings = AppSettings.shared
        httpServer.restart(with: settings.port)
    }
    
    @objc func showMenu() {
        let menu = NSMenu()
        
        let statusTitle = httpServer.isRunning ? "Server running on port \(httpServer.currentPort)" : "Server stopped"
        menu.addItem(NSMenuItem(title: statusTitle, action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let toggleTitle = httpServer.isRunning ? "Stop Server" : "Start Server"
        let toggleItem = NSMenuItem(title: toggleTitle, action: #selector(toggleServer), keyEquivalent: "")
        menu.addItem(toggleItem)
        
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
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 550),
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
    
    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow == settingsWindow {
            settingsWindow = nil
        }
    }
}