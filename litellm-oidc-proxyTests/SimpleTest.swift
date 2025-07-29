//
//  SimpleTest.swift
//  litellm-oidc-proxyTests
//
//  Created by Tests on 7/29/25.
//

import Testing
import Foundation
@testable import litellm_oidc_proxy

struct SimpleTest {
    
    @Test func basicLogCreation() async throws {
        // Just test that we can create a RequestLog
        let log = RequestLog(
            id: UUID(),
            timestamp: Date(),
            method: "GET",
            path: "/test",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 200,
            responseHeaders: [:],
            responseBody: nil,
            duration: 0.1,
            tokenUsed: nil,
            error: nil
        )
        
        #expect(log.method == "GET")
        #expect(log.path == "/test")
        #expect(log.responseStatus == 200)
    }
    
    @Test func emptyMethodPath() async throws {
        // Test that we can identify empty logs
        let log = RequestLog(
            id: UUID(),
            timestamp: Date(),
            method: "",
            path: "",
            requestHeaders: [:],
            requestBody: nil,
            responseStatus: 400,
            responseHeaders: [:],
            responseBody: nil,
            duration: 0.1,
            tokenUsed: nil,
            error: nil
        )
        
        #expect(log.method.isEmpty)
        #expect(log.path.isEmpty)
    }
}