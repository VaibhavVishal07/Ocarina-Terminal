# Ocarina Terminal

A terminal for macOS, written in Swift.

Tabs are named after what they are *doing*, not after the binary running inside
them — so a strip of twenty terminals reads as a task list instead of a column
of `zsh` and `Claude`.

## Design docs

- [Context-Aware Tab Naming](docs/context-aware-tab-naming.md) — how tab titles
  are derived from terminal activity and from terminal-based LLM sessions.

## Package layout

`OcarinaTerminalContext` is the naming subsystem. It holds no PTY state and does
no rendering — it takes a `TerminalSessionSnapshot`, asks each provider what the
terminal is doing, and folds the strongest answer into a `TabContext`.

```
Sources/OcarinaTerminalContext/
  ContextSource.swift            priority chain: shell < project < command < llm < manual
  ContextObservation.swift       one provider's reading, with a confidence
  TabContext.swift               per-tab naming state; displayTitle / subtitle
  TabNamingEngine.swift          the stability rules (dwell, margin, no demotion)
  TabContextCoordinator.swift    actor that runs the provider chain per tab
  TitleFormatter.swift           local text -> 2-4 word title. No model, no network.
  Providers/
    LLMSessionContextProvider    shared agent provider; Claude / Codex / Gemini / OpenCode
    ClaudeTranscriptSource       ~/.claude/projects/<slug>/*.jsonl
    CodexTranscriptSource        ~/.codex/sessions/**/rollout-*.jsonl
    GenericProcessContextProvider foreground argv -> title
  Session/
    ProcessInspector             tcgetpgrp + sysctl: what owns the pty right now
    OSCTitleParser               streaming ESC ] 0;title BEL reader
    TerminalSessionMonitor       one pty -> TerminalSessionSnapshot
    TabNamingService             poll loop; publishes tabs whose title changed
```

Wiring a tab:

```swift
let service = TabNamingService()
await service.attach(TerminalSessionMonitor(ptyDescriptor: primaryFD, shellName: "zsh"))
await service.start()

for await tab in await service.updates() {
    tabStrip.rename(tab.tabID, to: tab.displayTitle, subtitle: tab.subtitle)
}
```

The renderer can forward the bytes it already reads to `monitor.ingest(_:)` so
programs that set their own title are picked up; nothing else is read from the
terminal, and nothing leaves the machine.

## The app

```
Sources/OcarinaUI/       SwiftUI layer
  TerminalSession        one tab: pty + SwiftTerm view + naming monitor
  OcarinaModel           open tabs, selection, renames, title updates
  TabStripView           task as the title; process on hover
  CommandPaletteView     jump by what a terminal is doing (⇧⌘P)
  EmptyStateView         no tabs open: the departure board
  DotMatrix              5x7 dot-matrix panel, the board is built from it
  OcarinaIcon            the bundled app mark, trimmed of its plate
  TabIcon                a symbol for whatever the tab is running
  SleepGuard             holds the Mac awake while Ocarina is open
  MainMenu               the menu bar; where ⌘T / ⌘W / ⇧⌘P actually live
  ToolTip                AppKit tool tips, because .help draws none here
Sources/Ocarina/         executable entry point
```

SwiftTerm is used only as the VT parser and screen grid. Ocarina spawns the pty
itself, via `forkpty`, because `login_tty` is what makes the pty the child's
controlling terminal — and without that `tcgetpgrp` reports nothing and the
naming layer is blind.

```
swift build
swift test
swift run Ocarina
```

## Building the app

```
Scripts/make-app.sh          # release
Scripts/make-app.sh debug    # debug
open build/Ocarina.app
```

`swift run Ocarina` still works and is fine for development, but it runs
unbundled: generic icon, and no Finder integration.

One behaviour differs between the two. A binary run from a shell inherits that
shell's directory, so tabs opened where you were; an app launched from Finder
inherits `/`, and every new tab opened at the root of the disk and was named
for it. A session with no directory of its own now starts at home.

## Tool tips

Three mechanisms were tried. SwiftUI's `.help` produces nothing in a plain
`NSHostingController` — walk the view tree and there is no tool tip on it at
all. AppKit's `NSView.toolTip` *is* installed, on a view that hit-tests at the
right frame, and still never appears: the tool tip manager needs mouse-moved
events to reach the view under the cursor, and inside a hosting view they do not
arrive. A SwiftUI bubble drawn by the control itself is then clipped away by the
scroll view the tabs sit in.

So a control only reports hover, through a tracking area on the small `NSView`
that already takes its click, and the strip draws the bubble in its own
coordinate space — outside the scroller, and above the terminal by `zIndex`.

Tab titles are capped at 24 characters for display, ellipsis included, so one
long name cannot push the strip around. The tab keeps its full name for
renaming, for the hover subtitle and for the command palette.

