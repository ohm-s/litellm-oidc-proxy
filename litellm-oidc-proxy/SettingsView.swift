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
    @State private var isTesting = false
    @State private var testResult: String = ""
    @State private var testSuccessful = false
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
                    
                    HStack {
                        Spacer()
                            .frame(width: 120)
                        
                        Button(action: testConfiguration) {
                            HStack {
                                if isTesting {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "checkmark.circle")
                                }
                                Text("Test Configuration")
                            }
                        }
                        .disabled(isTesting || settings.keycloakURL.isEmpty || settings.keycloakClientId.isEmpty || settings.keycloakClientSecret.isEmpty)
                        
                        Spacer()
                    }
                    
                    if !testResult.isEmpty {
                        HStack {
                            Spacer()
                                .frame(width: 120)
                            Text(testResult)
                                .foregroundColor(testSuccessful ? .green : .red)
                                .font(.caption)
                                .lineLimit(2)
                        }
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
        .frame(width: 500, height: 400)
        .onAppear {
            portText = String(settings.port)
        }
        .alert("Invalid Settings", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
    }
    
    private func testConfiguration() {
        isTesting = true
        testResult = ""
        
        Task {
            let result = await OIDCClient.validateConfiguration(
                keycloakURL: settings.keycloakURL,
                clientId: settings.keycloakClientId,
                clientSecret: settings.keycloakClientSecret
            )
            
            await MainActor.run {
                isTesting = false
                
                switch result {
                case .success(let message):
                    testResult = message
                    testSuccessful = true
                case .failure(let error):
                    testResult = error.localizedDescription
                    testSuccessful = false
                }
            }
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