//
//  StreamingResponseParser.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 8/14/25.
//

import Foundation

struct StreamingResponseParser {
    
    static func parseAnthropicStreamingResponse(_ streamData: String) -> String? {
        var message: [String: Any] = [:]
        var contentBlocks: [[String: Any]] = []
        var currentContentBlock: [String: Any]?
        var currentBlockIndex: Int = -1
        var usage: [String: Any] = [:]
        
        // Parse SSE format
        let lines = streamData.components(separatedBy: "\n")
        var i = 0
        
        while i < lines.count {
            let line = lines[i].trimmingCharacters(in: .whitespacesAndNewlines)
            
            if line.hasPrefix("event:") {
                let eventType = line.replacingOccurrences(of: "event:", with: "").trimmingCharacters(in: .whitespaces)
                
                // Get the data line
                if i + 1 < lines.count {
                    let dataLine = lines[i + 1]
                    if dataLine.hasPrefix("data:") {
                        let jsonString = dataLine.replacingOccurrences(of: "data:", with: "").trimmingCharacters(in: .whitespaces)
                        
                        if let data = jsonString.data(using: .utf8),
                           let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            
                            switch eventType {
                            case "message_start":
                                if let msg = json["message"] as? [String: Any] {
                                    message["id"] = msg["id"]
                                    message["type"] = msg["type"]
                                    message["role"] = msg["role"]
                                    message["model"] = msg["model"]
                                    message["content"] = []
                                    if let msgUsage = msg["usage"] as? [String: Any] {
                                        usage = msgUsage
                                    }
                                }
                                
                            case "content_block_start":
                                if let contentBlock = json["content_block"] as? [String: Any],
                                   let index = json["index"] as? Int {
                                    currentBlockIndex = index
                                    currentContentBlock = contentBlock
                                    
                                    // Initialize text field if not present
                                    if contentBlock["type"] as? String == "text" && currentContentBlock?["text"] == nil {
                                        currentContentBlock?["text"] = ""
                                    } else if contentBlock["type"] as? String == "tool_use",
                                              let input = contentBlock["input"] as? [String: Any] {
                                        currentContentBlock?["input"] = input
                                    }
                                }
                                
                            case "content_block_delta":
                                if let index = json["index"] as? Int,
                                   let delta = json["delta"] as? [String: Any] {
                                    
                                    print("DEBUG: Processing delta - index: \(index), delta: \(delta)")
                                    
                                    if let deltaType = delta["type"] as? String, deltaType == "text_delta",
                                       let text = delta["text"] as? String {
                                        // Append text to current block
                                        if index == currentBlockIndex, var block = currentContentBlock {
                                            let currentText = block["text"] as? String ?? ""
                                            block["text"] = currentText + text
                                            currentContentBlock = block
                                            print("DEBUG: Updated text to: \(block["text"] ?? "nil")")
                                        } else {
                                            print("Warning: Received text delta for index \(index) but current block index is \(currentBlockIndex)")
                                        }
                                    } else if let partialJson = delta["partial_json"] as? String {
                                        // For tool use, accumulate the JSON
                                        if index == currentBlockIndex {
                                            let currentJson = currentContentBlock?["partial_json"] as? String ?? ""
                                            currentContentBlock?["partial_json"] = currentJson + partialJson
                                        }
                                    }
                                }
                                
                            case "content_block_stop":
                                if let index = json["index"] as? Int,
                                   index == currentBlockIndex,
                                   var block = currentContentBlock {
                                    
                                    print("DEBUG: Stopping block at index \(index), block content: \(block)")
                                    
                                    // For tool use, parse the accumulated JSON
                                    if block["type"] as? String == "tool_use",
                                       let partialJson = block["partial_json"] as? String,
                                       let jsonData = partialJson.data(using: .utf8),
                                       let parsedInput = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] {
                                        block["input"] = parsedInput
                                        block.removeValue(forKey: "partial_json")
                                    }
                                    
                                    // Ensure we have enough space in the array
                                    while contentBlocks.count <= index {
                                        contentBlocks.append([:])
                                    }
                                    contentBlocks[index] = block
                                    print("DEBUG: Saved block to contentBlocks[\(index)]: \(block)")
                                }
                                
                            case "message_delta":
                                if let delta = json["delta"] as? [String: Any] {
                                    if let stopReason = delta["stop_reason"] {
                                        message["stop_reason"] = stopReason
                                    }
                                    if let stopSequence = delta["stop_sequence"] {
                                        message["stop_sequence"] = stopSequence
                                    }
                                }
                                if let deltaUsage = json["usage"] as? [String: Any] {
                                    // Merge usage data
                                    for (key, value) in deltaUsage {
                                        usage[key] = value
                                    }
                                }
                                
                            case "message_stop":
                                // Message is complete
                                break
                                
                            default:
                                break
                            }
                        }
                    }
                    i += 1 // Skip the data line
                }
            }
            i += 1
        }
        
        // Construct final message
        message["content"] = contentBlocks
        if !usage.isEmpty {
            message["usage"] = usage
        }
        
        // Convert to pretty JSON
        if let jsonData = try? JSONSerialization.data(withJSONObject: message, options: [.prettyPrinted, .sortedKeys]),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return nil
    }
    
    static func isAnthropicStreamingResponse(_ response: String) -> Bool {
        // Check if this looks like an Anthropic SSE stream
        let trimmed = response.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.contains("event: message_start") && 
               trimmed.contains("data: {\"type\":\"message_start\"")
    }
}