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
| `AI` | `URLSession` | request building, SSE framing, stream decoding, cancellation |
| `Storage` | UserDefaults + Keychain | non-secret preferences and API key only |
| `Core` | Foundation | action and error domain types |

## Required contracts

- Accessibility is best-effort. `ContextCapturing` must fall back in this order: selection, clipboard, direct input.
- `KeychainStoring` is the sole owner of API keys. No API key may appear in `AppSettings`, logs, errors, or analytics.
- `LLMClient` is provider-independent at the application boundary. v0.1 implements only OpenAI-compatible Chat Completions SSE.
- `FloatingPanel` is a SwiftUI content host. An AppKit `NSPanel` controller must own panel level, focus, location, activation, and dismissal.
- System actions in later releases require explicit user confirmation. Do not add an agent/tool loop to v0.1.

## Concurrency

- UI and AppKit lifecycle code runs on `MainActor`.
- Network streaming and context capture must not block the main thread.
- Cancellation from `Esc`, panel dismissal, and a second shortcut must stop the active request and discard late stream events.

## Dependency rule

Dependency direction is `App/UI → System/AI/Storage → Core`. `Core` imports no UI, AppKit, network, or storage concerns.
