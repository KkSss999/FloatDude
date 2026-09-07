# Quality gates — v0.1.0

## Build and tests

- `swift build` succeeds with no external runtime dependency.
- `swift test` passes.
- `xcodebuild -project FloatDude.xcodeproj -scheme FloatDude -destination 'platform=macOS' build` succeeds under full Xcode.
- The same Xcode scheme runs the XCTest suite with `xcodebuild ... test`.
- Add deterministic unit tests for prompt construction, SSE framing/decoding, URL normalization, settings serialization, and Keychain error mapping.
- Add UI or integration coverage for state transitions: idle → panel → streaming → completed/cancelled/error.

## Manual macOS acceptance

| Scenario | Expected result |
| --- | --- |
| Shortcut in Safari, Xcode, Terminal, and TextEdit | One panel appears near the cursor; no duplicate panels |
| Selected text available | Preview contains the selected text and labels its source |
| Accessibility denied | Clear non-blocking permission guidance, then clipboard or input fallback |
| `Esc` during streaming | Panel closes and cancels the request |
| Click outside the panel | Panel dismisses without retaining sensitive context in visible UI |
| Copy response | Pasteboard receives exactly the final visible response |
| Invalid endpoint/key | Human-readable error; key and Authorization header never rendered or logged |
| Credential modes | No Authentication sends no header; Session Only survives panel dismissal but not app relaunch; Remember on This Mac is Keychain-only |
| Stream termination | `[DONE]` or `message_stop` completes; an early EOF is reported as an error |
| Relaunch | Non-secret settings restore; Session Only key is absent; Remembered key may be reloaded from Keychain |

## Performance targets

- Panel is visible within 150 ms of a registered shortcut on an idle Apple Silicon Mac.
- Context preview renders within 100 ms after capture returns.
- The first visible model token arrives within 1.5 seconds of a responsive provider beginning its stream; record provider latency separately.
- No UI-frame stall longer than 100 ms while streaming a 10,000-character response.

## Security review before handoff

- Run `bash Scripts/secret-scan.sh --staged` before committing; it must inspect index content, not only the worktree.
- Verify `git diff --cached` contains no API keys or Keychain values.
- Search source and logs for `Authorization`, `api_key`, and `Bearer` before committing.
- Confirm no request body, selected text, or response is sent anywhere except the user-configured model endpoint.
- v0.1 uses local SwiftPM/Xcode validation and manual native acceptance. CI/CD is intentionally deferred to v0.5.0.
