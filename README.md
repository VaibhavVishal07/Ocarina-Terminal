<div align="center">

<img src="docs/images/icon.png" width="104" alt="Ocarina">

# Ocarina Terminal

**A macOS terminal that names its own tabs after what they are doing.**

</div>

<img src="docs/images/window.png" alt="The Ocarina window: tab sidebar, terminal, task panel">

Twenty terminals open and every one of them called `zsh` is not a list, it is a
guessing game. Ocarina reads what each tab is actually doing — the foreground
process, the project directory, the prompt you gave an agent — and puts *that*
on the tab. The sidebar becomes something you can read down.

Nothing leaves the machine. Titles are derived locally, from files the tools
already write.

- [Your first terminal](docs/first-terminal.md) — for people who have never
  opened one.
- [Context-aware tab naming](docs/context-aware-tab-naming.md) — how titles are
  derived, and how conflicts are settled.

## Running it

```
swift build
swift test
swift run Ocarina
```

`swift run` is fine for development, but it runs unbundled: generic icon, no
Finder integration. For the real thing:

```
Scripts/make-app.sh          # release -> build/Ocarina.app
Scripts/make-app.sh debug    # a separate "Ocarina Test Build.app"
open build/Ocarina.app
```

The debug build is a *separate app*, not the same one rebuilt: its own name,
bundle identifier and executable name. Sharing any of the three meant Launch
Services, the Dock and ⌘-Tab could not tell a test build from the installed one.

One behaviour differs between bundled and not. A binary run from a shell
inherits that shell's directory, so tabs opened where you were; an app launched
from Finder inherits `/`, and every new tab opened at the root of the disk and
was named for it. A session with no directory of its own starts at home.

## What is in the window

**The sidebar** carries the tabs, each with a status dot — idle, running,
succeeded, failed — and a symbol for whatever is running in it. Below them sit the theme
picker and the keep-awake switch.

**The task panel** on the right lists what you have asked the agent in this tab,
read from the transcript the agent writes anyway. It costs the session nothing
and it survives scrollback, which is the point: you gave an agent five things
across twenty minutes and cannot remember which of them it got to.

It is always open. It used to be a drawer behind a notch, and the notch was
the problem — as a column it animated the terminal's *width*, and every frame
of that resize was an `ioctl(TIOCSWINSZ)` and a SIGWINCH, so the shell repainted
its prompt through the length of the slide.

`TaskSummariser` asks Claude to rewrite the heuristic titles, because it is
better at it: "Toggle option near right-hand" becomes "Move toggle to right
side". Three rules follow from where that work happens.

- The local condenser runs first, so a title is on screen immediately and a
  machine with no agent installed loses nothing it had.
- Every prompt is asked about once, ever, cached on disk by the transcript's own
  uuid. This spends your Claude allowance.
- **It waits for a keystroke.** Running the `claude` binary means a subprocess,
  and a subprocess inherits the app's TCC identity — every protected thing it
  reads is asked about in Ocarina's name. Doing it at startup put "Ocarina would
  like to access your Photo Library" in front of someone who had done nothing
  but open a terminal. The first keystroke cannot happen at launch, and it means
  the session is genuinely in use.

## Themes

<img src="docs/images/themes.png" alt="The theme picker, fourteen themes">

Fourteen bundled themes, applied as you pick. Each is a JSON file in
`Sources/OcarinaUI/Resources/Themes/` carrying the chrome colours, the terminal
bed, a sixteen-colour ANSI palette and an optional background motif. Drop your
own in `~/.ocarina/themes/` and they appear beside the bundled ones.

The picker is not a sheet. A sheet on macOS is modal and will not dismiss on a
click outside it, and picking a theme is a thing you do by trying three and then
getting on with your work.

Choosing a theme also sets `NSApp.appearance`. System controls — the keep-awake
switch, the menus, the window's own furniture — draw themselves and take their
cue from `NSAppearance`, not from us; without this a light theme kept a dark
switch and dark scrollbars, which reads as a half-finished theme rather than a
choice.

Text is Geist and Geist Mono, bundled under the OFL and registered before the
first frame draws, so nothing flashes through a fallback face on its way to the
right one.

## Quick actions, and not running things for you

⌘K opens a drawer of recipes — install an agent, and so on — from
`Sources/OcarinaUI/Resources/Recipes/`, extended from `~/.ocarina/recipes/`.

It does not run anything. Choosing a recipe **types** its command at the prompt
and leaves the cursor after it, so the last act is always yours. That is
deliberate on two counts: nothing executes that you did not trigger, and you see
the command each time, which is how you eventually stop needing the drawer.

