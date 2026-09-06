import Foundation

@main
struct LiveValidation {
    static func main() async {
        guard let apiKey = ProcessInfo.processInfo.environment["FLOATDUDE_LIVE_KEY"], !apiKey.isEmpty else {
            print("LIVE_VALIDATION_KEY_MISSING")
            return
        }

        do {
            let client = try OpenAIChatCompletionsClient(
                configuration: LLMConfiguration(
                    baseURL: URL(string: "https://api.deepseek.com/anthropic")!,
                    model: "deepseek-v4-flash"
                ),
                credentials: ProviderCredentials(mode: .thisSessionOnly, apiKey: apiKey)
            )
            var deltaCount = 0
            var completed = false
            for try await event in client.stream(
                LLMRequest(
                    action: .explain,
                    context: CapturedContext(
                        text: "FloatDude live validation context",
                        source: .directInput,
                        applicationName: nil
                    ),
                    userPrompt: "Reply with one short sentence."
                )
            ) {
                switch event {
                case .textDelta:
                    deltaCount += 1
                case .completed:
                    completed = true
                }
            }
            print("LIVE_VALIDATION_HTTP_OK")
            print("LIVE_VALIDATION_TEXT_DELTA_COUNT=\(deltaCount)")
            print("LIVE_VALIDATION_COMPLETED=\(completed)")
        } catch {
            print("LIVE_VALIDATION_FAILED")
            print("LIVE_VALIDATION_ERROR=\(LLMSecretRedactor.redact(error.localizedDescription, apiKey: apiKey))")
        }
    }
}
