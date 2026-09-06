# FloatDude

> An AI dude that pops up wherever you need it on your Mac.

FloatDude is a native macOS menu-bar utility built around one interaction:

> Select something → invoke FloatDude → finish one task → disappear.

## v0.1.0 — Pop

The first milestone proves a single, complete loop:

1. Invoke FloatDude with `⌥ Space`.
2. Capture selected text when available, otherwise use the clipboard or direct input.
3. Choose Explain, Translate, Rewrite, or Ask Anything.
4. Receive a streaming response from a user-configured OpenAI-compatible model.
5. Copy the result or press `Esc` to dismiss.

This repository currently contains the application and architecture scaffold only. Product behavior is intentionally left for the implementation team.

## Engineering baseline

- Swift 6, SwiftUI, and AppKit
- macOS 14 Sonoma or newer
- No third-party runtime dependencies in the initial scaffold
- Configuration: OpenAI-compatible Chat Completions streaming API
- Credentials: Keychain only; never `UserDefaults`, source control, or logs

## Layout

```text
Sources/FloatDude/
├── App/       application lifecycle and menu-bar host
├── UI/        SwiftUI surfaces and AppKit panel boundary
├── System/    hotkey, selection, clipboard, and positioning contracts
├── AI/        provider, streaming, and prompt-action contracts
├── Storage/   settings and Keychain contracts
└── Core/      product domain types
```

Read [architecture](docs/ARCHITECTURE.md), [UI direction](docs/UI_DIRECTION.md), [implementation handoff](docs/DEVELOPMENT_HANDOFF.md), and [quality gates](docs/QUALITY_GATES.md) before implementing behavior.

## Local checks

```sh
swift build
swift test
```

Opening `Package.swift` in Xcode is supported. Release signing, notarization, app icons, and a distributable `.app` bundle are deliberately deferred from v0.1.0.
