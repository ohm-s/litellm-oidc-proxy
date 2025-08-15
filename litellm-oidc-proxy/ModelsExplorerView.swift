//
//  ModelsExplorerView.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 1/15/25.
//

import SwiftUI

struct ModelsExplorerView: View {
    @StateObject private var modelService = ModelService()
    @State private var selectedModel: CombinedModel?
    @State private var searchText = ""
    @State private var filterProvider = "All Providers"
    @State private var showOnlyWithFallbacks = false
    @State private var sortBy = SortOption.name
    
    enum SortOption: String, CaseIterable {
        case name = "Name"
        case provider = "Provider"
        case inputCost = "Input Cost"
        case outputCost = "Output Cost"
    }
    
    var availableProviders: [String] {
        let providers = Set(modelService.combinedModels.map { $0.provider })
        return ["All Providers"] + providers.sorted()
    }
    
    var filteredModels: [CombinedModel] {
        var models = modelService.combinedModels
        
        // Filter by search text
        if !searchText.isEmpty {
            models = models.filter { model in
                model.displayName.localizedCaseInsensitiveContains(searchText) ||
                model.id.localizedCaseInsensitiveContains(searchText) ||
                model.provider.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        // Filter by provider
        if filterProvider != "All Providers" {
            models = models.filter { $0.provider == filterProvider }
        }
        
        // Filter by fallbacks
        if showOnlyWithFallbacks {
            models = models.filter { !$0.fallbacks.isEmpty }
        }
        
        // Sort
        switch sortBy {
        case .name:
            models.sort { $0.displayName < $1.displayName }
        case .provider:
            models.sort { lhs, rhs in
                if lhs.provider == rhs.provider {
                    return lhs.displayName < rhs.displayName
                }
                return lhs.provider < rhs.provider
            }
        case .inputCost:
            models.sort { lhs, rhs in
                let lhsCost = lhs.pricing.inputCostPerMillionTokens ?? Double.greatestFiniteMagnitude
                let rhsCost = rhs.pricing.inputCostPerMillionTokens ?? Double.greatestFiniteMagnitude
                return lhsCost < rhsCost
            }
        case .outputCost:
            models.sort { lhs, rhs in
                let lhsCost = lhs.pricing.outputCostPerMillionTokens ?? Double.greatestFiniteMagnitude
                let rhsCost = rhs.pricing.outputCostPerMillionTokens ?? Double.greatestFiniteMagnitude
                return lhsCost < rhsCost
            }
        }
        
        return models
    }
    
    var body: some View {
        HSplitView {
            // Left panel - Model list
            VStack(spacing: 0) {
                // Search and filters
                VStack(spacing: 12) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                        TextField("Search models...", text: $searchText)
                            .textFieldStyle(PlainTextFieldStyle())
                    }
                    .padding(8)
                    .background(Color(NSColor.textBackgroundColor))
                    .cornerRadius(8)
                    
                    HStack {
                        Picker("Provider", selection: $filterProvider) {
                            ForEach(availableProviders, id: \.self) { provider in
                                Text(provider).tag(provider)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 200)
                        
                        Picker("Sort by", selection: $sortBy) {
                            ForEach(SortOption.allCases, id: \.self) { option in
                                Text(option.rawValue).tag(option)
                            }
                        }
                        .pickerStyle(MenuPickerStyle())
                        .frame(width: 150)
                        
                        Spacer()
                        
                        Toggle("Has Fallbacks", isOn: $showOnlyWithFallbacks)
                            .toggleStyle(CheckboxToggleStyle())
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                
                Divider()
                
                // Model list
                if modelService.isLoading {
                    VStack {
                        ProgressView("Loading models...")
                            .padding()
                        Spacer()
                    }
                } else if let error = modelService.error {
                    VStack {
                        Text("Error loading models")
                            .font(.headline)
                            .padding(.top)
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal)
                        Button("Retry") {
                            Task {
                                await modelService.fetchModels()
                            }
                        }
                        .padding()
                        Spacer()
                    }
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(filteredModels) { model in
                                ModelRowView(model: model, isSelected: selectedModel?.id == model.id)
                                    .onTapGesture {
                                        selectedModel = model
                                    }
                                
                                Divider()
                            }
                        }
                    }
                }
                
                // Status bar
                Divider()
                HStack {
                    Text("\(filteredModels.count) models")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button(action: {
                        Task {
                            await modelService.fetchModels()
                        }
                    }) {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Refresh")
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(NSColor.controlBackgroundColor))
            }
            .frame(minWidth: 400, idealWidth: 500)
            
            // Right panel - Model details
            if let model = selectedModel {
                ModelDetailView(model: model)
                    .frame(minWidth: 500)
            } else {
                VStack {
                    Text("Select a model to view details")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 1200, minHeight: 700)
        .onAppear {
            Task {
                await modelService.fetchModels()
            }
        }
    }
}

struct ModelRowView: View {
    let model: CombinedModel
    let isSelected: Bool
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                
                HStack(spacing: 8) {
                    Label(model.provider, systemImage: "cloud")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !model.fallbacks.isEmpty {
                        Label("\(model.fallbacks.count) fallbacks", systemImage: "arrow.triangle.2.circlepath")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    
                    if let inputCost = model.pricing.inputCostPerMillionTokens {
                        Text("$\(String(format: "%.2f", inputCost))/M")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                }
            }
            
            Spacer()
            
            // Capability badges
            HStack(spacing: 4) {
                if model.capabilities.reasoning {
                    CapabilityBadge(icon: "brain", tooltip: "Reasoning")
                }
                if model.capabilities.vision {
                    CapabilityBadge(icon: "eye", tooltip: "Vision")
                }
                if model.capabilities.functionCalling {
                    CapabilityBadge(icon: "function", tooltip: "Function Calling")
                }
                if model.capabilities.webSearch {
                    CapabilityBadge(icon: "globe", tooltip: "Web Search")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .contentShape(Rectangle())
    }
}

struct CapabilityBadge: View {
    let icon: String
    let tooltip: String
    
    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 10))
            .foregroundColor(.secondary)
            .help(tooltip)
    }
}

struct ModelDetailView: View {
    let model: CombinedModel
    @State private var selectedTab = 0
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(alignment: .leading, spacing: 12) {
                Text(model.displayName)
                    .font(.title2)
                    .fontWeight(.semibold)
                
                HStack(spacing: 16) {
                    Label(model.provider, systemImage: "cloud")
                        .foregroundColor(.secondary)
                    
                    Text("ID: \(model.id)")
                        .font(.system(.body, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Tabs
            Picker("", selection: $selectedTab) {
                Text("Overview").tag(0)
                Text("Capabilities").tag(1)
                Text("Pricing & Limits").tag(2)
                Text("Variants").tag(3)
                if !model.fallbacks.isEmpty {
                    Text("Fallbacks").tag(4)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding()
            
            // Tab content
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selectedTab {
                    case 0:
                        ModelOverviewTab(model: model)
                    case 1:
                        ModelCapabilitiesTab(model: model)
                    case 2:
                        ModelPricingTab(model: model)
                    case 3:
                        ModelVariantsTab(model: model)
                    case 4:
                        ModelFallbacksTab(model: model)
                    default:
                        EmptyView()
                    }
                }
                .padding()
            }
        }
    }
}

struct ModelOverviewTab: View {
    let model: CombinedModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Quick summary
            GroupBox(label: Label("Summary", systemImage: "info.circle")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Provider:")
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .trailing)
                        Text(model.provider)
                        Spacer()
                    }
                    
                    HStack {
                        Text("Mode:")
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .trailing)
                        Text(model.capabilities.mode.capitalized)
                        Spacer()
                    }
                    
                    HStack {
                        Text("Variants:")
                            .fontWeight(.medium)
                            .frame(width: 120, alignment: .trailing)
                        Text("\(model.variants.count)")
                        Spacer()
                    }
                    
                    if !model.fallbacks.isEmpty {
                        HStack {
                            Text("Fallbacks:")
                                .fontWeight(.medium)
                                .frame(width: 120, alignment: .trailing)
                            Text("\(model.fallbacks.count)")
                            Spacer()
                        }
                    }
                }
                .padding()
            }
            
