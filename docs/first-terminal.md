# A Terminal for Your First One

Ocarina is for people whose first terminal is this one. Not a lighter version
of a developer terminal — a different product, aimed at someone who came from a
web interface, opened Terminal.app once, and closed it.

Everything below follows from one rule:

> **The terminal should never require you to already know the answer.**

A developer terminal assumes you know what to type, what broke, and what to
install. Every feature here exists because that assumption fails for the person
we are building for.

This document is the design. Nothing in it is built yet except where noted.

---

## 1. Quick Actions — "I didn't know how to install Claude"

The current path to installing an agent is: open a browser, find the docs, copy
a command you cannot read, come back, paste, hope. The browser trip is the
failure. A terminal for beginners should carry the twenty commands they will
actually need.

### Shape

A **Quick Actions** drawer (⌘K, and an always-visible button in the empty
state, which is where a new user is sitting). It lists recipes grouped by
intent, not by tool:

```
Install an AI coding agent
  Claude Code          curl -fsSL https://claude.ai/install.sh | bash
  Gemini CLI           …
  Codex CLI            …

Things Claude needs
  Homebrew, Node, Git, Python

Check what I have
  claude doctor · node --version · git --version
```

### Recipes are data, not code

```
Resources/Recipes/agents.json
~/.ocarina/recipes/*.json          # user's own
```

```json
{
  "id": "claude-code",
  "name": "Claude Code",
  "blurb": "Anthropic's coding agent. Runs in this terminal.",
  "command": "curl -fsSL https://claude.ai/install.sh | bash",
  "alternatives": [
    { "label": "Homebrew", "command": "brew install --cask claude-code" }
  ],
  "verify": "claude --version",
  "docs": "https://code.claude.com/docs/en/setup",
  "explain": "Downloads an installer from claude.ai and runs it. Puts the `claude` command in ~/.local/bin."
}
```

The Claude Code commands above are verified against
`code.claude.com/docs/en/setup`. **Every other recipe must be verified the same
way before it ships.** A wrong install command in a one-tap button is worse
than no button, because the person pressing it cannot tell it went wrong.

### Never a blind one-tap

Tapping a recipe does **not** execute it. It types the command into the
terminal at the prompt, and shows the `explain` line above it. The user presses
Return. That is deliberate, and it is the whole pedagogy of the feature:

- They see the command that ran, so next time they might type it themselves.
- Nothing runs that they did not trigger.
- `curl … | bash` is a pattern beginners should never be trained to trust
  blindly. Showing what it does, every time, is the honest version of
  convenience.

After it runs, the recipe's `verify` command tells the panel whether it worked,
and the row turns into a green check or an explained failure.

### Cost

The catalog goes stale. Mitigation: recipes carry a `docs` URL and a
`lastVerified` date, and a test asserts every bundled recipe has both. A stale
recipe is a bug with an owner, not a mystery.

---

## 2. The Task Panel — "I forget what I asked Claude to do"

A right-hand pane, per tab, listing what you asked the agent, trimmed to short
lines, checked off as each finishes.

### This is mostly already possible

Ocarina already reads agent transcripts to name tabs. The panel needs no new
plumbing — it needs a second reader over files the app opens anyway:

| Piece | Already exists |
|---|---|
| `~/.claude/projects/<slug>/*.jsonl` reader | `ClaudeTranscriptSource` |
| `~/.codex/sessions/**/rollout-*.jsonl` | `CodexTranscriptSource` |
| Streaming JSONL parse | `JSONLReader` |
| Long prompt → 2–4 word title | `TitleFormatter` |

### What the transcript actually gives us

Measured against the 14 transcripts on this machine:

| Field | Count | Use |
|---|---|---|
| `promptSource: "typed"` | 224 | A task. The human actually asked for this. |
| `promptSource: "queued" / "system" / "suggestion_accepted"` | 9 | **Not** tasks. Never list these. |
| `stop_reason: "end_turn"` | 258 | The turn finished. |
| `stop_reason: "tool_use"` | 5446 | Still working. |
| `isSidechain: true` | 0 | Subagent traffic. Exclude. |

