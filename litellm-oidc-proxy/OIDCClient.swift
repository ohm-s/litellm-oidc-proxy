//
//  OIDCClient.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 7/29/25.
//

import Foundation

class OIDCClient {
    
    struct TokenResponse: Codable {
        let access_token: String
        let token_type: String?
        let expires_in: Int?
        let refresh_token: String?
        let scope: String?
    }
    
    struct ErrorResponse: Codable {
        let error: String
        let error_description: String?
    }
    
    enum OIDCError: Error, LocalizedError {
        case invalidURL
        case invalidCredentials
        case networkError(String)
        case serverError(String)
        case decodingError
        case unknownError
        
        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Invalid Keycloak URL"
            case .invalidCredentials:
                return "Invalid client credentials"
            case .networkError(let message):
                return "Network error: \(message)"
            case .serverError(let message):
                return "Server error: \(message)"
            case .decodingError:
                return "Failed to decode response"
            case .unknownError:
                return "Unknown error occurred"
            }
        }
    }
    
    static func validateConfiguration(keycloakURL: String, clientId: String, clientSecret: String) async -> Result<String, OIDCError> {
        // Build token endpoint URL
        guard var urlComponents = URLComponents(string: keycloakURL) else {
            return .failure(.invalidURL)
        }
        
        // Ensure URL ends with /protocol/openid-connect/token
        let path = urlComponents.path
        if !path.contains("/protocol/openid-connect/token") {
            if path.hasSuffix("/") {
                urlComponents.path = path + "protocol/openid-connect/token"
            } else {
                urlComponents.path = path + "/protocol/openid-connect/token"
            }
        }
        
        guard let url = urlComponents.url else {
            return .failure(.invalidURL)
        }
        
        // Prepare request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        
        // Prepare body
        let bodyString = "grant_type=client_credentials&client_id=\(clientId)&client_secret=\(clientSecret)"
        request.httpBody = bodyString.data(using: .utf8)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                return .failure(.unknownError)
            }
            
            if httpResponse.statusCode == 200 {
                // Success - try to decode token
                let decoder = JSONDecoder()
                if let tokenResponse = try? decoder.decode(TokenResponse.self, from: data) {
                    let tokenPreview = String(tokenResponse.access_token.prefix(50))
                    return .success("Successfully obtained token: \(tokenPreview)...")
                } else {
                    return .failure(.decodingError)
                }
            } else {
                // Error - try to decode error response
                let decoder = JSONDecoder()
                if let errorResponse = try? decoder.decode(ErrorResponse.self, from: data) {
                    return .failure(.serverError(errorResponse.error_description ?? errorResponse.error))
                } else if let errorString = String(data: data, encoding: .utf8) {
                    return .failure(.serverError("HTTP \(httpResponse.statusCode): \(errorString)"))
                } else {
                    return .failure(.serverError("HTTP \(httpResponse.statusCode)"))
                }
            }
        } catch {
            return .failure(.networkError(error.localizedDescription))
        }
    }
}