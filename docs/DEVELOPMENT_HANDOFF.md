# FloatDude 0.1.0 — development handoff

## Scope to implement

1. A menu-bar-only macOS app; no Dock icon during normal operation.
2. Configurable global shortcut, default `⌥ Space`.
3. Borderless, always-on-top floating panel placed near the cursor.
4. Panel closes on `Esc` and when focus is lost, except while an explicit system permission sheet is active.
5. Context capture using Accessibility selected text where available; clipboard fallback; editable direct-input fallback.
6. Four actions: Explain, Translate, Rewrite, Ask Anything.
7. OpenAI-compatible Chat Completions streaming response, cancellation, failure UI, and Copy.
8. Settings for Base URL, API key, model, and shortcut. API key uses Keychain.

## Explicit non-scope

- Accounts, sync, cloud backend, or telemetry.
- Conversation history or multi-turn chat.
- Screenshot capture.
- Tool invocation, shell access, text replacement, autonomous workflows, or agent loops.
- Responses API, provider-specific OAuth, and subscription logins.
- Distribution, notarization, updater, or DMG.

## Implementation order

1. Replace `App` scaffold with a production-ready menu-bar lifecycle and Settings entry point.
2. Implement `GlobalHotkeyManaging`, `WindowPositioning`, and the `NSPanel` controller; validate dismissal/focus behavior before AI work.
3. Implement accessibility permission UX and the selection → clipboard → direct-input capture chain.
4. Build panel state: context preview, action picker, prompt input, loading, streaming response, error, copy.
5. Implement the provider client and SSE cancellation path.
6. Implement Settings persistence and Keychain storage.
7. Add automated tests and manual acceptance evidence.

## Configuration decision

The initial provider adapter targets:

```text
POST {Base URL}/v1/chat/completions
Accept: text/event-stream
Authorization: Bearer {Keychain API key}
```

The implementation must normalize trailing slashes in Base URL and redact credentials from all errors and debug logs.
