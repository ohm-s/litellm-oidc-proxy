//
//  LaunchAtLogin.swift
//  litellm-oidc-proxy
//
//  Created by Assistant on 7/30/25.
//

import Foundation
import ServiceManagement

class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()
    
    @Published var isEnabled: Bool = false {
        didSet {
            if isEnabled != oldValue {
                if isEnabled {
                    enable()
                } else {
                    disable()
                }
                UserDefaults.standard.set(isEnabled, forKey: "launchAtLogin")
            }
        }
    }
    
    private init() {
        // Check current state
        self.isEnabled = UserDefaults.standard.bool(forKey: "launchAtLogin")
        
        // Verify actual state with system
        if #available(macOS 13.0, *) {
            let actualState = SMAppService.mainApp.status == .enabled
            if actualState != isEnabled {
                self.isEnabled = actualState
                UserDefaults.standard.set(actualState, forKey: "launchAtLogin")
            }
        }
    }
    
    private func enable() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.register()
                print("Launch at login enabled")
            } catch {
                print("Failed to enable launch at login: \(error)")
                // Revert the state
                DispatchQueue.main.async {
                    self.isEnabled = false
                }
            }
        } else {
            // For older macOS versions
            SMLoginItemSetEnabled("dev.306.litellm-oidc-proxy" as CFString, true)
        }
    }
    
    private func disable() {
        if #available(macOS 13.0, *) {
            do {
                try SMAppService.mainApp.unregister()
                print("Launch at login disabled")
            } catch {
                print("Failed to disable launch at login: \(error)")
                // Revert the state
                DispatchQueue.main.async {
                    self.isEnabled = true
                }
            }
        } else {
            // For older macOS versions
            SMLoginItemSetEnabled("dev.306.litellm-oidc-proxy" as CFString, false)
        }
    }
    
    func checkStatus() -> Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // Legacy check
            return UserDefaults.standard.bool(forKey: "launchAtLogin")
        }
    }
}