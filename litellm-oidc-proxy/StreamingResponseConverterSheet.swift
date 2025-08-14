//
//  StreamingResponseConverterSheet.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 8/14/25.
//

import SwiftUI

struct StreamingResponseConverterSheet: View {
    let title: String
    let sseData: String
    @Binding var isPresented: Bool
    @Environment(\.colorScheme) var colorScheme
    
    @State private var convertedJSON: String = ""
    @State private var conversionError: String? = nil
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text(title)
                    .font(.headline)
                
                Spacer()
                
                if !convertedJSON.isEmpty {
                    Button(action: {
                        // Copy to clipboard
                        let pasteboard = NSPasteboard.general
                        pasteboard.clearContents()
                        pasteboard.setString(convertedJSON, forType: .string)
                    }) {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(PlainButtonStyle())
                    .help("Copy to clipboard")
                }
                
                Button(action: {
                    isPresented = false
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding()
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // JSON content or error
            if let error = conversionError {
                VStack(spacing: 20) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 48))
                        .foregroundColor(.orange)
                    
                    Text("Failed to convert streaming response")
                        .font(.headline)
                    
                    Text(error)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if !convertedJSON.isEmpty {
                JSONWebView(jsonString: convertedJSON, isDarkMode: colorScheme == .dark)
                    .frame(minWidth: 600, minHeight: 400)
            } else {
                ProgressView("Converting streaming response...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: 1400, height: 900)
        .onAppear {
            convertStreamingResponse()
        }
    }
    
    private func convertStreamingResponse() {
        if let parsed = StreamingResponseParser.parseAnthropicStreamingResponse(sseData) {
            convertedJSON = parsed
        } else {
            conversionError = "The response does not appear to be a valid Anthropic streaming format."
        }
    }
}