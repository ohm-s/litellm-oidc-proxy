//
//  SettingsView.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 7/29/25.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @State private var portText: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Settings")
                .font(.title2)
                .bold()
            
            GroupBox("Server Configuration") {
                HStack {
                    Text("Port:")
                        .frame(width: 120, alignment: .trailing)
                    TextField("8080", text: $portText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                        .frame(width: 100)
                }
                .padding(.top, 8)
            }
            
            GroupBox("OIDC Keycloak Configuration") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Keycloak URL:")
                            .frame(width: 120, alignment: .trailing)
                        TextField("https://keycloak.example.com", text: $settings.keycloakURL)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    HStack {
                        Text("Client ID:")
                            .frame(width: 120, alignment: .trailing)
                        TextField("client-id", text: $settings.keycloakClientId)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    HStack {
                        Text("Client Secret:")
                            .frame(width: 120, alignment: .trailing)
                        SecureField("client-secret", text: $settings.keycloakClientSecret)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                }
                .padding(.vertical, 8)
            }
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Save") {
                    saveSettings()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 500, height: 350)
        .onAppear {
            portText = String(settings.port)
        }
        .alert("Invalid Settings", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func saveSettings() {
        guard let newPort = Int(portText), newPort > 0, newPort <= 65535 else {
            alertMessage = "Port must be between 1 and 65535"
            showAlert = true
            return
        }
        
        if !settings.keycloakURL.isEmpty {
            guard settings.keycloakURL.starts(with: "http://") || settings.keycloakURL.starts(with: "https://") else {
                alertMessage = "Keycloak URL must start with http:// or https://"
                showAlert = true
                return
            }
        }
        
        settings.port = newPort
        NotificationCenter.default.post(name: .settingsChanged, object: nil)
        dismiss()
    }
}

extension Notification.Name {
    static let settingsChanged = Notification.Name("settingsChanged")
    static let serverToggled = Notification.Name("serverToggled")
}