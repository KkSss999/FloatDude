import Foundation

struct ModelCatalogClient: Sendable {
    let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchModels(
        configuration: LLMConfiguration,
        credentials: ProviderCredentials
    ) async throws -> [String] {
        let url = try LLMEndpoint.modelsURL(for: configuration.baseURL)
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if credentials.mode != .noAuthentication {
            guard let apiKey = credentials.apiKey, !apiKey.isEmpty else {
                throw LLMClientError.missingAPIKey
            }
            switch configuration.apiFormat {
            case .openAIChatCompletions:
                request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            case .anthropicMessages:
                request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
                request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            }
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw AgentEngineError.modelCatalogUnavailable("The provider returned no HTTP response.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = LLMSecretRedactor.redact(
                Self.providerMessage(from: data),
                apiKey: credentials.apiKey ?? ""
            )
            throw AgentEngineError.modelCatalogUnavailable(
                message.isEmpty
                    ? "Model test failed with HTTP \(http.statusCode)."
                    : "Model test failed with HTTP \(http.statusCode): \(message)"
            )
        }
        let ids = Self.modelIDs(from: data)
        guard !ids.isEmpty else {
            throw AgentEngineError.modelCatalogUnavailable("The provider connected, but /v1/models returned no model IDs.")
        }
        return ids.sorted()
    }

    static func modelIDs(from data: Data) -> [String] {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [] }
        let candidates = (object["data"] as? [[String: Any]])
            ?? (object["models"] as? [[String: Any]])
            ?? []
        return candidates.compactMap { ($0["id"] ?? $0["name"]) as? String }
    }

    static func isOptionalCatalogEndpointUnavailable(_ error: Error) -> Bool {
        guard let agentError = error as? AgentEngineError,
              case let .modelCatalogUnavailable(message) = agentError
        else {
            return false
        }
        return message.contains("HTTP 404")
    }

    private static func providerMessage(from data: Data) -> String {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "" }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return object["message"] as? String ?? ""
    }
}
