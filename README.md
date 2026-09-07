# FloatDude

<div align="center">

**One shortcut. One tiny window. One job done.**

An AI dude that pops up wherever you need it on your Mac.

[English](README.md) · [简体中文](README.zh-CN.md)

</div>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/design/floatdude-dark-glass-reference.png">
  <img alt="FloatDude floating beside selected text on macOS" src="docs/design/floatdude-light-glass-reference.png">
</picture>

FloatDude is a native macOS menu-bar utility built around one focused interaction:

> Select something → invoke FloatDude → finish one task → disappear.

It is not a chat client squeezed into a floating window. FloatDude uses macOS-native shortcuts, selection capture, window behavior, and permissions to bring a small AI action surface directly to the work already in front of you.

## What it does

- Opens with the global `⌥ Space` shortcut.
- Captures the current text selection through macOS Accessibility when available.
- Falls back safely to the clipboard or direct input.
- Places one movable, always-on-top panel beside the selection.
- Provides **Explain**, **Translate**, **Rewrite**, and **Ask Anything** actions.
- Streams responses from OpenAI Chat Completions or Anthropic Messages compatible APIs.
- Copies the result in one click and disappears with `Esc` or a click outside.
- Follows the current macOS Light or Dark appearance with an adaptive glass interface.

## Why native macOS

FloatDude is written in Swift because its defining behaviors belong to the Mac:

- **SwiftUI** owns the interface, settings, and application state.
- **AppKit** owns `NSPanel`, focus, window level, positioning, menu-bar behavior, and Accessibility integration.
- **URLSession** owns provider communication and server-sent event streaming.
- **Keychain Services** optionally stores a remembered API key on the current Mac.

There is no third-party runtime dependency, FloatDude account, synchronization service, or application backend.

## Requirements

- macOS 14 Sonoma or newer
- Xcode 16 or newer
- An OpenAI Chat Completions or Anthropic Messages compatible model endpoint

FloatDude currently ships as a development build. A signed, notarized DMG is not available yet.

## Build and run

```sh
git clone https://github.com/KkSss999/FloatDude.git
cd FloatDude
open FloatDude.xcodeproj
```

Select the **FloatDude** scheme in Xcode and run the app. FloatDude lives in the menu bar and does not occupy the Dock.

Then:

1. Open **FloatDude → Settings…** from the menu bar.
2. Configure the base URL, model, credential mode, and API key for your provider.
3. Grant FloatDude access in **System Settings → Privacy & Security → Accessibility**.
4. Select text in another app and press `⌥ Space`.

Fresh settings use DeepSeek's Anthropic-compatible endpoint with `deepseek-v4-flash` and **This Session Only** credential mode. You can replace every provider field with another compatible service.

## Credentials and privacy

FloatDude is local-first, but model requests are sent to the provider you configure.

- **No Authentication** sends no authentication header.
- **This Session Only** retains the key in memory until FloatDude quits or the provider session is cleared.
- **Remember on This Mac** stores the key in the macOS login Keychain only after explicit opt-in.
- API keys are never written to `UserDefaults`, source control, application logs, or endpoint URLs.
- Credential-like selections and clipboard values are blocked before they can become model context.
- Selected text and prompts are sent only when you run an action, directly to the configured model endpoint.
- FloatDude has no telemetry or project-operated server.

You are responsible for reviewing the data and retention policies of the model provider you choose.

## Project structure

```text
Sources/FloatDude/
├── App/       application lifecycle and task coordination
├── UI/        SwiftUI surfaces and AppKit panel boundary
├── System/    hotkey, selection, clipboard, and positioning
├── AI/        provider requests, SSE streaming, and actions
├── Storage/   preferences and Keychain integration
└── Core/      shared domain types
```

The dependency direction is:

```text
App / UI → System / AI / Storage → Core
```

See [Architecture](docs/ARCHITECTURE.md), [UI direction](docs/UI_DIRECTION.md), [Development handoff](docs/DEVELOPMENT_HANDOFF.md), and [Quality gates](docs/QUALITY_GATES.md) for implementation details.

## Local validation

```sh
swift build
swift test
./Scripts/run-local-validation.sh
./Scripts/secret-scan.sh
xcodebuild -project FloatDude.xcodeproj -scheme FloatDude -destination 'platform=macOS' build
xcodebuild -project FloatDude.xcodeproj -scheme FloatDude -destination 'platform=macOS' test
```

The Xcode build and XCTest suite require a full Xcode installation. Development builds are ad-hoc signed, so macOS Accessibility authorization may need to be granted again after rebuilding at a different path or with a different code identity.

## Contributing

Issues and focused pull requests are welcome. Please keep proposed changes aligned with FloatDude's defining constraint: one invocation, one compact surface, one completed job.

Before submitting code, run the local validation commands above and confirm that no API key, selected text, or other private content is included in the change.

## Author

FloatDude was conceived, designed, and built by **Kerye (凯毅)** — [@KkSss999](https://github.com/KkSss999).

It is both an open-source macOS utility and an exploration of how AI can feel native, temporary, and respectful of the user's current context.

## License

FloatDude is licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution.

The license does not grant rights to use the FloatDude name or visual identity except as required to describe the origin of the project and reproduce its attribution notices.
