# Local native application acceptance — 2026-09-07

The accepted glass UI is compiled into the actual application. The visual review
script uses the same FloatingPanel views, but is not the installed product.

- Release bundle installed at `/Applications/FloatDude.app`.
- Bundle identifier: `com.kks999.FloatDude`; version: 0.1.0 (1).
- Release build succeeded; strict code-signature verification succeeded.
- Installed executable SHA-256 matches the Release build:
  `94abff0a5f21f5774cecd0910f442ec2fac62c7f48dbe3134a5cb2c9820c43d4`.
- SwiftPM: 113 tests passed, zero failures. The Release build was compiled and
  installed through the single-copy installer; later interactive acceptance is user-owned.

Verified against the installed application through native UI:

- Finder recognizes the bundle as an application and launches it.
- Reopening the running application presents the real coordinator-backed panel.
- Direct input updates the field and enables submission.
- Submission without credentials expands the same panel and shows an actionable
  missing-key message; Settings opens the actual configuration window.
- Escape closes the panel; reopening presents a fresh prompt.
- Capture guidance, its recovery link, input and quick actions all fit in the
  initial panel after reserving 76 extra points for guidance.

The app remains a menu-bar utility (`LSUIElement`); absence from the Dock does not
indicate a missing application bundle. The menu now also offers Ask FloatDude.

## Usability and macOS 27 permission repair

- Title-strip drag verified in the installed app: a 90×60 point drag moved the
  WindowServer bounds from (1574, 1067) to (1664, 1127), retaining 400×252 size.
- Full native diffusion and denser neutral backing replace the transmission
  mask after real-work-window feedback about interfering background text.
- Disabled the rectangular `NSPanel` shadow that was visible outside the
  rounded glass surface. Native UI inspection of the installed Release app
  confirms the square outer outline is gone while the rounded surface shadow remains.
- OS verified as macOS 27.0 (26A5421a). The permission page on this host is
  “设备控制和数据访问” (Device Control and Data Access).
- TCC logs showed a stale `~/Applications/FloatDude.app` lookup and mismatching
  old/new ad-hoc code requirements. No valid certificate-based signing identity
  was available on this Mac.
- Unregistered the development build paths and force-registered `/Applications/FloatDude.app`.
- A prior build was added through System Settings after a FloatDude-only TCC
  reset. The newest ad-hoc build has a different code requirement and currently
  reports that Accessibility access is unavailable; it must be re-added before
  physical hotkey/selection acceptance.
- The former `~/Applications/FloatDude.app` compatibility link was removed at
  the user's request so no alternate FloatDude path remains.

Run `bash Scripts/install-local-app.sh` for local replacement. A later ad-hoc
rebuild may still require authorizing the newly signed binary because code-hash
identity cannot remain stable without a certificate-backed signing identity.

Still not verified: live model streaming and final-answer copy, macOS 14/15
material fallback, or system Reduce Transparency/Increase Contrast toggles.
No provider credentials or other applications' permissions were changed.

## Markdown, placement, and rewrite qualification

- Responses parse and render headings, inline emphasis and links, ordered and
  unordered lists, quotes, fenced code, rules, and pipe tables. Unclosed fenced
  code is rendered safely while streaming.
- Placement chooses the valid selection's display before the cursor display and
  follows a deterministic below/above/right/left order. Off-screen bounds are rejected.
- Context capture snapshots text, bounds, and writability synchronously inside
  the hot-key event. macOS 27 falls back from the failing system-wide focused
  element query to the frontmost application's AX element.
- Rewrite requires `AXUIElementIsAttributeSettable` to confirm that
  `AXSelectedText` is writable. Read-only selections, clipboard fallback, and
  direct input omit Rewrite; the coordinator rejects unsupported rewrite calls.
- Native preview visually confirmed Markdown rendering and both the three-action
  writable state and two-action non-writable state. Automated Option-Space
  injection does not faithfully reproduce a physical key event on this host,
  so physical-hotkey acceptance remains a separate check.

## Agent Engine foundation

- Switching focus to Finder left the installed panel visible and accessible;
  click-away no longer closes or cancels it.
- The native header conversation menu displayed New Conversation and the active
  session. Repeated presentation preserves a user-moved frame in tests.
- The installed panel opened its native multi-file importer and successfully
  imported `README.md` as a managed Markdown attachment. The UI showed its chip
  and completion status; the acceptance copy was then removed through the UI.
- Managed originals, extracted text caches, conversation JSON, and write-tool
  outputs are forced to owner-only `0600` permissions. Existing archives are
  tightened when loaded.
- OpenAI and Anthropic streamed tool-loop fixtures both completed a tool call,
  consumed a native result, sent the provider-specific tool-result shape, and
  continued to a final answer.
- Settings contains a bounded user system-prompt editor, `/models` test action,
  and `SMAppService.mainApp` launch-at-login control. Network validation uses
  synthetic URLProtocol evidence; no user credential was transmitted during acceptance.
- The protected software root and tool schemas form a stable prefix of more than
  1K tokens. Official providers receive their supported cache controls; compatible
  providers receive no vendor-only cache extensions.
- Remembered Keychain loading is off the main actor. A code-identity marker avoids
  querying an old ACL after rebuilds, and the query itself forbids authentication UI.
  Xcode test-host startup is isolated from the user's login Keychain.
- `Scripts/install-local-app.sh` built and staged the Release app, replaced the
  installed copy with rollback protection, deleted seven build-path copies plus
  the former home Applications link, and unregistered their Launch Services records.
- Filesystem and Launch Services inspection now return only
  `/Applications/FloatDude.app`.
- The installed build includes the 440 × 956 pt iPhone 17 Pro Max responsive
  canvas policy, active-conversation restoration with AX-only live selection
  synchronization, a jump-to-latest control, and hover-expandable message map.
- The message map records only user turns. The current build also follows
  process-scoped `AXSelectedTextChanged`/focus notifications with an AX-only
  polling fallback, and persists the Settings English/Simplified Chinese choice.
- Streaming, completed, cancelled, and failed turns render in the same transcript
  surface as conversation history. The fixed title strip remains outside the
  scroll view so its drag target is reachable in every scroll position.
- Feishu selection capture enables Electron's `AXManualAccessibility` attribute
  for its known bundle, searches a bounded focused-node neighborhood, and clears
  the pending context when an observed external app reports deselection.
- If Feishu exposes no AX selection, the user-invoked hotkey takes a one-shot
  Cmd-C snapshot, reads the resulting text, and restores every prior pasteboard
  representation before displaying context. This Feishu-only path is not live;
  other supported applications retain system-wide AX live selection capture.
- Model connectivity derives its probe from the configured base URL and requests
  exactly one `/v1/models` segment. The persistent English/Simplified Chinese
  setting now redraws the menu-bar surface and conversation UI as well as Settings.
- A 404 from the optional `/v1/models` directory is a warning rather than a
  model-use failure. Applying valid credentials clears a stale remembered-key
  startup alert, and deleting the only conversation creates a fresh empty one.

Final system permission recovery is a host operation after each ad-hoc binary
replacement. Re-adding the current installed hash remains the only local
acceptance step outside the built application.
