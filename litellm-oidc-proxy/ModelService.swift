//
//  ModelService.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 1/15/25.
//

import Foundation

@MainActor
class ModelService: ObservableObject {
    @Published var combinedModels: [CombinedModel] = []
    @Published var isLoading = false
    @Published var error: String?
    
    private let baseURL: String
    
    init(baseURL: String = "http://localhost:9000") {
        self.baseURL = baseURL
    }
    
    func fetchModels() async {
        isLoading = true
        error = nil
        
        do {
            // Fetch both endpoints in parallel
            async let modelsListTask = fetchModelsList()
            async let modelInfoTask = fetchModelInfo()
            
            let (modelsList, modelInfo) = try await (modelsListTask, modelInfoTask)
            
            // Combine the data
            self.combinedModels = combineModelData(models: modelsList, modelInfo: modelInfo)
        } catch {
            self.error = error.localizedDescription
        }
        
        isLoading = false
    }
    
    private func fetchModelsList() async throws -> [Model] {
        let url = URL(string: "\(baseURL)/v1/models?include_metadata=true")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ModelsListResponse.self, from: data)
        return response.data
    }
    
    private func fetchModelInfo() async throws -> [ModelInfo] {
        let url = URL(string: "\(baseURL)/v1/model/info")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let response = try JSONDecoder().decode(ModelInfoResponse.self, from: data)
        return response.data
    }
    
    private func combineModelData(models: [Model], modelInfo: [ModelInfo]) -> [CombinedModel] {
        // Group model info by base model name
        var modelGroups: [String: [ModelInfo]] = [:]
        
        for info in modelInfo {
            let baseName = extractBaseModelName(from: info.modelName)
            if modelGroups[baseName] == nil {
                modelGroups[baseName] = []
            }
            modelGroups[baseName]?.append(info)
        }
        
        // Create combined models
        var combined: [CombinedModel] = []
        
        for model in models {
            let variants = modelGroups[model.id] ?? []
            
            // Find the primary variant (prefer one without special suffixes)
            let primaryVariant = findPrimaryVariant(variants: variants, modelId: model.id)
            
            // Extract capabilities from primary variant
            let capabilities = primaryVariant.map { variant in
                CombinedModel.ModelCapabilities(
                    vision: variant.modelInfo.supportsVision ?? false,
                    functionCalling: variant.modelInfo.supportsFunctionCalling ?? false,
                    reasoning: variant.modelInfo.supportsReasoning ?? false,
                    thinking: variant.modelInfo.thinking == "supported",
                    promptCaching: variant.modelInfo.supportsPromptCaching ?? false,
                    pdfInput: variant.modelInfo.supportsPdfInput ?? false,
                    webSearch: variant.modelInfo.supportsWebSearch ?? false,
                    computerUse: variant.modelInfo.supportsComputerUse ?? false,
                    mode: variant.modelInfo.mode
                )
            } ?? CombinedModel.ModelCapabilities(
                vision: false,
                functionCalling: false,
                reasoning: false,
                thinking: false,
                promptCaching: false,
                pdfInput: false,
                webSearch: false,
                computerUse: false,
                mode: "unknown"
            )
            
            // Extract pricing from primary variant
            let pricing = primaryVariant.map { variant in
                CombinedModel.ModelPricing(
                    inputCostPerMillionTokens: variant.modelInfo.inputCostPerToken.map { $0 * 1_000_000 },
                    outputCostPerMillionTokens: variant.modelInfo.outputCostPerToken.map { $0 * 1_000_000 }
                )
            } ?? CombinedModel.ModelPricing(
                inputCostPerMillionTokens: nil,
                outputCostPerMillionTokens: nil
            )
            
            // Extract limits from primary variant
            let limits = primaryVariant.map { variant in
                CombinedModel.ModelLimits(
                    maxInputTokens: variant.modelInfo.maxInputTokens,
                    maxOutputTokens: variant.modelInfo.maxOutputTokens,
                    totalMaxTokens: variant.modelInfo.maxTokens
                )
            } ?? CombinedModel.ModelLimits(
                maxInputTokens: nil,
                maxOutputTokens: nil,
                totalMaxTokens: nil
            )
            
            // Extract provider
            let provider = primaryVariant?.modelInfo.litellmProvider ?? "unknown"
            
            let combinedModel = CombinedModel(
                id: model.id,
                displayName: formatModelName(model.id),
                provider: formatProviderName(provider),
                capabilities: capabilities,
                pricing: pricing,
                limits: limits,
                fallbacks: model.metadata.fallbacks,
                variants: variants
            )
            
            combined.append(combinedModel)
        }
        
        // Sort by provider and then by name
        return combined.sorted { lhs, rhs in
            if lhs.provider == rhs.provider {
                return lhs.displayName < rhs.displayName
            }
            return lhs.provider < rhs.provider
        }
    }
    
    private func extractBaseModelName(from modelName: String) -> String {
        // Remove provider prefixes
        var name = modelName
        let prefixes = ["bedrock-", "google-", "vertex-ai-", "openai-"]
        for prefix in prefixes {
            if name.hasPrefix(prefix) {
                name = String(name.dropFirst(prefix.count))
            }
        }
        
        // Remove thinking suffixes
        if name.hasSuffix("-thinking") {
            name = String(name.dropLast("-thinking".count))
        }
        
        return name
    }
    
    private func findPrimaryVariant(variants: [ModelInfo], modelId: String) -> ModelInfo? {
        // First try exact match
        if let exact = variants.first(where: { $0.modelName == modelId }) {
            return exact
        }
        
        // Then try without thinking suffix
        let baseId = modelId.replacingOccurrences(of: "-thinking", with: "")
        if let base = variants.first(where: { $0.modelName == baseId }) {
            return base
        }
        
        // Return first if available
        return variants.first
    }
    
    private func formatModelName(_ name: String) -> String {
        // Format model names for display
        return name
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.capitalized }
            .joined(separator: " ")
    }
    
    private func formatProviderName(_ provider: String) -> String {
        let providerMap = [
            "anthropic": "Anthropic",
            "openai": "OpenAI",
            "vertex_ai": "Google Vertex AI",
            "vertex_ai-language-models": "Google Vertex AI",
            "vertex_ai-anthropic_models": "Google Vertex AI (Anthropic)",
            "bedrock_converse": "AWS Bedrock",
            "bedrock": "AWS Bedrock"
        ]
        
        return providerMap[provider] ?? provider.capitalized
    }
}