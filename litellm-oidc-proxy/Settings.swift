//
//  Settings.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 7/29/25.
//

import Foundation

class AppSettings: ObservableObject {
    @Published var port: Int {
        didSet { UserDefaults.standard.set(port, forKey: "serverPort") }
    }
    
    @Published var keycloakURL: String {
        didSet { UserDefaults.standard.set(keycloakURL, forKey: "keycloakURL") }
    }
    
    @Published var keycloakClientId: String {
        didSet { UserDefaults.standard.set(keycloakClientId, forKey: "keycloakClientId") }
    }
    
    @Published var keycloakClientSecret: String {
        didSet {
            if !keycloakClientSecret.isEmpty {
                try? KeychainHelper.save(key: "keycloakClientSecret", value: keycloakClientSecret)
            }
        }
    }
    
    @Published var litellmEndpoint: String {
        didSet { UserDefaults.standard.set(litellmEndpoint, forKey: "litellmEndpoint") }
    }
    
    static let shared = AppSettings()
    
    private init() {
        self.port = UserDefaults.standard.object(forKey: "serverPort") as? Int ?? 8080
        self.keycloakURL = UserDefaults.standard.string(forKey: "keycloakURL") ?? ""
        self.keycloakClientId = UserDefaults.standard.string(forKey: "keycloakClientId") ?? ""
        self.keycloakClientSecret = KeychainHelper.load(key: "keycloakClientSecret") ?? ""
        self.litellmEndpoint = UserDefaults.standard.string(forKey: "litellmEndpoint") ?? ""
    }
}

enum KeychainHelper {
    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else { return }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.litellm-oidc-proxy",
            kSecValueData as String: data
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.unableToSave
        }
    }
    
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecAttrService as String: "com.litellm-oidc-proxy",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &dataTypeRef)
        
        guard status == errSecSuccess,
              let data = dataTypeRef as? Data,
              let value = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return value
    }
    
    enum KeychainError: Error {
        case unableToSave
    }
}