Paste works the same way. ⌘V goes through `PasteInspector` rather than straight
to the emulator: anything unremarkable is pasted with no ceremony, because a
terminal that interrupts every paste is one people learn to click through. Only
multi-command or dangerous text stops for review.

When a command fails, `ErrorHelp` offers to hand the exit code and the visible
screen to whichever agent is installed. For the person this app is for, an
unreadable error is not an inconvenience — it is where the session ends.

## The empty states

<img src="docs/images/empty.png" alt="The departure board with no tabs open, and the empty task panel">

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
their columns line up.

## Package layout

`OcarinaTerminalContext` is the naming subsystem. It holds no PTY state and does
no rendering — it takes a `TerminalSessionSnapshot`, asks each provider what the
terminal is doing, and folds the strongest answer into a `TabContext`.

```
Sources/OcarinaTerminalContext/
  ContextSource.swift            priority chain: shell < project < command < llm < manual
  ContextObservation.swift       one provider's reading, with a confidence
  TabContext.swift               per-tab naming state; displayTitle / subtitle
  TabActivity.swift              idle / running / succeeded / failed, for the dot
  TabNamingEngine.swift          the stability rules (dwell, margin, no demotion)
  TabContextCoordinator.swift    actor that runs the provider chain per tab
  TitleFormatter.swift           local text -> 2-4 word title. No model, no network.
  Providers/
    LLMSessionContextProvider    shared agent provider: Claude / Codex / Gemini / OpenCode
    ClaudeTranscriptSource       ~/.claude/projects/<slug>/*.jsonl
    CodexTranscriptSource        ~/.codex/sessions/**/rollout-*.jsonl
    AgentTaskSource              the same transcripts, read as a to-do list
    GenericProcessContextProvider foreground argv -> title
  Session/
    ProcessInspector             tcgetpgrp + sysctl: what owns the pty right now
    OSCParser.swift              streaming ESC ] 0;title BEL reader
    PTYProcess.swift             forkpty, resize, and the environment scrub
    ShellIntegration.swift       the env a spawned shell is given
    TerminalSessionMonitor       one pty -> TerminalSessionSnapshot
    TabNamingService             poll loop; publishes tabs whose title changed
```

Wiring a tab:

```swift
let service = TabNamingService()
await service.attach(TerminalSessionMonitor(ptyDescriptor: primaryFD, shellName: "zsh"))
await service.start()

for await tab in await service.updates() {
    sidebar.rename(tab.tabID, to: tab.displayTitle, subtitle: tab.subtitle)
}
```

The renderer can forward the bytes it already reads to `monitor.ingest(_:)` so
programs that set their own title are picked up; nothing else is read from the
terminal.

```
Sources/OcarinaUI/       SwiftUI layer
  OcarinaWindowView      the window: sidebar, terminal, task panel
  OcarinaModel           open tabs, selection, renames, title updates
  TerminalSession        one tab: pty + SwiftTerm view + naming monitor
  TabSidebarView         tabs as tasks, with the theme and keep-awake footer
  TaskPanelView          what you have asked the agent in this tab
  TaskSummariser         better names for those tasks, via the `claude` binary
  ThemeStore / Theme     bundled + user themes, and the colour model
  ThemePickerView        pick by looking, not by remembering names
  CommandPaletteView     jump by what a terminal is doing (⇧⌘P)
  QuickActionsView       recipe drawer (⌘K); types, never runs
  PasteInspector         reads a paste before the terminal does
  ErrorHelp              hand a failure to an installed agent
  EmptyStateView         no tabs open: the departure board
  DotMatrix              5x7 dot-matrix panel, the board is built from it
  OcarinaIcon            the bundled app mark, prepared for the dock
  TabIcon / StatusDot    a symbol and a state for each tab
  SleepGuard             holds the Mac awake while Ocarina is open
  BundledFonts           registers Geist before the first frame
  MainMenu               the menu bar; where ⌘T / ⌘W / ⌘K / ⇧⌘P actually live
  ToolTip                AppKit tool tips, because .help draws none here
Sources/Ocarina/         executable entry point
```

SwiftTerm is used only as the VT parser and screen grid. Ocarina spawns the pty
itself, via `forkpty`, because `login_tty` is what makes the pty the child's
controlling terminal — and without that `tcgetpgrp` reports nothing and the
naming layer is blind.

## Keyboard shortcuts

