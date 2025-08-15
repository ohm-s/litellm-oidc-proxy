//
//  Model.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 1/15/25.
//

import Foundation

// MARK: - Models List Response
struct ModelsListResponse: Codable {
    let data: [Model]
    let object: String
}

struct Model: Codable, Identifiable {
    let id: String
    let object: String
    let created: Int
    let ownedBy: String
    let metadata: ModelMetadata
    
    enum CodingKeys: String, CodingKey {
        case id, object, created
        case ownedBy = "owned_by"
        case metadata
    }
}

struct ModelMetadata: Codable {
    let fallbacks: [String]
}

// MARK: - Model Info Response
struct ModelInfoResponse: Codable {
    let data: [ModelInfo]
}

struct ModelInfo: Codable {
    let modelName: String
    let litellmParams: LiteLLMParams
    let modelInfo: DetailedModelInfo
    
    enum CodingKeys: String, CodingKey {
        case modelName = "model_name"
        case litellmParams = "litellm_params"
        case modelInfo = "model_info"
    }
}

struct LiteLLMParams: Codable {
    let model: String
    let useInPassThrough: Bool?
    let useLitellmProxy: Bool?
    let mergeReasoningContentInChoices: Bool?
    let thinking: ThinkingConfig?
    let vertexProject: String?
    let vertexLocation: String?
    let apiBase: String?
    let awsRegionName: String?
    let reasoningEffort: String?
    let extraHeaders: [String: String]?
    
    enum CodingKeys: String, CodingKey {
        case model
        case useInPassThrough = "use_in_pass_through"
        case useLitellmProxy = "use_litellm_proxy"
        case mergeReasoningContentInChoices = "merge_reasoning_content_in_choices"
        case thinking
        case vertexProject = "vertex_project"
        case vertexLocation = "vertex_location"
        case apiBase = "api_base"
        case awsRegionName = "aws_region_name"
        case reasoningEffort = "reasoning_effort"
        case extraHeaders = "extra_headers"
    }
}

struct ThinkingConfig: Codable {
    let type: String
    let budgetTokens: Int?
    
    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }
}

struct DetailedModelInfo: Codable {
    let id: String
    let key: String
    let maxTokens: Int?
    let maxInputTokens: Int?
    let maxOutputTokens: Int?
    let inputCostPerToken: Double?
    let outputCostPerToken: Double?
    let litellmProvider: String
    let mode: String
    let supportsVision: Bool?
    let supportsFunctionCalling: Bool?
    let supportsReasoning: Bool?
    let thinking: String?
    let interleavedThinking: String?
    let supportsPromptCaching: Bool?
    let supportsPdfInput: Bool?
    let supportsWebSearch: Bool?
    let supportsComputerUse: Bool?
    let supportedOpenaiParams: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id, key, mode, thinking
        case maxTokens = "max_tokens"
        case maxInputTokens = "max_input_tokens"
        case maxOutputTokens = "max_output_tokens"
        case inputCostPerToken = "input_cost_per_token"
        case outputCostPerToken = "output_cost_per_token"
        case litellmProvider = "litellm_provider"
        case supportsVision = "supports_vision"
        case supportsFunctionCalling = "supports_function_calling"
        case supportsReasoning = "supports_reasoning"
        case interleavedThinking = "interleaved_thinking"
        case supportsPromptCaching = "supports_prompt_caching"
        case supportsPdfInput = "supports_pdf_input"
        case supportsWebSearch = "supports_web_search"
        case supportsComputerUse = "supports_computer_use"
        case supportedOpenaiParams = "supported_openai_params"
    }
}

// MARK: - Combined Model for Display
struct CombinedModel: Identifiable {
    let id: String
    let displayName: String
    let provider: String
    let capabilities: ModelCapabilities
    let pricing: ModelPricing
    let limits: ModelLimits
    let fallbacks: [String]
    let variants: [ModelInfo]
    
    struct ModelCapabilities {
        let vision: Bool
        let functionCalling: Bool
        let reasoning: Bool
        let thinking: Bool
        let promptCaching: Bool
        let pdfInput: Bool
        let webSearch: Bool
        let computerUse: Bool
        let mode: String
    }
    
    struct ModelPricing {
        let inputCostPerMillionTokens: Double?
        let outputCostPerMillionTokens: Double?
    }
    
    struct ModelLimits {
        let maxInputTokens: Int?
        let maxOutputTokens: Int?
        let totalMaxTokens: Int?
    }
}