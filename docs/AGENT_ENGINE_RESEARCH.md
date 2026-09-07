# Agent Engine research notes — 2026-09-07

These notes record the external contracts used for the implementation. They are
design inputs, not runtime dependencies.

## macOS window and background lifecycle

Apple documents floating window level as the standard level for palettes and
states that levels determine stacking before within-level ordering. `orderFrontRegardless`
can bring a window to the front without activating the application. `NSPanel`
defaults `hidesOnDeactivate` to true, while `NSWindow` defaults it to false, so a
persistent panel must set this explicitly. Collection behavior controls Spaces,
full screen, Mission Control, and Stage Manager; `canJoinAllApplications` is
specifically intended for floating windows and system overlays.

Implementation consequence: retain one panel, set floating level,
`hidesOnDeactivate = false`, `canHide = false`, join all Spaces/applications,
support full-screen auxiliary display, and re-order after active-space changes.
Click-away is not a close event. Screen changes and user movement re-constrain the
whole frame to `visibleFrame`.

Sources:

- [NSWindow levels](https://developer.apple.com/documentation/appkit/nswindow/level-swift.struct)
- [hidesOnDeactivate](https://developer.apple.com/documentation/appkit/nswindow/hidesondeactivate)
- [NSWindow collection behavior](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct)
- [canJoinAllApplications](https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct/canjoinallapplications)
- [SMAppService](https://developer.apple.com/documentation/servicemanagement/smappservice)
- [SMAppService.mainApp](https://developer.apple.com/documentation/servicemanagement/smappservice/mainapp)

Apple's supported macOS 13+ launch-at-login path is `SMAppService.mainApp` with
`register()`/`unregister()` and a system-owned status. FloatDude therefore exposes
an explicit Settings toggle and a link to Login Items rather than installing a
LaunchAgent file itself.

## Pi agent structure

Pi's agent core keeps a state containing a system prompt, model, tools, messages,
stream state, pending tool calls, and an optional session ID. It exposes message
replacement/append/clear operations and a context-transform hook. The coding
agent builds a system prompt from the active tools and their guidelines, then
appends project/user context. Tools are an explicit runtime list rather than
abilities inferred from prose.

Implementation consequence: FloatDude separates immutable software policy,
editable user instructions, durable messages, current turn context, and the tool
registry. The session UUID is stable across turns. Only registered tool schemas
are sent to the provider, and the runtime rejects unknown tool names.

Sources:

- [Pi agent core README](https://github.com/badlogic/pi-mono/blob/main/packages/agent/README.md)
- [Pi system prompt builder](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/src/core/system-prompt.ts)
- [Pi SDK tool selection](https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/src/core/sdk.ts)
- [Pi provider/session and cache options](https://github.com/badlogic/pi-mono/blob/main/packages/ai/src/types.ts)

## Prompt caching

Provider caching is prefix-sensitive. A changed byte early in the prompt prevents
reuse after that point. The stable software root and tool schemas therefore come
first; user customization follows; history grows by appending; current selection,
attachment index, action, and question stay last.

Official Anthropic requests mark the stable root block with ephemeral cache
control. Official OpenAI requests use a conversation-stable cache key and request
24-hour retention. Compatible endpoints receive neither extension because some
Anthropic-compatible services reject `cache_control` inside otherwise valid payloads.
The stable ordering still permits transparent caching by compatible providers.

Sources:

- [Anthropic prompt-caching guidance](https://github.com/anthropics/skills/blob/main/skills/claude-api/shared/prompt-caching.md)
- [OpenAI API data controls and prompt-cache retention](https://platform.openai.com/docs/models/default-usage-policies-by-endpoint)
- [Pi cache retention and session ID](https://github.com/badlogic/pi-mono/blob/main/packages/ai/src/types.ts)

## Harness engineering

OpenAI's account of harness engineering emphasizes making the environment
legible, building missing capabilities as enforceable primitives, and turning
failures into feedback loops rather than repeated prompting. FloatDude encodes the
requested safety boundary in schemas and filesystem roots: attachment read by UUID,
managed text write by safe filename, eight tool passes, explicit errors, deterministic
tests, and no local-control tools.

Source:

- [Harness engineering: leveraging Codex in an agent-first world](https://openai.com/index/harness-engineering/)