            // Key capabilities
            GroupBox(label: Label("Key Capabilities", systemImage: "star")) {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    ForEach(keyCapabilities, id: \.0) { capability, isSupported in
                        HStack {
                            Image(systemName: isSupported ? "checkmark.circle.fill" : "xmark.circle")
                                .foregroundColor(isSupported ? .green : .secondary)
                            Text(capability)
                            Spacer()
                        }
                    }
                }
                .padding()
            }
        }
    }
    
    var keyCapabilities: [(String, Bool)] {
        [
            ("Vision", model.capabilities.vision),
            ("Function Calling", model.capabilities.functionCalling),
            ("Reasoning", model.capabilities.reasoning),
            ("Thinking", model.capabilities.thinking),
            ("Web Search", model.capabilities.webSearch),
            ("PDF Input", model.capabilities.pdfInput)
        ]
    }
}

struct ModelCapabilitiesTab: View {
    let model: CombinedModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            GroupBox(label: Label("All Capabilities", systemImage: "checklist")) {
                LazyVGrid(columns: [
                    GridItem(.flexible()),
                    GridItem(.flexible())
                ], spacing: 12) {
                    CapabilityRow(name: "Vision", isSupported: model.capabilities.vision)
                    CapabilityRow(name: "Function Calling", isSupported: model.capabilities.functionCalling)
                    CapabilityRow(name: "Reasoning", isSupported: model.capabilities.reasoning)
                    CapabilityRow(name: "Thinking", isSupported: model.capabilities.thinking)
                    CapabilityRow(name: "Prompt Caching", isSupported: model.capabilities.promptCaching)
                    CapabilityRow(name: "PDF Input", isSupported: model.capabilities.pdfInput)
                    CapabilityRow(name: "Web Search", isSupported: model.capabilities.webSearch)
                    CapabilityRow(name: "Computer Use", isSupported: model.capabilities.computerUse)
                }
                .padding()
            }
        }
    }
}

