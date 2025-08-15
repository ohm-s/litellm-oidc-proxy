//
//  TokenUsageExtractor.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 8/15/25.
//

import Foundation

struct TokenUsage {
    // Core token fields
    var promptTokens: Int?
    var completionTokens: Int?
    var totalTokens: Int?
    
    // Anthropic cache tokens
    var cacheCreationInputTokens: Int?
    var cacheReadInputTokens: Int?
    
    // Cost tracking
    var responseCost: Double?
    var inputCost: Double?
    var outputCost: Double?
    
    // Performance metrics
    var timeToFirstToken: Double?
    var tokensPerSecond: Double?
    
    // Additional metadata
    var litellmCallId: String?
    var usageTier: String?
    var litellmModelId: String?
    var litellmResponseCost: Double?
    var responseDurationMs: Double?
    var attemptedFallbacks: Int?
    var attemptedRetries: Int?
}

class TokenUsageExtractor {
    
    // Extract token usage from non-streaming response
    static func extractFromNonStreamingResponse(
        responseData: Data?,
        responseHeaders: [String: String],
        path: String,
        duration: TimeInterval
    ) -> TokenUsage? {
        var usage = TokenUsage()
        
        // Extract LiteLLM headers (only available in non-streaming)
        usage.litellmCallId = responseHeaders["x-litellm-call-id"]
        usage.litellmModelId = responseHeaders["x-litellm-model-id"]
        
        if let costHeader = responseHeaders["x-litellm-response-cost"],
           let cost = Double(costHeader) {
            usage.litellmResponseCost = cost
        }
        
        if let durationHeader = responseHeaders["x-litellm-response-duration-ms"],
           let durationMs = Double(durationHeader) {
            usage.responseDurationMs = durationMs
        }
        
        if let fallbacksHeader = responseHeaders["x-litellm-attempted-fallbacks"],
           let fallbacks = Int(fallbacksHeader) {
            usage.attemptedFallbacks = fallbacks
        }
        
        if let retriesHeader = responseHeaders["x-litellm-attempted-retries"],
           let retries = Int(retriesHeader) {
            usage.attemptedRetries = retries
        }
        
        // Extract usage from JSON response body
        guard let responseData = responseData,
              let jsonObject = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
            return usage
        }
        
        // Check if it's an OpenAI-style response (/v1/chat/completions)
        if path.contains("/chat/completions") {
            if let usageDict = jsonObject["usage"] as? [String: Any] {
                usage.promptTokens = usageDict["prompt_tokens"] as? Int
                usage.completionTokens = usageDict["completion_tokens"] as? Int
                usage.totalTokens = usageDict["total_tokens"] as? Int
                
                // Calculate tokens per second if we have completion tokens
                if let completionTokens = usage.completionTokens, duration > 0 {
                    usage.tokensPerSecond = Double(completionTokens) / duration
                }
            }
        }
        // Check if it's an Anthropic-style response (/v1/messages)
        else if path.contains("/messages") {
            if let usageDict = jsonObject["usage"] as? [String: Any] {
                // Map Anthropic fields to our standard fields
                usage.promptTokens = usageDict["input_tokens"] as? Int
                usage.completionTokens = usageDict["output_tokens"] as? Int
                
                // Calculate total if not provided
                if let prompt = usage.promptTokens, let completion = usage.completionTokens {
                    usage.totalTokens = prompt + completion
                }
                
                // Anthropic-specific cache fields
                usage.cacheCreationInputTokens = usageDict["cache_creation_input_tokens"] as? Int
                usage.cacheReadInputTokens = usageDict["cache_read_input_tokens"] as? Int
                
                // Calculate tokens per second if we have completion tokens
                if let completionTokens = usage.completionTokens, duration > 0 {
                    usage.tokensPerSecond = Double(completionTokens) / duration
                }
            }
        }
        
        return usage
    }
    
    // Extract token usage from streaming response (to be implemented)
    static func extractFromStreamingResponse(
        streamEvents: [String],
        responseHeaders: [String: String],
        path: String,
        startTime: Date,
        firstTokenTime: Date?
    ) -> TokenUsage? {
        var usage = TokenUsage()
        
        // Extract LiteLLM headers (note: some headers not available in streaming)
        usage.litellmCallId = responseHeaders["x-litellm-call-id"]
        
        // Calculate time to first token if available
        if let firstTokenTime = firstTokenTime {
            usage.timeToFirstToken = firstTokenTime.timeIntervalSince(startTime)
        }
        
        // Check if it's an OpenAI-style response
        if path.contains("/chat/completions") {
            // OpenAI always includes usage in the final chunk before [DONE]
            for event in streamEvents.reversed() {
                if event == "[DONE]" { continue }
                
                if let data = parseSSEData(event),
                   let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let usageDict = jsonObject["usage"] as? [String: Any] {
                    usage.promptTokens = usageDict["prompt_tokens"] as? Int
                    usage.completionTokens = usageDict["completion_tokens"] as? Int
                    usage.totalTokens = usageDict["total_tokens"] as? Int
                    break
                }
            }
        }
        // Check if it's an Anthropic-style response
        else if path.contains("/messages") {
            // Process message_start event for initial usage
            for event in streamEvents {
                if event.hasPrefix("event: message_start") {
                    // Find the corresponding data event
                    if let dataIndex = streamEvents.firstIndex(of: event),
                       dataIndex + 1 < streamEvents.count {
                        let dataEvent = streamEvents[dataIndex + 1]
                        if let data = parseSSEData(dataEvent),
                           let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let message = jsonObject["message"] as? [String: Any],
                           let usageDict = message["usage"] as? [String: Any] {
                            usage.promptTokens = usageDict["input_tokens"] as? Int
                            usage.cacheCreationInputTokens = usageDict["cache_creation_input_tokens"] as? Int
                            usage.cacheReadInputTokens = usageDict["cache_read_input_tokens"] as? Int
                        }
                    }
                }
            }
            
            // Process message_delta events for final output tokens
            for event in streamEvents.reversed() {
                if event.hasPrefix("event: message_delta") {
                    // Find the corresponding data event
                    if let dataIndex = streamEvents.firstIndex(of: event),
                       dataIndex + 1 < streamEvents.count {
                        let dataEvent = streamEvents[dataIndex + 1]
                        if let data = parseSSEData(dataEvent),
                           let jsonObject = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let usageDict = jsonObject["usage"] as? [String: Any],
                           let outputTokens = usageDict["output_tokens"] as? Int {
                            usage.completionTokens = outputTokens
                            
                            // Calculate total
                            if let prompt = usage.promptTokens {
                                usage.totalTokens = prompt + outputTokens
                            }
                            break
                        }
                    }
                }
            }
        }
        
        // Calculate tokens per second if we have completion tokens and duration
        let duration = Date().timeIntervalSince(startTime)
        if let completionTokens = usage.completionTokens, duration > 0 {
            usage.tokensPerSecond = Double(completionTokens) / duration
        }
        
        return usage
    }
    
    // Helper function to parse SSE data
    private static func parseSSEData(_ event: String) -> Data? {
        if event.hasPrefix("data: ") {
            let jsonString = String(event.dropFirst(6))
            return jsonString.data(using: .utf8)
        }
        return nil
    }
}