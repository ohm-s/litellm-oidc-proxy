//
//  HTTPServer.swift
//  litellm-oidc-proxy
//
//  Created by Omar Ayoub Salloum on 7/29/25.
//

import Foundation
import Network

class HTTPServer: ObservableObject {
    private var listener: NWListener?
    @Published var isRunning = false
    @Published var currentPort: Int = 8080
    
    init() {
        currentPort = AppSettings.shared.port
    }
    
    func start(port: Int? = nil) {
        stop()
        
        if let port = port {
            currentPort = port
        }
        
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        
        do {
            listener = try NWListener(using: parameters, on: NWEndpoint.Port(integerLiteral: UInt16(currentPort)))
            listener?.newConnectionHandler = { [weak self] connection in
                self?.handleConnection(connection)
            }
            listener?.start(queue: .main)
            isRunning = true
            print("HTTP Server started on port \(currentPort)")
        } catch {
            print("Failed to start HTTP server: \(error)")
            isRunning = false
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
        print("HTTP Server stopped")
    }
    
    func restart(with newPort: Int) {
        currentPort = newPort
        if isRunning {
            start(port: newPort)
        }
    }
    
    private func handleConnection(_ connection: NWConnection) {
        connection.start(queue: .main)
        
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
            if let data = data, !data.isEmpty {
                let response = self.createHTTPResponse()
                self.send(response, on: connection)
            }
            
            if isComplete {
                connection.cancel()
            } else if let error = error {
                print("Connection error: \(error)")
                connection.cancel()
            }
        }
    }
    
    private func createHTTPResponse() -> Data {
        let body = "Hello World"
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/plain\r
        Content-Length: \(body.count)\r
        Connection: close\r
        \r
        \(body)
        """
        return response.data(using: .utf8) ?? Data()
    }
    
    private func send(_ data: Data, on connection: NWConnection) {
        connection.send(content: data, completion: .contentProcessed { error in
            if let error = error {
                print("Send error: \(error)")
            }
            connection.cancel()
        })
    }
}