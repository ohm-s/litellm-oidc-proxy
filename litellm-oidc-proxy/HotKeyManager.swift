//
//  HotKeyManager.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 8/16/25.
//

import Cocoa
import Carbon

class HotKeyManager {
    static let shared = HotKeyManager()
    
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandlerRef: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: OSType("LLMP".fourCharCodeValue), id: 1)
    
    private init() {
        setupEventHandler()
    }
    
    private func setupEventHandler() {
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        
        let handler: EventHandlerUPP = { (nextHandler, event, userData) -> OSStatus in
            HotKeyManager.shared.handleHotKeyPress()
            return noErr
        }
        
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &eventSpec, nil, &eventHandlerRef)
    }
    
    func registerHotKey() {
        // Remove any existing hotkey
        unregisterHotKey()
        
        let settings = AppSettings.shared
        guard settings.globalHotkeyEnabled else { return }
        
        // Register the hotkey
        let status = RegisterEventHotKey(
            settings.globalHotkeyKeyCode,
            UInt32(settings.globalHotkeyModifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        
        if status == noErr {
            print("Successfully registered hotkey with keyCode: \(settings.globalHotkeyKeyCode) and modifiers: \(settings.globalHotkeyModifiers)")
        } else {
            print("Failed to register hotkey. Error: \(status)")
        }
    }
    
    func unregisterHotKey() {
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
        }
    }
    
    private func handleHotKeyPress() {
        // Remove debug alert - just show the menu
        DispatchQueue.main.async {
            // Post notification to show menu
            NotificationCenter.default.post(name: .showStatusMenu, object: nil)
        }
    }
    
    deinit {
        unregisterHotKey()
        if let handler = eventHandlerRef {
            RemoveEventHandler(handler)
        }
    }
}

extension Notification.Name {
    static let showStatusMenu = Notification.Name("showStatusMenu")
}

// Helper extension to convert string to FourCharCode
extension String {
    var fourCharCodeValue: FourCharCode {
        var result: FourCharCode = 0
        for char in self.prefix(4) {
            result = (result << 8) + FourCharCode(char.asciiValue ?? 0)
        }
        return result
    }
}