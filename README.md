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
- Xcode 16 or newer for the native app target and XCTest
- No third-party runtime dependencies in the initial scaffold
- Configuration: OpenAI-compatible Chat Completions streaming API
- Credentials: explicit `No Authentication`, `This Session Only`, or `Remember on This Mac`; Keychain is opt-in and keys never enter `UserDefaults`, source control, or logs
- Fresh installs default to DeepSeek's Anthropic-compatible endpoint and `deepseek-v4-flash`; only the API key requires user input.

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
./Scripts/run-local-validation.sh
xcodebuild -project FloatDude.xcodeproj -scheme FloatDude -destination 'platform=macOS' build
xcodebuild -project FloatDude.xcodeproj -scheme FloatDude -destination 'platform=macOS' test
```

`swift build` remains available for the package scaffold. The native app target and XCTest suite require a full Xcode installation; Command Line Tools alone do not provide `xcodebuild` or the XCTest module. The app target is intentionally unsigned and unsandboxed in v0.1.0 so Accessibility and global-hotkey integration can be validated; the target declares outbound network access for the configured model endpoint. Release signing, notarization, app icons, and a distributable `.app` bundle are deliberately deferred from v0.1.0.
