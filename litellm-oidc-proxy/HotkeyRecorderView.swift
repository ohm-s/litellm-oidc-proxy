//
//  HotkeyRecorderView.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 8/16/25.
//

import SwiftUI
import Carbon

struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var modifiers: UInt
    @Binding var keyCode: UInt32
    
    func makeNSView(context: Context) -> HotkeyRecorderTextField {
        let textField = HotkeyRecorderTextField()
        textField.delegate = context.coordinator
        textField.updateDisplay(modifiers: modifiers, keyCode: keyCode)
        return textField
    }
    
    func updateNSView(_ nsView: HotkeyRecorderTextField, context: Context) {
        nsView.updateDisplay(modifiers: modifiers, keyCode: keyCode)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: HotkeyRecorderView
        
        init(_ parent: HotkeyRecorderView) {
            self.parent = parent
        }
        
        func updateHotkey(modifiers: UInt, keyCode: UInt32) {
            parent.modifiers = modifiers
            parent.keyCode = keyCode
        }
    }
}

class HotkeyRecorderTextField: NSTextField {
    weak var delegate: HotkeyRecorderView.Coordinator?
    private var isRecording = false
    
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        isEditable = false
        isBordered = true
        bezelStyle = .roundedBezel
        alignment = .center
        font = .systemFont(ofSize: 13)
        placeholderString = "Click to record hotkey"
    }
    
    override func mouseDown(with event: NSEvent) {
        if !isRecording {
            isRecording = true
            stringValue = "Press keys..."
            window?.makeFirstResponder(self)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if isRecording {
            // Get modifiers
            let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            var modifierValue: UInt = 0
            
            if modifiers.contains(.command) {
                modifierValue |= UInt(cmdKey)
            }
            if modifiers.contains(.option) {
                modifierValue |= UInt(optionKey)
            }
            if modifiers.contains(.control) {
                modifierValue |= UInt(controlKey)
            }
            if modifiers.contains(.shift) {
                modifierValue |= UInt(shiftKey)
            }
            
            // Get key code
            let keyCode = UInt32(event.keyCode)
            
            // Update the binding
            delegate?.updateHotkey(modifiers: modifierValue, keyCode: keyCode)
            
            // Stop recording
            isRecording = false
            window?.makeFirstResponder(nil)
        } else {
            super.keyDown(with: event)
        }
    }
    
    func updateDisplay(modifiers: UInt, keyCode: UInt32) {
        var parts: [String] = []
        
        // Add modifiers
        if (modifiers & UInt(cmdKey)) != 0 {
            parts.append("⌘")
        }
        if (modifiers & UInt(optionKey)) != 0 {
            parts.append("⌥")
        }
        if (modifiers & UInt(controlKey)) != 0 {
            parts.append("⌃")
        }
        if (modifiers & UInt(shiftKey)) != 0 {
            parts.append("⇧")
        }
        
        // Add key
        if let keyString = keyCodeToString(keyCode) {
            parts.append(keyString)
        }
        
        stringValue = parts.joined(separator: "")
    }
    
    private func keyCodeToString(_ keyCode: UInt32) -> String? {
        // Common key codes
        switch keyCode {
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 36: return "Return"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        case 48: return "Tab"
        case 49: return "Space"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return "Key \(keyCode)"
        }
    }
}