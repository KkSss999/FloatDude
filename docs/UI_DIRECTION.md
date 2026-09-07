# UI direction — Adaptive Glass

**Status:** accepted for FloatDude v0.1.0
**Decision:** FloatDude uses one adaptive glass visual system with a Light and Dark appearance. It follows the current macOS appearance; dark mode is not the permanent brand expression.

## Visual references

| Light Glass | Dark Glass |
| --- | --- |
| ![Light Glass reference](design/floatdude-light-glass-reference.png) | ![Dark Glass reference](design/floatdude-dark-glass-reference.png) |

These images establish material, hierarchy, and tone—not pixel-perfect copy, icons, or geometry. Use SF Symbols or a future approved brand asset; do not ship generated icons or text from the references.

## Product principle

> **Adaptive Glass, One-Breath Motion.**

FloatDude should feel like a small piece of macOS material briefly rising above the user’s work. It appears near the cursor, handles one request, and leaves. It must never read as a permanent chat client, dashboard, or secondary workspace.

## Appearance contract

| Element | Light Glass | Dark Glass |
| --- | --- | --- |
| Primary material | Frosted pearl-white with subtle blue-gray refraction | Translucent graphite-indigo, never pure black |
| Main text | Warm charcoal | Soft white |
| Secondary text and dividers | Cool gray | Desaturated lavender-gray |
| Active action | Restrained coral, plus label and underline | Same coral, tuned for contrast |
| Edge aura | Low-opacity lavender-blue, visible only against the panel edge | Same hue, slightly brighter but never neon |

- v0.1 follows the system Light/Dark setting. Do not add a manual theme picker until there is a user reason to override macOS.
- Use native vibrancy/material APIs where possible, with an opaque high-contrast fallback for Reduce Transparency.
- Color never carries state alone: the active action also has an underline and stronger text treatment.
- Body text, actions, and errors must meet a minimum 4.5:1 contrast ratio in both appearances.

## Panel structure

The visual references suggest an upper bubble and a response sheet. The implementation must render this as **one `NSPanel`** with a single focus and dismissal lifecycle. The small waist/light point is an optional expansion transition, not a second window.

| State | Target size | Required content |
| --- | --- | --- |
| No context | 400 pt wide; 132–176 pt high | Brand mark, `Ask FloatDude…`, action row |
| Context captured | 400 pt wide; 196–236 pt high | Two-line selected-text preview, actions, ask field |
| Streaming/completed | 400 pt wide; grows to 420 pt high | Existing context/action area, response, Copy |
| Long response | 400 pt wide; 420 pt max | Response becomes internally scrollable; panel never grows further |
| Error | 400 pt wide; 196–260 pt high | Actionable error, retry, and Settings path when relevant |

- Permit a width range of 336–456 pt for small displays and accessibility text sizes.
- When Accessibility provides selection bounds, anchor the panel to that selection: below first, then above or beside it without covering the text. Fall back to the pointer only when selection geometry is unavailable. Keep the panel fully on the active display.
- Use the valid selection's display and a fixed below/above/right/left candidate order. Reject invalid or off-screen bounds before pointer fallback.
- Truncate previews after two lines; preserve the complete captured text for the model request, not for visible UI.
- Settings belong in the menu-bar item or a dedicated Settings scene, never in the task panel.

## Interaction hierarchy

1. Selected text or a direct prompt is the context.
2. With captured text, tapping `Explain` or `Translate` starts that action immediately. Show `Rewrite` only when `AXSelectedText` is settable on the captured element.
3. `Ask anything…` always dispatches the Ask action, not whichever quick action was last selected.
4. On first output token, the same panel grows downward and renders native Markdown.
5. `Copy` copies only final visible response text. `Esc`, click-away, or a repeated shortcut cancels active streaming and dismisses the panel.

## Motion and restraint

- Opening: 180–220 ms scale/fade from the pointer-adjacent anchor.
- Expanding to response: 220–280 ms vertical resize, preserving the panel’s top anchor whenever screen bounds allow.
- Dismissal: 120–160 ms fade/scale; no bounce, particle, or mascot animation.
- Reduce Motion replaces size/scale animation with a short opacity transition.
- Use a single faint connection glow only during expansion. It disappears once the response settles.

## Non-negotiable exclusions

- No persistent two-panel layout.
- No large initial window, sidebar, tabs, history list, avatars, chat bubbles, or dashboard cards.
- No hard-coded dark theme, black glass, thick borders, or decorative gradients.
- No stored selected text or answer history in v0.1.

## Design acceptance

- Switching macOS appearance while the panel is visible updates material, text, controls, and focus indicators without restart.
- Light and Dark states preserve the same layout and action hierarchy.
- With Reduce Transparency or Increase Contrast enabled, controls and body copy remain unambiguous and legible.
- At 200% accessibility text sizing, the panel remains within the active display and response content scrolls rather than clipping.
- The screen recording demo must clearly show: shortcut → selection preview → action → one-panel expansion → Copy/Esc.

## Native glass refinement (2026-09-07)

The task surface uses one native optical background layer. After testing against
real work windows, readability takes priority over transmitting sharp background
text: macOS 26+ uses full `.regular` Liquid Glass, without a transmission mask.
A neutral backing (42% light / 52% dark) limits background interference; Increase
Contrast strengthens it further. Foreground text and controls are never faded.
The rim light and restrained shadow preserve separation from the desktop.
macOS 14/15 use AppKit behind-window vibrancy with a directional rim. This
requires Xcode 26+ to build; the deployment target remains macOS 14.

Inside the shell, the selection is a two-line quotation with a source caption,
the ask field is the main inset, and quick actions share one quiet row. Active
actions use coral plus a checkmark (replacing the earlier underline). Responses
sit directly on the surface below a hairline separator, without a second card
or repeated status headings. The close control is an actual accessible button. The title strip has an
explicit AppKit drag region, separate from close, selection and input controls;
its mouse events move the same NSPanel without routing through the ScrollView.
An outer scroll region keeps recovery guidance and controls reachable within
the bounded panel; long answers also scroll within their response region.

Reduce Transparency switches to opaque system colors. Increase Contrast adds a
stronger outer boundary and input edges. Native window resizing now observes
Reduce Motion as well as the SwiftUI transitions. These paths still require
real macOS accessibility-setting acceptance; a screenshot is not a contrast
measurement or a full accessibility audit.

Run `./Scripts/run-glass-preview.sh` for isolated native sample windows (light,
dark, direct input, and an increased-contrast appearance). Its background picker
switches between daylight, a dark desktop, and dense text so transmission and
reading-area interference can be checked on the same native windows. The preview uses
synthetic content, does not start AppRuntime or access clipboard/credentials,
and makes no network requests. Close it with Quit from its application menu or
stop the script. The background is a review fixture, not a shipped app screen.

Technical inspiration: [Appllama/liquid-glass-screens](https://github.com/Appllama/liquid-glass-screens),
particularly the distinction between background optics and rim light. No shader,
artwork, animation, or source code from that repository is included.
