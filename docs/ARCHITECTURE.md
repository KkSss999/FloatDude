# Architecture boundary — Agent Engine foundation

## Principle

FloatDude is a local-first conversational agent in a compact, persistent macOS panel.

```text
Global shortcut / menu-bar action
  → synchronous selection + capability snapshot
  → persistent floating panel
  → last active conversation + live AX-only selection synchronization
  → active conversation + optional attachments
  → stable software root + user instructions + history + current turn
  → provider stream ↔ bounded read/write tool loop
  → Markdown response + durable conversation archive
```

The model has no shell, browser, computer-use, process, permission, delete, move,
message, or arbitrary-path tool. The two native tools are mechanically fixed:

- `read`: extract bounded text from a file the user explicitly attached to this conversation.
- `write`: create a UTF-8 `.md` or `.txt` artifact in FloatDude's managed Exports directory.

## Ownership

| Area | Responsibility |
| --- | --- |
| `Agent` | conversation models/archive, stable software root, attachment ingestion and extraction, read/write tool enforcement |
| `App` | menu-bar lifecycle, active conversation coordination, turn state and panel sizing |
| `UI` | persistent panel, transcript/session controls, attachment picker, Markdown response, Settings |
| `System` | Carbon hotkey, Accessibility capture, deterministic placement, AppKit panel, login-item management |
| `AI` | OpenAI Chat Completions and Anthropic Messages adapters, SSE, tool loop, cache controls, `/models` probe |
| `Storage` | UserDefaults preferences, JSON conversations, managed attachments/exports, Keychain credentials |
| `Core` | shared action and error types |

## Prompt and cache contract

Request prefix order is stable by construction:

1. provider tool definitions (`read`, `write`);
2. `SoftwareRootPrompt.text`, identified by a versioned constant;
3. optional user system instructions from Settings;
4. ordered conversation history;
5. the current action, captured context, attachment index, and user message.

The software root is absent from product Settings and cannot be replaced by user
content. User instructions refine language, tone, and output preferences but cannot
expand tool authority. Official OpenAI requests use a conversation-stable cache key
and 24-hour retention preference. Official Anthropic requests place an ephemeral
cache breakpoint on the stable root block. Compatible endpoints receive the same
stable prefix without vendor-specific fields they may reject.

## Conversation and privacy contract

- Conversations and explicit attachment metadata persist locally under Application Support.
- Selected text and clipboard fallback remain ephemeral and are not written into conversation history.
- The persisted active conversation is reopened by the next shortcut and its UI
  scrolls to the latest turn. Creating or selecting a conversation carries the
  current safe selection as ephemeral pending context; it does not persist that
  text until the user sends a turn.
- While the panel is open, an `AXObserver` follows the frontmost source
  application and its focused element. `AXSelectedTextChanged` is delivered
  immediately when the app supports it; a 300 ms AX-only sampler remains as a
  fallback for apps that omit selection notifications. Neither path reads the
  clipboard, so unrelated clipboard changes cannot enter a conversation context.
- A deselection notification from an observed external process clears pending
  context and Rewrite eligibility. Focus in FloatDude itself and unproven
  polling misses do not clear a user's pending text.
- Feishu enables `AXManualAccessibility` before capture and searches a bounded
  parent/child neighborhood around the focused AX element, covering Chromium
  renderers that expose selected text through an `AXWebArea` rather than the
  focused group.
- If that direct read still fails, a Feishu-only hotkey fallback snapshots the
  selected text through Cmd-C, detects a new pasteboard change, and restores the
  complete prior pasteboard. It is not a background capability and is never used
  for other applications. This fallback is intentionally **not live selection
  synchronization**: it captures only the selection that exists when the user
  invokes FloatDude's shortcut.
- User prompts and assistant answers persist so subsequent turns receive ordered history.
- Attachments are copied into a conversation-specific managed directory after type, size, and extraction validation.
- Deleting a conversation removes its managed attachment copies after explicit UI confirmation.
- Credentials remain outside conversation files, prompts, errors, logs, and URLs.
- Remembered credentials load outside the main actor. A code-identity marker prevents an outdated ad-hoc ACL from being queried after rebuilds, and Keychain reads prohibit authentication UI.

## Window contract

- One retained `NSPanel` owns the entire interaction.
- Clicking another application does not dismiss or cancel it.
- `hidesOnDeactivate` and `canHide` are false; floating level keeps it above normal windows.
- It joins all Spaces and eligible full-screen/Stage Manager application sets.
- Repeated shortcut raises the existing panel without changing a user-moved position.
- The requested canvas is capped at the iPhone 17 Pro Max HIG size (440 × 956
  pt) at 1080p and above, then scales proportionally on smaller displays before
  safe-frame fitting.
- Screen/Space changes and completed drags constrain the full frame to the display's visible frame.
- The complete active transcript uses one scroll surface, an explicit jump-to-
  latest button, and a hover-expandable message map whose ticks are direct scroll
  targets. Only user turns create map ticks; assistant messages stay readable in
  the transcript but do not clutter navigation.
- `Esc`, the close button, application termination, and explicit programmatic dismissal remain close paths.

## Agent loop contract

- A provider turn may request tools, receive results, and continue for at most eight passes.
- OpenAI streamed `tool_calls` and Anthropic streamed `tool_use` blocks are accumulated before execution.
- Tool errors return to the model as errors and are never presented as successful content.
- Stream completion still requires `[DONE]` or `message_stop`; early EOF is an error.
- Cancellation stops the active provider response and discards late deltas.

## Attachments

Supported input is PDF with extractable text, Markdown, UTF-8 text, Word
(`.doc`, `.docx`, RTF/RTFD/ODT), XLSX, CSV, and TSV. XLSX extraction reads shared
strings and worksheet cells from the ZIP/XML container. Scanned PDF OCR, legacy
binary `.xls`, macros, embedded media, formulas-as-formulas, and workbook rendering
are outside this foundation; extracted cached values remain available as text.

## Concurrency

- UI, Settings, conversation mutation, and AppKit lifecycle run on `MainActor`.
- Accessibility capture is short and synchronous inside the hot-key event so source focus cannot race; the later live sampler is AX-only and ignored during streaming.
- Attachment copy/extraction runs outside the main actor and publishes results to the active conversation.
- Network streaming and tool passes use structured tasks with cancellation propagation.
