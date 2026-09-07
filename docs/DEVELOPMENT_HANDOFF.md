# FloatDude Agent Engine — development handoff

## Delivered foundation

1. Persistent always-on-top macOS panel with explicit close behavior and screen-safe placement.
2. Local multi-turn conversations with new/select/delete session management.
3. Explicit attachment import from the panel for PDF, Markdown/text, Word, and modern spreadsheets.
4. OpenAI Chat Completions and Anthropic Messages streaming agent loops.
5. Exactly two native tools: managed attachment `read` and managed artifact `write`.
6. Stable protected software root, optional user system instructions, and provider-aware prompt caching.
7. `/models` connectivity test in Settings.
8. Optional launch-at-login management through `SMAppService.mainApp`.
9. Settings-only English / Simplified Chinese display switch, persisted with
   non-secret preferences and applied immediately.
10. Process-scoped `AXObserver` selected-text notifications with AX-only
   polling fallback for live pending-context updates.

## Security boundaries

- No shell, browser, computer-use, arbitrary local filesystem, process, permission, deletion, move, or messaging tool.
- `read` accepts only an attachment UUID recorded in the active conversation.
- `write` rejects path separators, traversal, control characters, and extensions other than `.md`/`.txt`.
- Tool writes use owner-only `0600` permissions inside Application Support/FloatDude/Exports.
- Captured selections remain ephemeral; only typed user turns and assistant responses enter conversation history.
- API keys remain process memory or opt-in Keychain data and are redacted from errors.
- Remember-mode startup never blocks the menu-bar main thread; code-identity mismatch requires explicit re-application in Settings.

## Provider contract

```text
OpenAI Chat Completions:
POST {Base URL}/v1/chat/completions
tools = [read, write]

Anthropic Messages:
POST {Base URL}/v1/messages
tools = [read, write]

Connectivity:
GET {Base URL}/v1/models
```

Compatible providers receive no OpenAI/Anthropic cache extension fields unless
their host is the official provider. The Root Prompt and tool schemas remain
byte-stable so provider-side automatic prefix caching can still work.

## Follow-on work

- Add scanned-PDF OCR only after selecting an explicit local Vision workflow and resource budget.
- Add context compaction when real conversations approach provider context limits; preserve the stable prefix.
- Add visible per-tool progress and export reveal actions after real provider acceptance.
- Add signed/notarized distribution so Accessibility and login-item identity survives binary updates.
- Do not add further tools until each has a narrow schema, explicit resource boundary, and deterministic tests.