struct CapabilityRow: View {
    let name: String
    let isSupported: Bool
    
    var body: some View {
        HStack {
            Image(systemName: isSupported ? "checkmark.circle.fill" : "xmark.circle")
                .foregroundColor(isSupported ? .green : .secondary)
            Text(name)
            Spacer()
        }
    }
}

struct ModelPricingTab: View {
    let model: CombinedModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Pricing
            GroupBox(label: Label("Pricing", systemImage: "dollarsign.circle")) {
                VStack(alignment: .leading, spacing: 12) {
                    if let inputCost = model.pricing.inputCostPerMillionTokens {
                        HStack {
                            Text("Input:")
                                .fontWeight(.medium)
                                .frame(width: 120, alignment: .trailing)
                            Text("$\(String(format: "%.2f", inputCost)) per million tokens")
                            Spacer()
                        }
                    }
                    
                    if let outputCost = model.pricing.outputCostPerMillionTokens {
                        HStack {
                            Text("Output:")
                                .fontWeight(.medium)
                                .frame(width: 120, alignment: .trailing)
                            Text("$\(String(format: "%.2f", outputCost)) per million tokens")
                            Spacer()
                        }
                    }
                    
                    if model.pricing.inputCostPerMillionTokens == nil && model.pricing.outputCostPerMillionTokens == nil {
                        Text("Pricing information not available")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
            
            // Token limits
            GroupBox(label: Label("Token Limits", systemImage: "doc.text")) {
                VStack(alignment: .leading, spacing: 12) {
                    if let maxInput = model.limits.maxInputTokens {
                        HStack {
                            Text("Max Input:")
                                .fontWeight(.medium)
                                .frame(width: 120, alignment: .trailing)
                            Text("\(maxInput.formatted()) tokens")
                            Spacer()
                        }
                    }
                    
                    if let maxOutput = model.limits.maxOutputTokens {
                        HStack {
                            Text("Max Output:")
                                .fontWeight(.medium)
                                .frame(width: 120, alignment: .trailing)
                            Text("\(maxOutput.formatted()) tokens")
                            Spacer()
                        }
                    }
                    
                    if let totalMax = model.limits.totalMaxTokens {
                        HStack {
                            Text("Total Max:")
                                .fontWeight(.medium)
                                .frame(width: 120, alignment: .trailing)
                            Text("\(totalMax.formatted()) tokens")
                            Spacer()
                        }
                    }
                    
                    if model.limits.maxInputTokens == nil && model.limits.maxOutputTokens == nil && model.limits.totalMaxTokens == nil {
                        Text("Token limit information not available")
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
    }
}

struct ModelVariantsTab: View {
    let model: CombinedModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if model.variants.isEmpty {
                Text("No variant information available")
                    .foregroundColor(.secondary)
            } else {
                ForEach(model.variants, id: \.modelName) { variant in
                    GroupBox(label: Text(variant.modelName)) {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Provider:")
                                    .fontWeight(.medium)
                                    .frame(width: 100, alignment: .trailing)
                                Text(variant.modelInfo.litellmProvider)
                                Spacer()
                            }
                            
                            HStack {
                                Text("Model:")
                                    .fontWeight(.medium)
                                    .frame(width: 100, alignment: .trailing)
                                Text(variant.litellmParams.model)
                                    .font(.system(.caption, design: .monospaced))
                                Spacer()
                            }
                            
                            if let region = variant.litellmParams.awsRegionName {
                                HStack {
                                    Text("Region:")
                                        .fontWeight(.medium)
                                        .frame(width: 100, alignment: .trailing)
                                    Text(region)
                                    Spacer()
                                }
                            }
                            
                            if let project = variant.litellmParams.vertexProject {
                                HStack {
                                    Text("Project:")
                                        .fontWeight(.medium)
                                        .frame(width: 100, alignment: .trailing)
                                    Text(project)
                                    Spacer()
                                }
                            }
                        }
                        .padding()
                    }
                }
            }
        }
    }
}

struct ModelFallbacksTab: View {
    let model: CombinedModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("This model has the following fallback options configured:")
                .foregroundColor(.secondary)
            
            ForEach(model.fallbacks, id: \.self) { fallback in
                HStack {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundColor(.blue)
                    Text(fallback)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color(NSColor.textBackgroundColor))
                .cornerRadius(8)
            }
        }
    }
}