| | |
|---|---|
| ⌘T | New tab |
| ⌘W | Close tab |
| ⌘K | Quick actions |
| ⇧⌘P | Command palette |
| ⌘V | Paste, through the inspector |

They come from the menu bar in `MainMenu`, not from SwiftUI
`.keyboardShortcut`. AppKit offers a key equivalent to the main menu before the
event reaches the window or the responder chain, so a menu item always gets it;
a hidden SwiftUI button only sees what makes it as far as the view hierarchy,
which a terminal view holding first responder can swallow. Ocarina had no main
menu at all for a while, which is why ⌘W did nothing — and why ⌘Q didn't either.

The Edit menu's cut and copy have no target, so they travel the responder chain
to SwiftTerm, which implements them.

## The child environment

A terminal inherits the environment of whatever launched it, and passes it to
every shell it spawns. Launched from inside another tool's session that means
handing each shell the identity of that session — nested tools then believe they
are running as a child of their own parent, which is why Claude Code reported
that transcript saving was off. One of the inherited variables is a messaging
token, which has no business reaching an arbitrary shell.

`PTYProcess` drops those markers before the fork. Only session identity goes:
credentials and configuration a user exports for their own use are theirs and
are left alone.

## Keeping the Mac awake

Ocarina holds a `PreventUserIdleDisplaySleep` assertion — the same one
`caffeinate -d` takes — for as long as it is open. It is **on by default**: a
terminal is usually waiting on something long, and a display that sleeps through
the build is never what was wanted. The point is to stop needing a `caffeinate`
parked in a spare tab.

The switch in the sidebar says whether the assertion is actually held, and
toggles it. `isHolding` is tracked separately from `isEnabled` because the
system can refuse an assertion, and the switch must not claim the Mac is being
kept awake when it is not.

The assertion is named, so it is never a mystery which app is doing this:

```
$ pmset -g assertions
   pid 62530(Ocarina): [0x0001ec3a00058822] PreventUserIdleDisplaySleep named: "Ocarina is open"
```

The kernel drops a process's assertions when it exits, so quitting Ocarina
always gives it back, including on a crash.

## Icons and glass

The app icon is `Icons/AppIcon.png`. **Run `Scripts/make-app.sh` to get it.**

A bare SwiftPM executable has no bundle, so macOS has nowhere to read an icon
from and falls back to the generic Unix-executable picture. Setting
`applicationIconImage` is the only lever without a bundle and it does not reach
Finder, the app switcher or Get Info — which is why `swift run Ocarina` still
looks generic. The script assembles a real `Ocarina.app`: an `Info.plist`, an
`AppIcon.icns` generated from the PNG, the SwiftPM resource bundles, and an
ad-hoc signature.

`OcarinaIcon` trims the art to its drawn content, clips the corners to
transparency and lays it on a clear canvas at the ~80% the macOS icon grid
expects. That preparation exists because an earlier icon was an opaque black
plate with the tile drawn inside it: used as-is it made the dock icon read as a
small tile in a dark square. The invariant worth keeping is that preparation
adds margin around the art and never eats into it. A 512px plate that came back
as a 424px icon is the regression that invariant was written against; the test
pins the invariant — prepared is wider than the art it was given — not the
number.

Tabs do **not** use the app icon. Every tab carrying the same picture said
nothing; `TabIcon` gives each one a symbol for its foreground process, so Claude
Code reads differently from a shell at a prompt across a sidebar of twenty.

Glass needs something behind it to blur. An `NSVisualEffectView` sits behind the
hosting view and the window is non-opaque, so the materials in the chrome have
the desktop to work with; without it they resolve to flat grey. The terminal
view's own background is cleared and a themed bed sits behind it — the glass
reads through, and the text stays legible.

## Tool tips

Three mechanisms were tried. SwiftUI's `.help` produces nothing in a plain
`NSHostingController` — walk the view tree and there is no tool tip on it at
all. AppKit's `NSView.toolTip` *is* installed, on a view that hit-tests at the
right frame, and still never appears: the tool tip manager needs mouse-moved
events to reach the view under the cursor, and inside a hosting view they do not
arrive. A SwiftUI bubble drawn by the control itself is then clipped away by the
scroll view the tabs sit in.

So a control only reports hover, through a tracking area on the small `NSView`
that already takes its click, and the sidebar draws the bubble in its own
coordinate space — outside the scroller, and above the terminal by `zIndex`.

Tab titles are capped at 24 characters for display, ellipsis included, so one
long name cannot push the sidebar around. The tab keeps its full name for
renaming, for the hover subtitle and for the command palette.
