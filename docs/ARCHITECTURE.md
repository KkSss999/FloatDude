# Architecture boundary — v0.1.0

## Principle

FloatDude v0.1.0 is a one-shot action product, not an agent runtime.

```text
Global shortcut
  → Context capture
  → Floating panel + action selection
  → OpenAI-compatible streaming request
  → Response + copy or dismiss
```

There is no model-to-tool execution loop, autonomous planning, chat history, cloud account, or server in this release.

## Ownership

| Area | Primary technology | Responsibility |
| --- | --- | --- |
| `App` | AppKit + SwiftUI | accessory lifecycle and menu-bar host |
| `UI` | SwiftUI, AppKit at the panel seam | views; AppKit owns `NSPanel` behavior |
| `System` | AppKit, Accessibility, Carbon/EventKit as justified | global hotkey, text capture, pasteboard, cursor positioning |
| `AI` | `URLSession` | OpenAI/Anthropic request building, SSE framing, stream decoding, cancellation |
| `Storage` | UserDefaults + process memory + Keychain | non-secret preferences, ephemeral session key, opt-in remembered key |
| `Core` | Foundation | action and error domain types |

## Required contracts

- Accessibility is best-effort. `ContextCapturing` must fall back in this order: selection, clipboard, direct input.
- Credential-like content is blocked before it can become context. Clipboard fallback must never preview or transmit an API key, authorization header, private key, or recognized provider token.
- Credentials are explicit: No Authentication sends no auth header, This Session Only retains a key only for the process lifetime, and Remember on This Mac persists an opt-in device-local key. No API key may appear in `AppSettings`, logs, errors, analytics, or endpoint URLs.
- A panel dismissal cancels the task and clears task context, not the provider session. Provider credentials clear only on app termination, disconnect, mode change, replacement, or explicit forget.
- `LLMClient` is provider-independent at the application boundary. v0.1 implements OpenAI Chat Completions SSE and Anthropic Messages SSE.
- A stream is complete only after its protocol terminal signal (`[DONE]` or `message_stop`); a clean early EOF is an error.
- Settings clears the clipboard only when its normalized text exactly matches the API key just applied; unrelated clipboard content is never modified.
- `FloatingPanel` is a SwiftUI content host. An AppKit `NSPanel` controller must own panel level, focus, location, activation, and dismissal.
- System actions in later releases require explicit user confirmation. Do not add an agent/tool loop to v0.1.

## Concurrency

For the ad-hoc signed v0.1 macOS build, Remember on This Mac uses the system
file-based login keychain with default application access controls. It does not
opt into iCloud synchronization and never writes plaintext preferences. This is
not the Data Protection keychain's ThisDeviceOnly guarantee: login-keychain
backup/migration behavior remains controlled by macOS. Data Protection keychain
requires a future correctly provisioned signing configuration. Do not silently
fall back to plaintext or allow-all access lists. A failed save preserves the
previous working in-memory credential. Real persistence is checked separately
with Scripts/keychain-validation.swift using synthetic values and a unique service.

- UI and AppKit lifecycle code runs on `MainActor`.
- Network streaming and context capture must not block the main thread.
- Cancellation from `Esc`, panel dismissal, and a second shortcut must stop the active request and discard late stream events.

## Dependency rule

Dependency direction is `App/UI → System/AI/Storage → Core`. `Core` imports no UI, AppKit, network, or storage concerns.
