import Foundation

/// Reserved boundary for Server-Sent Event framing.
/// JSON decoding and provider-specific payload mapping must live behind `LLMClient`.
struct SSEParser: Sendable {}