So:

- **A task** is a user line with `promptSource == "typed"` and
  `isSidechain == false`, titled by `TitleFormatter.humanize`, keyed by `uuid`.
- **Running** is the newest task with no `end_turn` after it in that
  `sessionId`.
- **Finished** is any task with a later `end_turn`.

### One honest caveat, which changes the wording

`end_turn` means *the agent stopped talking*. It does not mean the work
succeeded, or that it did what you meant. So the panel must not print "Done" —
that is a claim it cannot support. It says **"Finished"**, and a task the agent
abandoned looks exactly like one it nailed.

If we want a real success signal we already have a better one: `TabActivity`
knows whether the last shell command exited non-zero, via `ShellIntegration`.
A finished turn whose last command failed can be flagged. That is a follow-up,
not v1.

### `TodoWrite` — the tempting wrong answer

Claude Code has a to-do tool, and its calls land in the transcript. It would be
the ideal source: real sub-tasks, real statuses, written by the agent.

**It appears zero times in all 14 transcripts here.** It is used at the model's
discretion, so a panel built on it is blank most of the time. Design: use typed
prompts as the spine, and *enrich* with `TodoWrite` sub-items when they happen
to be present. Never depend on them.

### Layout

Right pane, per tab. Not collapsible: it is there whenever an agent is in front
of the tab, and away when one is not. Empty state says what it is waiting for
rather than sitting blank.

---

## 3. Theming — "I want a Sakura theme"

The request is inclusivity: this should not look like it was made for one kind
of person. That means themes have to reach further than a colour swap, and the
codebase currently has colour literals scattered across eight files.

### What a theme actually has to cover

An audit of every colour and font decision in the app today:

| Surface | Where it lives now | Themeable via |
|---|---|---|
| 16 ANSI colours | SwiftTerm defaults | `terminalView.installColors([Color])` |
| Terminal text / background | `nativeForegroundColor`, `nativeBackgroundColor` (currently `.clear`) | same |
| Cursor | `caretColor`, `caretTextColor` | same |
| Selection | `selectedTextBackgroundColor` | same |
| Terminal font | SwiftTerm default | `terminalView.font: NSFont` |
| Sidebar panel | `TabSidebarView.metal` gradient | theme |
| Row hover / selected / border | white-opacity literals in `TabSidebarView` | theme |
| Status dot: idle/running/ok/failed | `StatusDot` | theme (semantic) |
| Tab icons | `TabIcon` process → SF Symbol + tint | theme (symbol map) |
| Departure board | `Palette` (lit, litDim, unlit, backdrop, amber) | theme |
| Accent: switch, focus ring, rename border | `Palette.litDim`, `Color.accentColor` | theme |
| Window material | `NSVisualEffectView` in `main.swift` | theme |

`Palette` already exists and is the seed of this. It becomes one field of a
`Theme` rather than a global.

### Structure

```swift
struct Theme: Codable, Identifiable {
    let id: String              // "sakura"
    let name: String            // "Sakura"
    let appearance: Appearance  // .light / .dark — drives NSAppearance too

    struct Terminal: Codable {
        let background, foreground, cursor, selection: Hex
        let ansi: [Hex]         // exactly 16
        let fontName: String    // must be fixed-pitch
        let fontSize: Double
    }

    struct Chrome: Codable {
        let panel: Gradient
        let rowHover, rowSelected, border, divider: Hex
        let textPrimary, textSecondary, textTertiary: Hex
        let accent: Hex
        let material: Material  // behind-window blur, or opaque
    }

    struct Semantic: Codable {
        let idle, running, succeeded, failed: Hex
    }

    struct Icons: Codable {
        let symbols: [String: String]   // "claude" -> "sparkles"
        let style: Style                // .sfSymbol / .emoji
    }
}
```

### Themes are files, so users can make their own

