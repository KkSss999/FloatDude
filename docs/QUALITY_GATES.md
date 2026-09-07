# Quality gates — v0.1.0

## Build and tests

- `swift build` succeeds with no external runtime dependency.
- `swift test` passes.
- `xcodebuild -project FloatDude.xcodeproj -scheme FloatDude -destination 'platform=macOS' build` succeeds under full Xcode.
- The same Xcode scheme runs the XCTest suite with `xcodebuild ... test`.
- `bash Scripts/install-local-app.sh` replaces the installed bundle, removes
  other local FloatDude app copies/links, unregisters their Launch Services
  records, and verifies `/Applications/FloatDude.app` is the only registered path.
- Add deterministic unit tests for prompt construction, SSE framing/decoding, URL normalization, settings serialization, and Keychain error mapping.
- Add UI or integration coverage for state transitions: idle → panel → streaming → completed/cancelled/error.

## Manual macOS acceptance

Use one final app build and path for permission acceptance. Ad-hoc code signing
uses a code-hash requirement and does not guarantee Accessibility trust survives
rebuilds. An enabled entry in System Settings alone is not proof that the running
binary is trusted. Record the in-app permission status and verify actual selected
text capture. A certificate-backed development identity is required for stable
identity across changing builds; CI/CD remains deferred to v0.5.0.

The task panel must not activate the entire app or raise Settings. Missing
configuration stays in the task error UI until the user explicitly opens Settings.
Opening Settings dismisses the task panel; closing macOS System Settings must not
close FloatDude Settings. Dismissal clears task content but preserves session keys.

| Scenario | Expected result |
| --- | --- |
| Shortcut in Safari, Xcode, Terminal, and TextEdit | One panel appears at the selection anchor, or the pointer fallback when bounds are unavailable; no duplicate panels |
| Selected text available | Preview contains the selected text, labels its source, and anchors the panel beside the selection rather than a distant pointer |
| Accessibility denied | Clear non-blocking permission guidance, then clipboard or input fallback |
| `Esc` during streaming | Panel closes and cancels the request |
| Click outside the panel | Panel remains visible and above normal windows without stealing focus |
| Repeated shortcut | Existing panel is raised without cancelling the turn or changing a user-moved position |
| Display/Space change | Full panel frame is constrained into the active visible frame and remains available |
| Drag panel background | Panel moves freely; response expansion preserves the dragged top anchor |
| Missing/invalid credential | Human-readable error exposes a working Settings button; legacy default DeepSeek/NoAuth state migrates to Session Only |
| Open Settings before first hotkey | Menu-bar Settings opens a populated window at least 520×480 pt without requiring a prior panel invocation or restoring a stale zero-sized frame |
| Clipboard contains a credential or standalone high-entropy token | FloatDude blocks it before preview/request and offers selection or direct-input recovery |
| Accessibility unavailable | Settings shows live permission status and user-triggered Request Access/Open System Settings actions; the panel explains any clipboard fallback |
| Apply credentials from clipboard | Matching API-key clipboard content is cleared; unrelated clipboard content is preserved |
| Copy response | Pasteboard receives exactly the final visible response |
| Multi-turn conversation | Second provider request contains ordered prior user/assistant turns and the same conversation ID |
| Attachment import | PDF/Markdown/text/Word/XLSX/CSV/TSV is copied into the active conversation after extraction validation |
| Agent tools | Provider sees exactly read/write; read cannot escape active attachments and write cannot escape managed `.md`/`.txt` exports |
| Model test | Settings GETs `/v1/models` with the selected credential mode and reports the model count without exposing the key |
| Launch at login | Settings reflects `SMAppService.mainApp` status and register/unregister errors remain actionable |
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
- Verify recognized credential patterns are rejected independently by context capture, task coordination, and network request construction.
- v0.1 uses local SwiftPM/Xcode validation and manual native acceptance. CI/CD is intentionally deferred to v0.5.0.