## The child environment

A terminal inherits the environment of whatever launched it, and passes it to
every shell it spawns. Launched from inside another tool's session that means
handing each shell the identity of that session — nested tools then believe
they are running as a child of their own parent, which is why Claude Code
reported that transcript saving was off. One of the inherited variables is a
messaging token, which has no business reaching an arbitrary shell.

`PTYProcess` drops those markers before the fork. Only session identity goes:
credentials and configuration a user exports for their own use are theirs and
are left alone.

## Icons and glass

The app icon is `Icons/AppIcon.png`. **Run `Scripts/make-app.sh` to get it.**

A bare SwiftPM executable has no bundle, so macOS has nowhere to read an icon
from and falls back to the generic Unix-executable picture. Setting
`applicationIconImage` is the only lever without a bundle and it does not reach
Finder, the app switcher or Get Info — which is why `swift run Ocarina` still
looks generic. The script assembles a real `Ocarina.app`: an `Info.plist`, an
`AppIcon.icns` generated from the PNG, the SwiftPM resource bundles, and an
ad-hoc signature. The icon is then correct everywhere.

`applicationIconImage` is kept anyway, so the unbundled binary is not a total
loss.

`OcarinaIcon` trims the art to its drawn content, clips the corners to
transparency and lays it on a clear canvas at the ~80% the macOS icon grid
expects. That preparation exists because an earlier icon was an opaque black
plate with the tile drawn inside it: used as-is it made the dock icon read as a
small tile in a dark square. The invariant worth keeping is that preparation
adds margin around the art and never eats into it — trimming a 512px plate once
produced a 424px icon, which is what the test pins.

Tabs do **not** use the app icon. Every tab carrying the same picture said
nothing; `TabIcon` gives each one a symbol for its foreground process, so Claude
Code reads differently from a shell at a prompt across a strip of twenty. It
matches on the naming layer's `processName`, which is a provider's display name
when one recognised the process and the bare executable otherwise, so both forms
are handled.

Glass needs something behind it to blur. An `NSVisualEffectView` sits behind the
hosting view and the window is non-opaque, so the materials in the chrome have
the desktop to work with; without it they resolve to flat grey. The terminal
view's own background is cleared and a 72% black bed sits behind it — the glass
reads through, and the text stays legible.

## Keyboard shortcuts

⌘T, ⌘W and ⇧⌘P come from the menu bar in `MainMenu`, not from SwiftUI
`.keyboardShortcut`. AppKit offers a key equivalent to the main menu before the
event reaches the window or the responder chain, so a menu item always gets it;
a hidden SwiftUI button only sees what makes it as far as the view hierarchy,
which a terminal view holding first responder can swallow. Ocarina had no main
menu at all for a while, which is why ⌘W did nothing — and why ⌘Q didn't either.

The Edit menu's cut/copy/paste have no target, so they travel the responder
chain to SwiftTerm, which implements them.

## Keeping the Mac awake

Ocarina holds a `PreventUserIdleDisplaySleep` assertion — the same one
`caffeinate -d` takes — for as long as it is open. It is **on by default**: a
terminal is usually waiting on something long, and a display that sleeps through
the build is never what was wanted. The point is to stop needing a `caffeinate`
parked in a spare tab.

The cup in the tab strip says whether the assertion is actually held, and
toggles it. `isHolding` is tracked separately from `isEnabled` because the
system can refuse an assertion, and the cup must not claim the Mac is being kept
awake when it is not.

The assertion is named, so it is never a mystery which app is doing this:

```
$ pmset -g assertions
   pid 62530(Ocarina): [0x0001ec3a00058822] PreventUserIdleDisplaySleep named: "Ocarina is open"
```

The kernel drops a process's assertions when it exits, so quitting Ocarina
always gives it back, including on a crash.

## The empty state

Close every tab and the window is given over to a dot-matrix panel: a wordmark,
one lit call to action, and the two shortcuts that still mean something with no
terminal open.

It borrows the look of an airport departures board but not its furniture. A
clock, gate numbers and an ON TIME column are what such a board carries because
a flight has a time and a status; a terminal that does not exist yet has
neither, so drawing them was decoration dressed up as information. What earns
its place is the matrix itself.

`DotMatrix` carries a 5x7 font and paints **every** cell of the grid, dark when
it is off. That is the whole character of the thing: the unlit dots stay visible
behind the words, so the text reads as lamps that happen to be on rather than as
glyphs floating on black. Characters are five cells wide with one blank column
between them, so padding two strings to the same length is all it takes to make
their columns line up — no layout code is involved, and it is why the shortcut
rows are padded to a common width rather than centred independently.

One catch: a `Spacer` inside the call to action stretches it across the whole
window, since the stack it sits in is full width. Fixed spacing lets the row
size to its own content.
