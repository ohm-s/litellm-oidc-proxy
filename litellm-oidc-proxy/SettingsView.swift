//
//  SettingsView.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 7/29/25.
//

import SwiftUI

struct SettingsView: View {
    @StateObject private var settings = AppSettings.shared
    @StateObject private var launchAtLogin = LaunchAtLogin.shared
    @State private var portText: String = ""
    @State private var showAlert = false
    @State private var alertMessage = ""
    @State private var isTesting = false
    @State private var testResult: String = ""
    @State private var testSuccessful = false
    @State private var isTestingEndpoint = false
    @State private var endpointTestResult: String = ""
    @State private var endpointTestSuccessful = false
    @State private var showModelsPopover = false
    @State private var availableModels: [String] = []
    @State private var showModelsExplorer = false
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
            
            GroupBox("LiteLLM Configuration") {
                VStack(spacing: 12) {
                    HStack {
                        Text("Endpoint URL:")
                            .frame(width: 120, alignment: .trailing)
                        TextField("https://litellm.example.com", text: $settings.litellmEndpoint)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    
                    HStack {
                        Spacer()
                            .frame(width: 120)
                        
                        Button(action: testEndpoint) {
                            HStack {
                                if isTestingEndpoint {
                                    ProgressView()
                                        .scaleEffect(0.8)
                                        .frame(width: 16, height: 16)
                                } else {
                                    Image(systemName: "list.bullet.circle")
                                }
                                Text("Test Endpoint")
                            }
                        }
                        .disabled(isTestingEndpoint || settings.litellmEndpoint.isEmpty || settings.keycloakURL.isEmpty || settings.keycloakClientId.isEmpty || settings.keycloakClientSecret.isEmpty)
                        .popover(isPresented: $showModelsPopover) {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Available Models (\(availableModels.count))")
                                    .font(.headline)
                                    .padding(.bottom, 5)
                                
                                ScrollView {
                                    VStack(alignment: .leading, spacing: 5) {
                                        ForEach(availableModels, id: \.self) { model in
                                            Text(model)
                                                .font(.system(.body, design: .monospaced))
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 2)
                                                .background(Color.gray.opacity(0.1))
                                                .cornerRadius(4)
                                        }
                                    }
                                }
                                .frame(maxHeight: 300)
                            }
                            .padding()
                            .frame(width: 400)
                        }
                        
                        Button(action: {
                            showModelsExplorer = true
                        }) {
                            HStack {
                                Image(systemName: "list.bullet.rectangle")
                                Text("Models Explorer")
                            }
                        }
                        .disabled(settings.litellmEndpoint.isEmpty)
                        
                        Spacer()
                    }
                    
                    if !endpointTestResult.isEmpty {
                        HStack {
                            Spacer()
                                .frame(width: 120)
                            Text(endpointTestResult)
                                .foregroundColor(endpointTestSuccessful ? .green : .red)
                                .font(.caption)
                                .lineLimit(2)
                        }
                    }
                }
                .padding(.vertical, 8)
            }
            
            GroupBox("Proxy Settings") {
                VStack(spacing: 12) {
                    HStack {
                        Toggle("Auto-start proxy server", isOn: $settings.autoStartProxy)
                            .disabled(!settings.isConfigurationValid || !testSuccessful || !endpointTestSuccessful)
                        Spacer()
                    }
                    
                    if !settings.isConfigurationValid {
                        Text("Auto-start requires valid OIDC and LiteLLM configuration")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if !testSuccessful || !endpointTestSuccessful {
                        Text("Auto-start requires successful configuration tests")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.vertical, 8)
            }
            
            GroupBox("Logging Settings") {
                VStack(spacing: 12) {
                    HStack {
                        Toggle("Truncate large request/response bodies", isOn: $settings.truncateLogs)
                        Spacer()
                    }
                    
                    if settings.truncateLogs {
                        HStack {
                            Text("Truncation limit (characters):")
                                .frame(width: 180, alignment: .trailing)
                            TextField("10000", value: $settings.logTruncationLimit, format: .number)
                                .frame(width: 100)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                            Spacer()
                        }
                        
                        Text("Large bodies will be truncated to save database space")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Warning: Storing full request/response bodies may use significant disk space")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.vertical, 8)
            }
            
            GroupBox("System Settings") {
                VStack(spacing: 12) {
                    HStack {
                        Toggle("Launch at login", isOn: $launchAtLogin.isEnabled)
                        Spacer()
                    }
                    
                    Text("Start LiteLLM OIDC Proxy automatically when you log in to your Mac")
                        .font(.caption)
                        .foregroundColor(.secondary)
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
        .frame(width: 500, height: 820)
        .onAppear {
            portText = String(settings.port)
        }
        .alert("Invalid Settings", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(alertMessage)
        }
        .sheet(isPresented: $showModelsExplorer) {
            ModelsExplorerView()
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
    
    private func testEndpoint() {
        isTestingEndpoint = true
        endpointTestResult = ""
        availableModels = []
        
        Task {
            let result = await OIDCClient.testLiteLLMEndpoint(
                keycloakURL: settings.keycloakURL,
                clientId: settings.keycloakClientId,
                clientSecret: settings.keycloakClientSecret,
                litellmEndpoint: settings.litellmEndpoint
            )
            
            await MainActor.run {
                isTestingEndpoint = false
                
                switch result {
                case .success(let models):
                    availableModels = models
                    endpointTestResult = "Successfully fetched \(models.count) models"
                    endpointTestSuccessful = true
                    showModelsPopover = true
                case .failure(let error):
                    endpointTestResult = error.localizedDescription
                    endpointTestSuccessful = false
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
        
        if !settings.litellmEndpoint.isEmpty {
            guard settings.litellmEndpoint.starts(with: "http://") || settings.litellmEndpoint.starts(with: "https://") else {
                alertMessage = "LiteLLM endpoint must start with http:// or https://"
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