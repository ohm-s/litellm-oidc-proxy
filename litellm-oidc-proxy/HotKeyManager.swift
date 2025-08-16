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
    private var eventHandler: EventHandlerRef?
    private let hotKeyID = EventHotKeyID(signature: FourCharCode(fromString: "LLOP"), id: 1)
    
    private init() {}
    
    func registerHotKey() {
        // Unregister any existing hotkey first
        unregisterHotKey()
        
        let settings = AppSettings.shared
        guard settings.globalHotkeyEnabled else { return }
        
        // Install event handler
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: OSType(kEventHotKeyPressed))
        let eventHandlerUPP = NewEventHandlerUPP { (nextHandler, event, userData) -> OSStatus in
            HotKeyManager.shared.handleHotKeyPress()
            return noErr
        }
        
        InstallApplicationEventHandler(eventHandlerUPP, 1, &eventType, nil, &eventHandler)
        
        // Register hotkey
        let modifiers = UInt32(settings.globalHotkeyModifiers)
        let keyCode = settings.globalHotkeyKeyCode
        
        RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
    
    func unregisterHotKey() {
        if let hotKey = hotKeyRef {
            UnregisterEventHotKey(hotKey)
            hotKeyRef = nil
        }
        
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
    
    private func handleHotKeyPress() {
        // Post notification to show menu
        NotificationCenter.default.post(name: .showStatusMenu, object: nil)
    }
}

extension Notification.Name {
    static let showStatusMenu = Notification.Name("showStatusMenu")
}

extension FourCharCode {
    init(fromString string: String) {
        precondition(string.count == 4)
        
        var result: FourCharCode = 0
        for char in string.utf8 {
            result = (result << 8) + FourCharCode(char)
        }
        self = result
    }
}