```
Sources/OcarinaUI/Resources/Themes/*.json   # bundled
~/.ocarina/themes/*.json                    # yours, hot-reloaded
```

A `ThemeStore` (`@Observable`, in the environment) holds the active theme;
selection persists in `UserDefaults`. Switching is live: chrome re-renders
because SwiftUI observes the store, and terminals are restyled by walking
`OcarinaModel.sessions` and re-applying to each `terminalView`. No relaunch.

### The two hard parts, stated plainly

**Legibility is not optional, and pretty themes break it.** A Sakura palette is
pale pink on cream, and dim ANSI yellow on it is invisible. Since the repo
already has a test culture, this is a test: every bundled theme must clear a
contrast floor (WCAG-ish, ~4.5:1 for normal text) for **all 16 ANSI colours plus
foreground against background**. A theme that fails does not ship. This is the
single most important thing in the theming work — a theme that makes error text
unreadable is actively dangerous for someone who cannot yet read errors.

**Fonts must be monospaced or the grid tears.** A terminal lays out on a
character cell. Validate with `NSFont.isFixedPitch` at load and reject with a
clear message rather than rendering garbage. Ship a small curated list rather
than a font picker over every font on the system.

### "Icons can become cuter"

`TabIcon` already maps a process name to a symbol and a tint, so a theme
supplies an override map. Two styles:

- **SF Symbols** — consistent, scalable, limited in cuteness.
- **Emoji** — genuinely expressive (🌸 for a Sakura shell, 🍵 for keep-awake),
  no asset pipeline, renders at any size.

Emoji is the honest way to get "cuter" without shipping and maintaining an icon
set per theme.

### Starter set

`Ocarina` (today's blues), `Sakura`, `Matcha`, `Paper` (light, high contrast),
`Mono` (no colour at all), `High Contrast` (accessibility, contrast ≥ 7:1).

---

## 4. Other things that frighten a first-time user

Not requested, but the same person hits all of these. Ordered by how often they
end a session in defeat.

**A pasted command they cannot read.** Pasting from the web is *the* beginner
workflow. A paste inspector — triggered on multi-line or `sudo`/`curl | bash`
pastes — that names what the command does before Return. Same mechanism as the
Quick Actions `explain`.

**Cryptic errors.** The app already knows the last command and its exit code
(`ShellIntegration`, `TabActivity`). When one fails, offer **"Explain this"**,
which sends the command and its output to whichever agent is installed. This is
arguably the single highest-value feature here: it turns every failure into a
lesson instead of a wall.

**Destructive commands.** `rm -rf`, `sudo`, `git push --force`, `> file` on
something that exists. Not a block — a one-line "this deletes X permanently"
with a confirm. Beginners cannot yet distinguish scary-looking from actually
dangerous.

**Not knowing anything is still running.** Handled better than most terminals
already: `StatusDot` pulses and tab names say what is happening. Extend to a
notification when a long job finishes while the app is in the background.

**Not knowing how to stop something.** Ctrl-C is not discoverable. A visible
stop button on a running tab.

**Not knowing where they are.** A cwd breadcrumb in the sidebar, not just in
`$PS1`.

**Nothing installed and no way to tell.** A "Check my setup" recipe that reports
what is present and offers the install for what is not.

---

## 5. Build order

Ordered by value to the target user per unit of work.

1. **Quick Actions** — solves the stated problem, needs no new data plumbing,
   and gives the empty state a purpose. Start with the verified Claude Code
   recipe and the setup check.
2. **Explain this error** — highest value-to-effort of anything here; the data
   is already tracked.
3. **Theming** — largest change, mostly mechanical: hoist the literals into
   `Theme`, add the store, write the contrast test, then themes are data.
4. **Task panel** — most novel, and the honest version is narrower than it
   first appears ("Finished", not "Done").
5. **Paste inspector and destructive-command confirms** — depend on the explain
   plumbing from 2.

Theming is third rather than first because it is the widest diff, and doing it
after 1 and 2 means those features get themed as they are written instead of
being retrofitted.
