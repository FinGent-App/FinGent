// FinGent/Agent/MCP/MCPClient.swift
//
// Model Context Protocol (MCP) Client for iOS.
// Implements JSON-RPC 2.0 communication over SSE (Server-Sent Events) and HTTP
// connecting Apple FoundationModels with the FinGent Cloud MCP Server.

import Foundation

// MARK: - MCP Tool Metadata Model

struct MCPToolDefinition: Sendable, Identifiable {
    var id: String { name }
    let name: String
    let description: String
    let inputSchema: [String: Any]?

    init(name: String, description: String, inputSchema: [String: Any]? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }
}

// MARK: - MCP Client

final class MCPClient: Sendable {

    static let shared = MCPClient()

    let baseURL: String
    let session: URLSession

    init(
        baseURL: String = StockApiClient.shared.baseURL,
        session: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.session = session
    }

    // MARK: - Connection & Discovery

    /// Discovers and caches available MCP tools from the server.
    @discardableResult
    func listTools() async throws -> [MCPToolDefinition] {
        guard let url = URL(string: "\(baseURL)/api/v1/mcp/tools") else {
            throw URLError(.badURL)
        }

        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let toolArray = json["tools"] as? [[String: Any]] else {
            return []
        }

        var results: [MCPToolDefinition] = []
        for t in toolArray {
            if let name = t["name"] as? String {
                let desc = t["description"] as? String ?? ""
                let schema = t["input_schema"] as? [String: Any]
                results.append(MCPToolDefinition(name: name, description: desc, inputSchema: schema))
            }
        }

        return results
    }

    // MARK: - Tool Calling (JSON-RPC 2.0 Protocol)

    /// Calls an MCP tool using standard JSON-RPC 2.0 parameters.
    /// Uses the resilient HTTP endpoint `/api/v1/mcp/call` with full parameter serialization.
    func callTool(name: String, arguments: [String: Any]) async throws -> String {
        guard let url = URL(string: "\(baseURL)/api/v1/mcp/call") else {
            throw URLError(.badURL)
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload: [String: Any] = [
            "name": name,
            "arguments": arguments
        ]

        req.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await session.data(for: req)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw URLError(.cannotParseResponse)
        }

        if let isError = json["is_error"] as? Bool, isError {
            let err = json["content"] as? String ?? "Unknown MCP Tool Error"
            return "Error from MCP Tool '\(name)': \(err)"
        }

        return json["content"] as? String ?? "{}"
    }
}
