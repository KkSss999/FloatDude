# Local native application acceptance — 2026-09-07

The accepted glass UI is compiled into the actual application. The visual review
script uses the same FloatingPanel views, but is not the installed product.

- Release bundle installed at `/Applications/FloatDude.app`.
- Bundle identifier: `com.kks999.FloatDude`; version: 0.1.0 (1).
- Release build succeeded; strict code-signature verification succeeded.
- Installed executable SHA-256 matches the Release build:
  `37650adb5a0db5d76a391d7f12cd84417c58322321bc6f501b22bfeb120097de`.
- SwiftPM: 74 tests passed, zero failures.

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
- OS verified as macOS 27.0 (26A5421a). The permission page on this host is
  “设备控制和数据访问” (Device Control and Data Access).
- TCC logs showed a stale `~/Applications/FloatDude.app` lookup and mismatching
  old/new ad-hoc code requirements. No valid certificate-based signing identity
  was available on this Mac.
- Unregistered the development build paths and force-registered `/Applications/FloatDude.app`.
- With explicit user approval, reset only `Accessibility` for
  `com.kks999.FloatDude`, then added the installed app through System Settings.
- TCC retained its stale path lookup despite the scoped reset. A compatibility
  symlink at `~/Applications/FloatDude.app` now points to `/Applications/FloatDude.app`;
  it is not another executable copy. Keep that link while this host has the stale
  cached reference. The system list now displays FloatDude with its switch on.
- The running app stopped reporting missing Accessibility trust. Physical
  hotkey/selection acceptance is tracked separately from the permission switch.

Do not replace this installed binary after authorization without accounting for
ad-hoc signature changes. A later rebuild may require authorizing the new build;
the compatibility link repairs the path lookup, not signing continuity.

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
