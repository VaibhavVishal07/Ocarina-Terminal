# Context-Aware Tab Naming

Status: Draft — core implemented in `MajoraTerminalContext`
Target: Majora (Swift, macOS)

## Problem

A terminal tab named after its shell, binary, or working directory tells the user
almost nothing. With 15–20 tabs open, the tab strip degenerates into:

```
Claude   Claude   Claude   Claude   zsh   zsh
```

The user cannot tell these apart, so tab names stop being a navigation aid and
spatial memory never forms.

The tab title should answer **"what is this terminal doing?"** — not
**"what binary is running in it?"**

## Goal

Tab titles update automatically from what is actually happening inside the
terminal, so the tab strip reads as a task list:

```
Fix Payment Failure   Portfolio Animation   Search API Latency   Add Watchlist API
```

The running process is metadata, shown as secondary information.

---

## Behaviour

### Initial title

A new terminal may start with any of, in order of availability:

- a manually provided name
- the current project / folder name (`xstream-play`)
- the shell name

### Activity-driven titles

Once meaningful activity begins, the title is regenerated from that activity.

| Activity | Title |
| --- | --- |
| `npm run dev` | `Dev Server` |
| `python generate_report.py` | `Generate Report` |
| `ssh production-api` | `Production API` |

### LLM-session titles

Terminal-based coding agents (Claude Code, Codex, Gemini CLI, OpenCode, and
others) are the case this feature exists for. The executable name is metadata;
the **task stated in the conversation** is the title.

| Conversation opener | Title |
| --- | --- |
| "Fix the payment failure state on the checkout page." | `Fix Payment Failure` |
| "Refactor the authentication service to support refresh tokens." | `Refactor Auth Service` |
| "Create the homepage animation for the portfolio." | `Portfolio Animation` |
| "Investigate why search API latency increased." | `Search API Latency` |

---

## Title generation principles

Generated titles are:

- short — approximately 2–5 words
- descriptive and action-oriented where it fits
- easy to scan
- specific enough to distinguish two similar sessions

**Good:** `Fix Login Redirect` · `Build Pricing Page` · `Debug Search API` ·
`Refactor Player State` · `Add SSH Support`

**Bad:** `Claude` · `Coding` · `Working` · `Terminal 4` · `Fixing Some Issues` ·
`Help With Homepage Development`

Never generate a sentence-length title.

---

## Context priority

The displayed title resolves in this order. The first available source wins.

1. Manual tab name
2. Explicit task detected from an active LLM session
3. Current foreground command
4. Current project / directory
5. Shell name

**Manual names always win.** If the user renames a tab by hand, automatic
naming switches off for that tab and stays off until the user explicitly
re-enables it.

---

## Dynamic updates and stability

The title is allowed to evolve as the session's work changes:

```
xstream-play  →  Claude  →  Debug Audio Switching  →  Subtitle Picker
```

But it must feel *stable*. The user is building spatial memory around these
names, and a title that churns is worse than a title that is slightly stale.

Rules:

- Update only on a **meaningful context shift**, never on every prompt.
- Require a **confidence threshold** to overwrite an existing contextual title —
  a higher bar to replace a good title than to set the first one.
- Apply a minimum dwell time before a title may be replaced again.

Avoid this:

```
Fix Player  →  Player Issue  →  Playback Bug  →  Fix Audio     (within minutes)
```

Prefer holding `Fix Playback Issue` until the task genuinely changes.

---

## Architecture

Context detection is provider-agnostic. Do not build the feature around Claude
Code specifically.

```swift
protocol TerminalContextProvider {
    /// Cheap check: can this provider say anything about this session?
    func canHandle(_ session: TerminalSession) -> Bool

    /// Produce a context observation, or nil if nothing meaningful is available.
    func context(for session: TerminalSession) async -> ContextObservation?
}
```

Implementations:

- `ClaudeContextProvider`
- `CodexContextProvider`
- `GeminiContextProvider`
- `GenericProcessContextProvider` — foreground command, project, shell

Providers are consulted in priority order; their observations feed a single
`TabContext` model.

### Detection signals

A provider may use any of:

- process name
- child processes
- terminal title escape sequences
- command invocation and arguments
- structured output patterns
- shell integration hooks
- optional first-party integrations with supported tools, where a tool exposes
  local session metadata

### TabContext model

```swift
struct TabContext {
    var displayTitle: String        // what the UI renders
    var generatedTitle: String?     // latest automatic title
    var manualTitle: String?        // user-set; overrides everything

    var processName: String?
    var activeTask: String?
    var projectName: String?
    var workingDirectory: URL?

    var contextSource: ContextSource
    var contextConfidence: Double
    var lastContextUpdate: Date
    var isAutoNamingEnabled: Bool
}
```

`TabContext` lives **separately from the PTY rendering layer**. The renderer
does not own naming state, and naming does not reach into the renderer.

---

## Privacy

Context-aware naming happens **locally**.

- Terminal content is never sent to an external server purely to generate a tab
  title.
- Where an LLM tool already exposes local session metadata, use that metadata
  in preference to inspecting output.
- Do not introduce a cloud LLM dependency just to name tabs.

---

## Visual treatment

The contextual task is the primary title. The underlying process is secondary.

Tab:

```
Fix Payment Flow
```

On hover:

```
Claude Code · ~/Projects/checkout
```

Command palette:

```
Fix Payment Flow
Claude Code · checkout
```

The user gets both **what this terminal is doing** and **what is running inside
it** — with the first prioritised everywhere in the primary UI.

---

## Implementation status

Built (`Sources/MajoraTerminalContext`, 39 tests):

- `TabContext`, `ContextObservation`, `ContextSource` priority chain
- `TabNamingEngine` — confidence floor, dwell window, replacement margin, no
  demotion to a weaker source
- `LLMSessionContextProvider` + `GenericProcessContextProvider`
- Claude Code and Codex transcript readers, against their real on-disk formats
- `ProcessInspector`, `OSCTitleParser`, `TerminalSessionMonitor`,
  `PTYProcess`, `TabNamingService` — live pty to title, covered by tests that
  spawn a real child process on a real pty
- A SwiftUI app: tab strip with the task as the title and the process on hover,
  a command palette that searches both, double-click and context-menu rename

Outstanding:

- Gemini CLI and OpenCode session formats are unverified; both providers ship
  with `UnavailableTranscriptSource` and detect the process only.
- Confidence and dwell constants are placeholders pending real-session tuning.
- The app runs as a plain SwiftPM executable; it is not yet an `.app` bundle,
  so it has no menu bar, Dock identity or app icon.
- Tab reordering, splits and persistence across launches.
