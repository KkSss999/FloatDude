# FloatDude

<div align="center">

**One shortcut. One persistent window. Every conversation close at hand.**

An AI dude that pops up wherever you need it on your Mac.

[English](README.md) · [Chinese](README.zh-CN.md)

</div>

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/design/floatdude-dark-glass-reference.png">
  <img alt="FloatDude floating beside selected text on macOS" src="docs/design/floatdude-light-glass-reference.png">
</picture>

FloatDude is a native macOS menu-bar agent built around a compact persistent surface:

> Select something or attach a document → invoke FloatDude → continue the conversation.

FloatDude uses macOS-native shortcuts, selection capture, window behavior, and permissions to keep a focused AI workspace directly beside the work already in front of you.

## What it does

- Opens with the global `⌥ Space` shortcut.
- Captures the current text selection through macOS Accessibility when available.
- Falls back safely to the clipboard or direct input.
- Places one movable, always-on-top panel beside the selection.
- Keeps the panel visible across app focus, Spaces, full screen, and Stage Manager until you explicitly close it.
- Reopens the last active conversation at its newest turn, with jump-to-latest and hover-expandable message navigation.
- Keeps a pending selected-text context synchronized while the nonactivating panel is open; a new conversation receives that live context without persisting it.
- Feishu falls back to a clipboard-preserving snapshot at shortcut invocation when its Electron-style renderer exposes no Accessibility selection; that path is not live synchronization. Other supported applications retain live AX selection updates.
- Lets the menu-bar surface, conversation panel, and Settings switch immediately between English and Simplified Chinese.
- Attaches PDF, Markdown/text, Word, XLSX, CSV, and TSV files directly from the panel.
- Gives the model exactly two bounded native tools: read attached content and write managed Markdown/text exports.
- Provides **Explain**, **Translate**, **Rewrite**, and **Ask Anything** actions.
- Shows **Rewrite** only when Accessibility confirms the selection can be replaced.
- Streams responses from OpenAI Chat Completions or Anthropic Messages compatible APIs.
- Renders Markdown headings, emphasis, links, lists, quotes, code, rules, and tables.
- Copies the result in one click and closes explicitly with `Esc` or the close button.
- Follows the current macOS Light or Dark appearance with an adaptive glass interface.

## Why native macOS

FloatDude is written in Swift because its defining behaviors belong to the Mac:

- **SwiftUI** owns the interface, settings, and application state.
- **AppKit** owns `NSPanel`, focus, window level, positioning, menu-bar behavior, and Accessibility integration.
- **URLSession** owns provider communication and server-sent event streaming.
- **PDFKit, AppKit document import, and native ZIP/XML parsing** extract user-selected documents.
- **ServiceManagement** controls the optional launch-at-login registration.
- **Keychain Services** optionally stores a remembered API key on the current Mac.

There is no third-party runtime dependency, FloatDude account, synchronization service, or application backend.

## Requirements

- macOS 14 Sonoma or newer
- Xcode 26 or newer
- An OpenAI Chat Completions or Anthropic Messages compatible model endpoint

The v0.1.0 GitHub Release provides an ad-hoc signed, unnotarized DMG for local
evaluation. If Gatekeeper blocks the first launch, Control-click FloatDude and
choose **Open**. Grant Accessibility to the installed `/Applications/FloatDude.app`;
replacing this development build can require authorization again because it has
no stable Developer ID identity.

## Build and run

```sh
git clone https://github.com/KkSss999/FloatDude.git
cd FloatDude
open FloatDude.xcodeproj
```

Select the **FloatDude** scheme in Xcode and run the app. FloatDude lives in the menu bar and does not occupy the Dock.

Then:

1. Open **FloatDude → Settings…** from the menu bar.
2. Configure the base URL, model, credential mode, API key, and optional user system instructions.
3. Use **Test /models** to verify provider connectivity before chatting.
4. Grant FloatDude access in **System Settings → Privacy & Security → Accessibility** (Device Control and Data Access on macOS 27).
5. Select text in another app and press `⌥ Space`, or attach documents from the paperclip button.

Fresh settings use DeepSeek's Anthropic-compatible endpoint with `deepseek-v4-flash` and **This Session Only** credential mode. You can replace every provider field with another compatible service.

## Credentials and privacy

FloatDude is local-first, but model requests are sent to the provider you configure.

- **No Authentication** sends no authentication header.
- **This Session Only** retains the key in memory until FloatDude quits or the provider session is cleared.
- **Remember on This Mac** stores the key in the macOS login Keychain only after explicit opt-in.
- API keys are never written to `UserDefaults`, source control, application logs, or endpoint URLs.
- Credential-like selections and clipboard values are blocked before they can become model context.
- Selected text and prompts are sent only when you run an action, directly to the configured model endpoint.
- Typed user turns and assistant answers are stored locally for multi-turn sessions; captured selection and clipboard text are not persisted.
- Explicitly attached files are copied into FloatDude's Application Support directory and removed with their conversation.
- The model can read only attachment IDs from the active conversation and write only `.md`/`.txt` files into FloatDude's managed Exports directory.
- FloatDude has no telemetry or project-operated server.

You are responsible for reviewing the data and retention policies of the model provider you choose.

## Project structure

```text
Sources/FloatDude/
├── Agent/     conversations, protected root policy, attachments, and read/write tools
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

See [Architecture](docs/ARCHITECTURE.md), [research notes](docs/AGENT_ENGINE_RESEARCH.md), [UI direction](docs/UI_DIRECTION.md), [Development handoff](docs/DEVELOPMENT_HANDOFF.md), and [Quality gates](docs/QUALITY_GATES.md) for implementation details.

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

Issues and focused pull requests are welcome. Keep the surface compact and every model capability mechanically bounded by the harness.

Before submitting code, run the local validation commands above and confirm that no API key, selected text, or other private content is included in the change.

## Author

FloatDude was conceived, designed, and built by **Kerye Gwent** — [@KkSss999](https://github.com/KkSss999).

It is both an open-source macOS utility and an exploration of how AI can feel native, temporary, and respectful of the user's current context.

## License

FloatDude is licensed under the [Apache License 2.0](LICENSE). See [NOTICE](NOTICE) for attribution.

The license does not grant rights to use the FloatDude name or visual identity except as required to describe the origin of the project and reproduce its attribution notices.

## Local application bundle

Build and install a Release `.app` that runs independently of Xcode:

```sh
bash Scripts/install-local-app.sh
```

The script builds the Release bundle, replaces `/Applications/FloatDude.app`,
removes other FloatDude build copies and links, clears their stale Launch Services
registrations, and opens the one installed copy. FloatDude lives in the menu bar
and has no Dock icon. Use **Ask FloatDude…** in its menu-bar panel, or open the app
again, to show the task surface. Local builds are ad-hoc signed; this is not a
notarized distribution.
