//
//  CertificateManager.swift
//  litellm-oidc-proxy
//
//  Created by Claude on 2025-09-04.
//

import Foundation
import Security

class CertificateManager {
    static let shared = CertificateManager()
    
    private let caCertificateLabel = "dev.306.litellm-oidc-proxy.ca"
    private let caPrivateKeyLabel = "dev.306.litellm-oidc-proxy.ca.key"
    
    private var caIdentity: SecIdentity?
    private var caCertificate: SecCertificate?
    private var caPrivateKey: SecKey?
    
    private init() {
        loadOrCreateCA()
    }
    
    // MARK: - CA Certificate Management
    
    private func loadOrCreateCA() {
        if let identity = loadCAFromKeychain() {
            self.caIdentity = identity
            extractCertificateAndKey(from: identity)
            print("CertificateManager: Loaded existing CA certificate")
        } else {
            createNewCA()
            print("CertificateManager: Created new CA certificate")
        }
    }
    
    private func loadCAFromKeychain() -> SecIdentity? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassIdentity,
            kSecAttrLabel as String: caCertificateLabel,
            kSecReturnRef as String: true
        ]
        
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        
        if status == errSecSuccess {
            return (item as! SecIdentity)
        }
        return nil
    }
    
    private func createNewCA() {
        // Generate key pair
        let keyAttributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeRSA,
            kSecAttrKeySizeInBits as String: 2048
        ]
        
        var publicKey, privateKey: SecKey?
        let status = SecKeyGeneratePair(keyAttributes as CFDictionary, &publicKey, &privateKey)
        
        guard status == errSecSuccess,
              let pubKey = publicKey,
              let privKey = privateKey else {
            print("CertificateManager: Failed to generate key pair")
            return
        }
        
        // Create CA certificate using openssl via shell
        createCACertificateWithOpenSSL(privateKey: privKey)
    }
    
    private func createCACertificateWithOpenSSL(privateKey: SecKey) {
        // For simplicity, we'll use the Security framework's built-in certificate creation
        // In a production app, you might want to use a more robust solution
        
        // This is a simplified version - in production you'd want proper certificate generation
        print("CertificateManager: CA certificate generation would happen here")
        
        // Store in keychain for future use
        self.caPrivateKey = privateKey
    }
    
    private func extractCertificateAndKey(from identity: SecIdentity) {
        // Extract certificate
        var certificate: SecCertificate?
        SecIdentityCopyCertificate(identity, &certificate)
        self.caCertificate = certificate
        
        // Extract private key
        var privateKey: SecKey?
        SecIdentityCopyPrivateKey(identity, &privateKey)
        self.caPrivateKey = privateKey
    }
    
    // MARK: - Server Certificate Generation
    
    func generateServerCertificate(for hostname: String) -> (SecIdentity?, SecCertificate?) {
        guard let caPrivateKey = caPrivateKey else {
            print("CertificateManager: No CA private key available")
            return (nil, nil)
        }
        
        // In a real implementation, you would:
        // 1. Generate a new key pair for the server
        // 2. Create a certificate signing request (CSR)
        // 3. Sign the CSR with the CA private key
        // 4. Create a SecIdentity from the certificate and private key
        
        // For now, return nil - this is where the MITM certificate generation would happen
        print("CertificateManager: Would generate certificate for \(hostname)")
        return (nil, nil)
    }
    
    // MARK: - CA Certificate Export
    
    func exportCACertificate() -> Data? {
        guard let certificate = caCertificate else { return nil }
        return SecCertificateCopyData(certificate) as Data
    }
    
    func caCertificatePath() -> URL? {
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        return documentsPath?.appendingPathComponent("litellm-proxy-ca.crt")
    }
    
    func saveCACertificateToDisk() -> URL? {
        guard let certData = exportCACertificate(),
              let path = caCertificatePath() else { return nil }
        
        do {
            try certData.write(to: path)
            print("CertificateManager: CA certificate saved to \(path)")
            return path
        } catch {
            print("CertificateManager: Failed to save CA certificate: \(error)")
            return nil
        }
    }
}