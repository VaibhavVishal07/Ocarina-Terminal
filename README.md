<div align="center">

<img src="docs/images/icon.png" width="104" alt="Ocarina">

# Ocarina Terminal

**A macOS terminal for people who were never taught one.**

</div>

<img src="docs/images/window.png" alt="The Ocarina window: the tab list with two shelves under it on the left, the terminal, and the task list and token meter on the right">

A terminal assumes you already know. It opens a blank rectangle, prints a `%`,
and waits. If you know what to type, it is the fastest tool on the machine. If
you do not, it is a locked door with no sign on it — and every instruction you
find for getting through it was written by someone who forgot they ever had to
ask.

Ocarina is the same terminal, built the other way round. It says what it is
doing, keeps the list of what you asked for, offers the command instead of
expecting it, explains the error instead of printing it, takes a file you drag
onto it, tells you what the last five hours have cost, and never runs anything
you did not trigger yourself.

That turns out to matter twice over. The person who has never opened a terminal
needs it because nothing else tells them anything. The person running five
agents at once needs it because five terminals called `zsh` is not a list, it is
a guessing game.

Nothing leaves the machine. Every title, task and explanation is derived
locally, from files the tools already write.

New to this entirely? [Start here](docs/first-terminal.md).

---

## Download

**[Ocarina for macOS](https://github.com/VaibhavVishal07/Ocarina-Terminal/releases/latest)**
— one universal build for Apple Silicon and Intel. macOS 14 or later.

Unzip it and drag `Ocarina.app` into Applications.

**The first launch needs one extra step.** The app is signed ad-hoc rather than
notarised — notarising requires a paid Apple Developer account — so macOS will
refuse to open it and say it cannot check it for malicious software. That is
Gatekeeper telling you the truth: nobody has vouched for this binary but the
person who built it. To open it anyway:

1. Right-click (or Control-click) `Ocarina.app` and choose **Open**.
2. Click **Open** again in the dialog.
3. If macOS still refuses, go to **System Settings → Privacy & Security**, scroll
   to the message about Ocarina, and click **Open Anyway**.

Only the first launch asks. If you would rather do it in one line — in whatever
terminal you have now, since this is the one you are trying to install:

```
xattr -dr com.apple.quarantine /Applications/Ocarina.app
```

Or build it yourself, which needs no permission from anyone:
[Running it](#running-it).

---

## The tabs name themselves

The tab is not called `zsh`. It is called what the terminal is *doing*: the
prompt you gave an agent, the command that is running, the project you are in.

Ocarina reads that from three places, in order of how much they know — the
transcript an agent is already writing, the foreground process on the pty, and
the directory the shell is sitting in. A stability layer decides when a new
answer is good enough to replace the one on screen, so a title does not flicker
every time a command finishes.

An agent conversation is named for the ask that opened it, not for the last
thing typed into it. Reading the newest prompt meant a tab renamed itself on
essentially every command, which is the opposite of what a name is for: you
find a tab by remembering where it is and what it was called. What the agent is
on *right now* is the subtitle, the tooltip and the task panel, all of which are
free to move.

The words themselves come from the same place the task list's do. A word filter
cuts the prompt down the moment it is read, and Claude rewrites it a beat later
— "Toggle option near right-hand" was what the filter made of a tab, and "Move
toggle to right side" is what it is called now. The panel had this and the tab
strip did not, which is why the two columns beside each other read as two
different qualities of the same sentence. One cache and one queue serve both, so
a prompt that appears in the list and on the tab is asked about once.

A dot on each row says idle, running, succeeded or failed, so a column of twenty
can be read down the edge without stopping at any of the names.

For an agent the dot comes from the transcript, not from the byte stream. A
coding agent holds the foreground from launch to quit and repaints its own
input box, status line and cursor while it waits — so "something drew recently",
which is the right test for a shell, is true for the entire life of the tab. A
tab whose job had finished minutes ago sat there blinking *working*, which is
the one distinction the dot exists to draw. `stop_reason: "end_turn"` says it
exactly: the agent has stopped and is waiting for you.

[How the naming works](docs/context-aware-tab-naming.md) — the provider chain,
the priorities and the stability rules.

## It remembers what you asked the agent

You give an agent five things across twenty minutes and cannot remember which of
them it actually got to. The panel down the right is that list, read from the
transcript the agent writes anyway — so it costs the session nothing and it
survives scrollback.

Every prompt you typed, and only the prompts you typed. That is harder than it
sounds. A prompt sent while the agent is already working never becomes a prompt
record at all — the queue hands it to the turn already running and files it as
an attachment on that turn — so a panel reading prompt records alone drops every
request after the first one in a turn, and a session of eight asks lists one.
A prompt that waited for the turn in front of it to end is filed a third way
again. All three are read. What is not read is anything the app said on your
behalf: injected prompts, follow-ups you accepted from a suggestion, background
work reporting back through the same queue, and a subagent talking to itself.

The list belongs to the tab, not to the folder. Two agents open on one project
write two transcripts side by side, and each tab is bound to the one that
appeared after its own agent started. A terminal with no agent in front of it is
bound to nothing at all — that case used to fall through to "whichever
transcript has been written to lately", which is exactly the neighbour that is
working right now, so opening a shell to run one `git status` came up carrying
somebody else's list with a task still in progress on it.

`TaskSummariser` asks Claude to rewrite the local titles, because it is better
at it: "Toggle option near right-hand" becomes "Move toggle to right side".
Three rules follow from where that work happens.

- The local condenser runs first, so a title is on screen immediately and a
  machine with no agent installed loses nothing it had.
- Every prompt is asked about once, ever, cached on disk under a hash of the
  prompt rather than of where it was found — so the tab strip and the task list
  asking about the same sentence cost one call between them. This spends your
  Claude allowance.
- **It waits for a keystroke.** Running the `claude` binary means a subprocess,
  and a subprocess inherits the app's TCC identity — every protected thing it
  reads is asked about in Ocarina's name. Doing it at startup put "Ocarina would
  like to access your Photo Library" in front of someone who had done nothing
  but open a terminal. The first keystroke cannot happen at launch, and it means
  the session is genuinely in use.

The panel is on by default and turns off from a switch in the left column, with
⌘J written beside it. It is a column, not a drawer: showing or hiding it resizes
the terminal once. It was a sliding drawer for a while, and that animated the
terminal's *width* — a `TIOCSWINSZ` and a SIGWINCH per frame, with the shell
repainting its prompt through the whole slide.

Starting something new? The header carries an eraser when there is anything to
erase. It records a line under the list for that project and hides what came
before it. The agent's transcript is not touched — it belongs to the agent, and
deleting somebody's prompts out of Claude's history to tidy a panel would be the
worst kind of helpful. Ask for something new and it appears, being newer than
the line.

Closing the panel closes the column, not one card in it. The token reading used
to stay behind when the task list went — a single card floating in a lane of its
own, still taking the width off the terminal, with no way to shut it that was
not the ⌘J that had visibly just failed to. ⌘J means "give me the room back",
and half the room back is the wrong answer to that. The figure is not lost: it
is in the menu bar's menu, one click from anywhere.

Panels stacked one above another share a gradient rather than each running
their own. A column used to go bright, dim, bright, dim — the light restarted
at every card, and the pair read as two objects that happened to be near each
other.

Mirroring the lower card was the first answer and it is wrong in the other
direction: the junction matches, but the column then gets *brighter* on the way
down, which is not what a light source does. So it is one gradient cut in two.
The top card runs from the panel colour to its dark end; the card under it
carries on from that end towards the window's own ground, and the bottom of the
stack is the darkest thing in it. The sheen goes on the top card and only the
top card — a panel halfway down a falling gradient has no reason to catch light
of its own, and putting one there is what made the lower card glow in the
middle of the fall.

## It says whether the thing you asked for is still going, where you can see it

In the menu bar, beside the Wi-Fi: **one cell of a departure board, and the state
beside it in words** — `Ready`, `Still going`, `Needs you`, `Back to you`,
`Stopped (127)`. The card is blank while nothing has been asked, turns while an
agent works, lands on a ring when it comes back to you, wears an exclamation when
a tab is asking for you, and shows a cross when something exited badly. Sixteen
and a half points square, in the app's own lamps.

It was the whole line set in the 5x7 grid the wordmark and the landing screen are
built from — `STILL GOING`, `BACK TO YOU`, `STOPPED 127` — and that was right
about the alphabet and wrong about everything it cost. Eleven characters at six
columns each is **136 points** of menu bar: wider than the clock, the Wi-Fi and
the battery together, for a reading you take in a fifth of a second. And a
letterform built from 1.4pt lamps is under the size the grid can set — the S and
the G came out as smudges. It was a word you could not read taking the room of a
sentence.

So the grid came off, and for a release the card went up on its own. That was one
correction too many. The width was a fact about the *grid*, not about the words:
the same line set in the system font is about a third of the space, and it is the
font every other item up there is already set in. A picture alone asks somebody to
have learned four plates before it says anything; a picture with its name beside
it teaches them, and then goes on working once they have. The item is
variable-width again as a result, so things to its left shift a few points when
the state changes — which is what every variable-width item in a menu bar already
does.

**Nothing up there says Completed.** The words gained a state and did not gain a
claim: `Back to you` is what a turn ending can support, and *completed*,
*finished* and *done* are not. See the note on `end_turn` below, and the test that
holds the line.

A pictogram survives that size where a letterform does not, and every other item
in a menu bar is one glyph wide for the same reason. It was a little face on a
plate of lamps for a release, which was legible and was a character from
nowhere: it had no more to do with this app than with any other. A split-flap
cell has both — it is the object the rest of the app is already made of, and it
says the four states by doing what a board does.

**The seam is the whole idea.** A split-flap card is cut across its middle, and
that line has to be visible in every state or this is a box that fills up. So it
is drawn as a *lit line when the cell is empty* and a *dark gap when the cell is
full* — the same hinge, taking whichever value contrasts with what is round it.
One row of the seven is the seam and nothing else is ever drawn there.

**Seven by seven, and square.** A real split-flap card is taller than it is
wide, and this was five by seven for a while on exactly that reasoning. In a
menu bar it is wrong: every other item up there sits in a square, and a tall
narrow one reads as something squeezed rather than as something drawn to fit.
The proportion of the real object is worth less than sitting properly in the row
it lives in.

Widening rather than shortening, because the two states that are marks rather
than fills need the room. It was five by five once, and there a cross has its
crossing point *on* the seam — the one row nothing may be drawn on — so it came
out as eight loose dots, and a ring sat one lamp inside the frame the whole way
round and read as a second border. Seven by seven gives each half three rows and
the mark a proper diagonal.

**The lamps are thick and the gaps between them thin** — 1.7pt against 0.35,
filling 83% of the pitch where the face filled 70%, and squarer at the corners.
That is the difference between a row of dots and a bar. A face is made of
separate lamps and wants the dark between them; a card is a surface, and every
state here is mostly filled rows.

The turn is **five frames at 120ms**, not a chase: the card stands, folds through
the seam, passes edge-on, comes down the other side and lands. Frames rather
than a chase because a chase is a lamp brightening and dimming — right for a
mark that is *lit*, wrong for a card, which does not glow, it moves. A departure
board clacks. Five frames and not the six it takes to come back round to the
seam: a sixth would show the resting card once a pass, and the resting card is
what *ready* looks like.

**It lands on a ring, not a tick.** A tick was the most readable of the seven
things tried in that slot and the only one that grades the work. An agent
stopping means it stopped talking, not that it managed what you asked — which is
why the words up here say *back to you* and never *done*, and a tick makes
exactly the claim that wording was written to avoid. A ring claims nothing, and
it is the app's own O, so the one state you most want to catch is also the one
place the menu bar says whose it is.

The image is built from a drawing handler rather than `lockFocus`, so it is
resolution-independent and AppKit redraws it at whatever scale it is being shown
at. `lockFocus` rasterises once at the deepest attached screen's scale: a 0.35pt
gap then landed wherever it landed on the pixel grid, and a filled row that
should read as one bar came out as a line of separated dots.

It is a template image, so the bar tints it and it inverts with light and dark
the way every system item does — which is also why the chase is expressed as
*alpha* rather than as colour. A template has no colour of its own to vary;
what it has is how much of the bar's ink each dot asks for, and that turns out
to be the right model for a lamp anyway. The dark cells of the plate are painted
too, faintly: they are what make it a panel of lamps rather than a face floating
in the menu bar, and at this size they are the only thing that says the lit ones
are lit.

**The tooltip still carries more than the bar can.** The line beside the card is
the state and only the state; a card has nothing to say about an exit code or
about whose app it is, so the tooltip and the accessibility label carry the house
line with Ocarina's name in front of it and the task named after it. The theme's
own wording is one click down in the menu. Everything is sentence case: it was
uppercase for as long as it was painted on a grid with no descenders, which is a
constraint the board imposed and not one the words ever had.

The words answer the question somebody has up there rather than naming a state.
They were Working, Idle and Done for a release, and each was a label for a value
in an enum. *Working* also reads as a claim about the Mac when it is glanced at
with no window beside it, which is the failure Steel's "Under load" made
obvious. And nothing up there says *done*: an agent stopping means it stopped
talking, not that it managed what you asked, so that state hands the turn back
rather than grading the work.

**Still going** means an ask that has not come back yet, and only that.
`.running` off the terminal means "this program drew something in the last two
and a half seconds", which for a compiler is exactly right and for an agent is
not the same claim at all — Claude sitting at its prompt with a cursor blinking
in it repaints forever, so a terminal left open on an agent that had been
waiting on you since lunch reported itself as working. For a tab with a
conversation in it the answer now comes from the conversation: an unanswered
ask is work in progress, and anything else is not, however busy the screen
looks. A plain terminal is still taken at its word — `make` in the foreground is
working and has no transcript to check it against — and an agent that exited
non-zero still says so whatever the transcript ends on.

It was a card under the task list for one release, and that was the wrong
surface for it. The state of the run is the one reading you want *while you are
looking at something else* — a browser, a design tool, somebody else's screen —
and a card inside Ocarina's own window can only be read when Ocarina's window is
the thing in front of you, by which point the tab's dot, the rail over the
terminal and the row in the task list have all already told you. Three copies of
a fact in one window and none of it anywhere else.

Before the card it was a drop out of the notch, which had the right idea about
where you were looking and paid for it by taking over the most valuable strip of
screen on the Mac for three and a half seconds. A status item says the same
thing for as long as it is true and costs nobody a frame of what they were
doing.

The menu it drops is built on the way open rather than held: the reading behind
it is refreshed every fifteen seconds, and assigning a freshly built `NSMenu` on
each refresh would swap the menu out from under anybody who had it open. It
carries the state in full, **the last five asks with what became of each**, and
the token window underneath.

The five are the task list, in the same order the panel keeps it and marked with
the same two marks — a quiet tick for an ask the agent has stopped on, an empty
box for one still open, so the eye lands on the row still outstanding rather than
on the ones already dealt with. It is the panel's own question — you gave the
agent five things across twenty minutes and cannot remember which of them it got
to — asked from where you actually have it, which is with Ocarina's window behind
something else. The panel can only answer once you have brought the window
forward, and that is the moment you least need to ask.

Five because the cost of this menu is the screen you were reading: it drops under
the clock over whatever is in front of you, and a list running to the twenty asks
a long session accumulates would cover the window it exists to save you opening.
A longer list is not dropped, it is counted — *and 2 more in the panel* under the
fifth row, because a list that stops at five with no sign it stopped is a list
claiming the sixth ask was never made.

The single task row above them is gone. It named the newest open ask, which is
the first row of this list under another name — and one bare line above its own
unmarked twin reads as two different tasks. The tooltip still names it, because a
tooltip is one line and has room for one. The marks are pictures and a picture is
nothing to a screen reader, so each row also spells its state out: *finished*,
never *done*, the same word the app uses everywhere else for an agent that
stopped talking.

The list is the panel's, cleared line and better titles included — drawing a line
under the panel and then finding everything you tidied still listed in the menu
bar would make the clear look like it had failed. It also means the menu bar is
told on the task poll rather than only on the activity stream and the
fifteen-second token refresh: without that, an ask finishing quietly left the
menu saying it was still going.

The wording is the theme's — see [themes](#it-looks-like-something-you-chose).
The exit code is not: it is appended after whatever the theme wrote, so a theme
is free to be as arch as it likes about a build stopping and cannot produce a
failure that reads as anything else.

The item goes away when there is no tab open. A menu bar item saying the
all-clear about an app with nothing in it is furniture in the most expensive
strip of screen on the Mac.

Inside the window, the wordmark says it. While an agent is working in **any**
tab, the mark's lamps light one at a time along the word, with a short trail
behind the head — the same chase the marks on the website run, at the same
speed. Any tab and not the selected one, because the mark sits over the list of
every tab: bound to the tab in front of you it would only repeat what that tab's
own dot already says. It costs the column no room and adds no second spinner to
a window that has one in the menu bar, and it is the only `DotMatrixText` in the
app that moves — the rest are labels, and a label that shimmers is a label you
cannot stop reading.

## It says when a tab is asking for you

A fifth state, and the only one in the app that is not read off the pty's own
behaviour: **Needs you**. The tab's dot goes to the theme's accent, the rail
over the terminal comes up brighter than it does for a run, and the menu bar
wears an exclamation whose gap falls exactly on the seam.

**The signal is the bell.** BEL has meant "a program is asking for you" for
fifty years, and the coding agents ring it when they want a decision. Nothing
else available can say it. A transcript cannot: a permission prompt that has not
been answered *has not happened yet*, so there is nothing written down — across
the transcripts this was checked against, `stop_reason` is only ever `tool_use`
or `end_turn`, and neither distinguishes "running your build" from "waiting for
you to say yes". Watching the screen cannot either, because an agent thinking
and an agent waiting both repaint.

So the app stops guessing and uses the thing the program says on purpose. The
beep still sounds; what is new is that it is also *written down*. A beep is gone
the moment it happens, and ringing while the window sits behind a browser used
to leave nothing on screen that remembered it.

**A ring in the tab you are already looking at is not news** — you are there,
you can see the prompt — so it is only recorded for a tab you are not in. And
**looking at the tab is the answer to it**: there is no button and no dismiss,
because either would be a second thing to do after the thing you already did.

It outranks running and loses to a failure. An agent that has stopped to get a
decision out of you is not making progress however busy the screen looks; a
command that has already exited non-zero is not waiting on anybody, and the
number is worth more than the ring.

A plain shell can ring too. The conversation rule governs what a *transcript* is
allowed to claim about a tab — `make` finishing with a bell in it is asking for
you exactly as much as an agent is.

### What it is still not called

The roadmap this came from asks for **Finished** as a state of its own, and the
app does not have one. The completion signal is `stop_reason: "end_turn"`, which
means the agent stopped talking — not that it managed what you asked. A task it
abandoned looks exactly like one it nailed. So the state stays **Back to you**,
which is a thing this data can support, and *Needs you* is the part of that
split which could be built honestly, because a ring is a program saying so
rather than the app inferring it.

`TabItem.needsAttention` is held beside `activity` rather than folded into it:
activity is rewritten from the naming service's stream every time the pty moves,
and a ring set there would be gone on the next update. `OcarinaModel.reported`
puts the two together on the way out, which is where the conversation rule
already lives.

The dot takes the theme's **accent** rather than a fifth colour in
`Theme.Status`, which every theme file would have had to grow. It is the colour
the app already uses to mean "this is the thing", and a tab asking for you is
the thing — the same argument `TabIcon` settled: name the slot, and let the
theme say what colour that is. The words work the same way: `needsYou` is
optional on a theme's `voice`, so all fourteen bundled themes and anybody's own
file still load, saying the house line until they say otherwise.

## It tells you, and only while you are elsewhere

Three moments reach macOS notifications: a tab **asking for you**, a tab that
**came back**, and a command that **stopped badly**. Not every command, not
output, not a shell reaching a prompt — a terminal reaches a prompt a hundred
times an hour and none of them are news.

**Nothing is posted while Ocarina is the app in front.** A notification about a
window you are looking at is not information, it is a second copy of the screen:
the tab's dot, the rail over the terminal and the card in the menu bar have all
already said it. This is only for when none of those are in view, which is the
only time the feature is worth anything.

They fire on the *edge*, not for as long as a state is true. The handler behind
this runs every time the pty moves, and a notification that repeated while
something stayed finished would be exactly the noise this exists to remove.

The state leads and the ask names the session — **Needs you** over *Fix the
checkout page* — because the state is the actionable half and the tab's name is
already the thing you were waiting on. The words are the house's, not the
theme's, for the reason the menu bar settled once already: a notification is
read on a lock screen beside mail and calendar alerts, further outside Ocarina
than even the menu bar is, and a theme being arch there costs somebody the one
reading they came for. Nothing says *done*, on a lock screen least of all.

A second notification about the same session replaces the first rather than
stacking under it. Four asks coming back while you are at lunch should be four
lines, not forty.

**No sound.** What prompts most of these already rang the terminal bell, and a
notification that beeps a second time for the same event is the thing it is
meant to save you from.

Permission is asked on the first post, not at launch — the first moment the
answer means anything. A permission sheet in front of a window you have only
just opened is a question about something you have not seen yet. A "no" is taken
for an answer: asking twice is asking somebody to say no twice.

The switch is third on the shelf beside Tasks and Keep Awake, because it is the
same kind of thing — on or off for this window, and something you check rather
than press. It is on by default: a feature nobody finds is worth nothing, and
the system's own prompt is the real opt-in.

`UNUserNotificationCenter.current()` does not fail politely without a bundle
identifier, it aborts the process — so the check is `Bundle.main.bundleIdentifier
!= nil` before the call rather than a `try` around it. A SwiftPM binary run
straight out of `.build`, and the test binary, are both in exactly that state.

## It still says what the window has cost

Under the task list, a small card: what this agent has spent, and how long the
window it is spending from has left to run. Two rows and a meter, 49pt against
the 101 it started as — it began as a dashboard tile, an icon and a caption and
a 21pt number and a rule and a sentence, which is a great deal of card for one
figure you glance at on your way past.

Neither this nor the task list appears until there is an agent in front of you.
Both are about a conversation, so a shell at a prompt has nothing to put in
either; the column used to open on launch regardless and say "No tasks yet" to
somebody who had not started an agent and had no way to know that was the point.

They also leave together. ⌘J closes the column rather than one card in it — see
[the task panel](#it-remembers-what-you-asked-the-agent) — and the figure is a
click down in the menu bar's menu for as long as the column is shut.

The meter is drawn as lamps on a departure board rather than as a bar, and the
reason is not decoration. A solid bar reads as a proportion of something
continuous, which invites exactly the reading this card must not invite — that
the fill is an allowance running down. Counted lamps read as counted units, and
these are: the five-hour window in fifteen-minute pieces, of which some have
gone. The app already has that alphabet in the wordmark and the landing screen.

It says **used**, not **left**, and that is not a hedge. Nothing on the machine
records the size of the allowance or when the account's quota renews: not
`~/.claude.json`, whose two rate-limit tier fields are null; not the session
files; not the transcripts, which carry no rate-limit record of any kind. That
number exists only in the responses Anthropic sends back, and the only way to
ask for it would be to take the OAuth token out of the user's home directory
and spend it on a request they did not make. A terminal does not get to do
that, so the card shows what can be shown honestly. A meter with a denominator
invented for it would be worse than no meter.

The window itself is reconstructed from the timestamps, which the transcripts
do record: a block opens on the first request made after the last one lapsed
and runs five hours — from the *top of the hour* that request landed in, which
is where the account puts the boundary. Counted from the timestamp itself the
card was up to an hour late: it went on filling a block the account had already
renewed, so a limit that had just reset was reported as a window nearly out of
time. And once a block has been established it is kept until the clock ends it,
rather than re-derived on every poll — the reading only looks back ten hours, so
a chain rebuilt from whatever is still inside that window moves under a user who
has done nothing.

Tokens are counted once each — what was sent, what was written to cache, what
came back. Cache *reads* are left out on purpose: they are the same tokens being
read back, already counted on the turn that wrote them, and adding them charges
a long conversation for its whole context on every single turn.

## It installs skills for whichever agent is in front of you

A skill is a folder of instructions an agent loads when a task calls for it —
a `SKILL.md` with a name and a description, and whatever scripts, references and
assets sit beside it. That is the whole format, and it is the same format for
every agent in the dock: Claude Code, Codex, Gemini CLI and OpenCode all read
it. Finding one still meant knowing which of two hundred repositories to look
in, reading a README, and copying a folder into the right place by hand.

So: a **Skills** row in the sidebar, always. It was there only while an agent
was running in the tab you were looking at, on the reasoning that the same skill
belongs in a different directory for Claude Code than for Codex and a plain
shell has no answer to "install this where". That reasoning is right about the
install and wrong about the browser, and it produced a row that was missing on
the day somebody most needed it: you find out what a skill *is* by opening this,
and you could not open it until you had already started the agent the skills are
for. The row now carries a count of what you have on its trailing edge.

**A press with no agent running is kept, not refused.** It goes in a queue, a
strip across the window says which skill is waiting and offers to start Claude,
and the moment an agent appears in front of any tab the queue drains into its
directory. The queue lasts as long as the app does and no longer — one restored
three days later would install something you have forgotten asking for.

| Agent | Where it reads skills |
| --- | --- |
| Claude Code | `~/.claude/skills` |
| Codex | `~/.agents/skills` |
| Gemini CLI | `~/.agents/skills` |
| OpenCode | `~/.agents/skills` |

`~/.agents/skills` is the interoperable one. Codex reads only that, and Gemini
CLI and OpenCode read it in preference to their own, so three of the four share
what they install. Claude Code reads its own and does not read `.agents`, so
installing the same skill for both writes it twice rather than linking — a
symlink into another tool's directory is a thing somebody has to discover the
hard way when they uninstall one of them.

The agent is matched on the foreground process, and on the whole first word of
it rather than on a prefix. A prefix test matches `claudette`, and writing into
`~/.claude/skills` because a command happens to start with the same six letters
is not a mistake worth being relaxed about.

That process is read off the pty, not off the tab's name for it. They are
usually the same string; the difference is that one is ground truth and the
other has been through a naming engine that publishes on its own schedule and
compares on what is *drawn*. For something deciding which directory in your home
gets written to, the pty is the honest source — and it is also the one that
cannot be a tab old when an agent starts inside a shell that was already open.

The poll that reads it had learnt to skip: first a hidden task panel, then
anything but a tab already believed to be an agent, which is circular when the
poll is what tells you a tab *is* one. It now runs for whatever is selected.
That costs a `snapshot()` and a `stat` every two seconds when nothing is
listening; the expensive half — parsing a transcript that can be tens of
megabytes — is still behind the signature check, which is where the cost always
was. A new tab refreshes at once rather than waiting for the next tick, and a
foreground the poll has read is the answer whatever it says: `zsh` means there
is no agent here, not "ask somebody else".

### It opens on eight, not on two hundred and sixteen

Two hundred and sixteen rows is not a shelf. It is a search box with a list
attached, and it only works if you already know what you are looking for —
which the person this screen exists for does not. So the browser opens on
**Starters**: a line saying what a skill even is, and eight picks. **All** is one
press away and holds everything it used to.

Eight, and not twenty. The point of a starting shelf is that it can be read to
the end; a shelf you have to scroll is the wall again, shorter. They are chosen
to be useful before you have decided what you are building — checking code,
debugging, looking things up, handling the file formats everybody has — rather
than to be the eight most installed, which is how you end up recommending
Prisma to somebody who has not got a database.

**Each pick leads with a line written for you, not for the agent.** A skill's
own description is addressed to the reader that will follow it — "Use when
encountering any bug, test failure, or unexpected behavior, before proposing
fixes" is the right text for that reader and no answer at all to "what would I
want this for". So the shelf says *Work out why something is broken*, and puts
`systematic-debugging · obra` underneath, because who wrote the instructions
your agent is going to follow is still most of the decision.

**Installed** is the standing list: what is waiting for an agent, what is on
disk, and a Remove on each. It reads every skills directory rather than the one
in front of you, so closing Claude no longer takes your installed skills off the
screen — they are still there, and the app had simply stopped looking. What a
card says about *itself* stays per-agent: a skill in `~/.agents/skills` is not
one Claude Code will read, and "Installed" beside Claude would be a claim about
the wrong directory.

### The catalogue is bundled, and says who wrote every row

Two hundred and sixteen skills from eleven publishers — Anthropic, OpenAI,
Vercel, Microsoft, Supabase, Prisma, Neon, Firebase and others — with each row's
description read out of that skill's own `SKILL.md`, so every row says what the
skill says about itself.

Bundled rather than fetched. A registry query is one more thing between somebody
and a working agent, it is a third party's uptime, and the only public endpoint
returns names and install counts with no descriptions at all — a browser built
on it would be a list of two hundred words. This opens instantly and offline.
The cost is that it goes out of date, which is why every row carries the
repository it came from.

**Who wrote it sits next to what it is called, on every card.** A skill is
instructions an agent will follow, so the publisher is not a detail — it is most
of what you are deciding when you press Add.

**Design leads.** The design category comes first in the filter pills, design
skills sort above everything else in an unsearched catalogue, and the starting
shelf opens on one. That is a house call rather than a fact about the registry:
this app is opinionated about how things look, the people who choose it are
choosing it for that, and the row a shelf leads with is the row that gets
installed. What you type still outranks it — a shelf that answered "pdf" with a
design skill would be a search box that does not search. Everything after that
is ordered by how often the registry has seen each one installed, which is not a
measure of quality but has to be something when there are two hundred of them.

Filter by category or search by name; searching puts the skill you *named* above
the ones that merely mention it, because somebody typing "pdf" wants the skill
called pdf and not the eleven that mention PDFs in passing.

### Three sections, one skeleton under all of them

Where to begin, everything, and what you have are genuinely three questions, so
they are three tabs. What was wrong was underneath: each opened with a different
kind of thing, so the panel reshuffled itself every time you moved between them.
The first led with a paragraph and ended with a link that went to the second,
which was already a tab above it. The second led with a search field and a row
of pills. The third led with uppercase headings over sections. Three tabs, four
navigation idioms, and no two of them starting at the same height.

**Everything above the tabs is constant now** — the title, the one line saying
what a skill is, and the search field — and everything below them is cards. The
search searches the catalogue whichever tab you were on, and typing moves you to
Browse: filtering eight starters down to two is not a thing anybody wants, and
leaving somebody typing into a list that cannot answer them reads as the search
box being broken.

One tab carries a row of filter pills, because it is the only one holding two
hundred things. That is a filter *inside* a list rather than a second way of
choosing which list, and it is one level deep. The two uppercase headings that
used to divide the third tab are gone: waiting skills sort above installed ones
and each card's own button already says which it is.

Small things that were making it look assembled rather than drawn: the active
tab's underline used to float a few points above a separate divider, so the
panel carried two nearly-parallel lines — it sits *on* the rule now, and is
exactly as wide as the word it belongs to rather than stretching to fill the
row. The footnote has a fill of its own, so it reads as the panel's floor.

And everything vertical is on **one scale** — 6, 14 or 20 points — rather than
whatever each pair of things happened to need, which is what made the panel read
as tight in some places and loose in others. The cards grew from 76 points to
86, the gap between them from 12 to 14, and the panel from 620 to 660 to hold
them.

Below the tabs, one card everywhere: **what this is** on top and one line under
it. It carried four things — a headline, a supporting line, the author and the
button — which is one more than a card this size can lay out without the eye
having to decide what to read next. The author moved onto the supporting line
rather than off the card, because a skill is instructions an agent will follow
and the publisher is most of the decision.

On the starters shelf the plain-language line leads and the folder name joins
the author underneath. Everywhere else the folder name leads, because that is
what you are searching by and what the agent will call it. Same two slots either
way, same fixed height, so a grid of them is a grid rather than a masonry of
whatever each description happened to need.

The problem was never two columns; it was two hundred rows in them. Eight cards
in two columns is a shelf you read to the end.

The category mark went, though. Nine glyphs at fourteen points, one on every
card, in the same place every time — scannable in principle and in practice a
column of small grey shapes beside the only words that carried anything.

**Accent capsules, a lit board colour on every installed mark, a red wash behind
the error line.** On a screen whose job is to be read by somebody who does not
know what the words mean yet, colour that carries no information is noise with a
mood. The category filters are still pills — they are controls and a control
should look pressable — but they are drawn in the window's own greys, the
buttons are a hairline rather than a fill, and what is left doing the work is
the type hierarchy. The theme still comes through in the surface, the text
colours and the window around it, without competing with the content.

**Add is drawn on every card now, quietly.** It used to appear only under the
pointer, on the reasoning that two hundred Install buttons is two hundred things
asking to be pressed. True of a wall, and exactly wrong for somebody who has
never seen this screen: a button that is not there until you happen to hover
over the thing it belongs to is a button you have to already know about.

It has two treatments and not four: an outlined **Add**, which is the one thing
on a card asking to be pressed, and a plain word for everything that has already
happened — waiting, installed, and the Remove that word becomes under the
pointer. A state that is not a call to action should not be drawn like one, and
four differently weighted buttons for one control was most of why the page read
as busy.

The supporting line on the browse page ends where a sentence does. These
descriptions are written for the agent, which reads all of them: they open with
what the skill does and then spend a sentence or three on when to reach for it.
Clipping the raw text to the card's width broke every one of them mid-word,
which makes a page look faulty rather than full. The rest is on the tool tip.

### Installing

One request to GitHub's tree API to learn what the folder holds, then one fetch
per file. A skill is a `SKILL.md` and usually a handful of things beside it, so
that is a few hundred kilobytes at worst — and pulling a tarball of a repository
like `microsoft/azure-skills` to extract one folder is thirty megabytes to save
four requests.

Nothing is written until every file has arrived, and then into a staging folder
that is swapped in. A skill is a folder an agent reads as a unit, and half of
one on disk is worse than none: the `SKILL.md` promises a script that is not
there. A download that dies part way must also not be able to delete a skill
that was working.

**And it says so outside the browser.** Everything the app knew about an install
used to be drawn inside a modal you close — the spinner on the row, the
"Installed" label — so closing it took the only evidence with it, and what was
left was a folder quietly appearing in a directory nobody looks at. A strip
across the top of the window now says what happened: installed, waiting for an
agent, or what went wrong. The success line names when it takes effect —
*Claude Code reads it the next time it starts* — because an agent reads its
skills directory on startup, and a skill installed into a conversation already
running is not in that conversation. Saying "installed" and stopping there is
how somebody comes to believe the feature is broken.

Every path out of the repository is checked before it is joined onto a directory
in your home — no absolute paths, no `~`, no `..`, no empty segments — and
checked again against the destination after the join. There is a ceiling of
twelve megabytes and two hundred files, so a repository that has quietly become
a data set cannot be pulled into your home directory by one click. Installing
replaces rather than merges, because a new version with a file deleted, merged
over an old one, leaves the deleted file behind and the agent reads it.

Removing takes the folder by name and only from the directory it was installed
into.

## It tells you what to type

<img src="docs/images/quick-actions.png" alt="The quick actions drawer: install an agent, and the things agents need">

⇧⌘K opens a drawer of recipes — install an agent, install the things agents
assume you already have. Each one says what it does before you choose it.

It does not run anything. Choosing a recipe **types** its command at the prompt
and leaves the cursor after it, so the last act is always yours. That is
deliberate on two counts: nothing executes that you did not trigger, and you see
the command each time, which is how you eventually stop needing the drawer at
all.

Recipes live in `Sources/OcarinaUI/Resources/Recipes/`, extended from
`~/.ocarina/recipes/`.

## It reads a paste before the shell does

The most dangerous thing a beginner does in a terminal is paste something from
the internet. ⌘V goes through `PasteInspector` rather than straight to the
emulator.

Anything unremarkable is pasted with no ceremony, because a terminal that
interrupts every paste is one people learn to click through. Only multi-command
or risky text stops for review, with a line on each part saying what it will do.

Prose is never multi-command, whatever line breaks are in it. Dictation arrives
as a paste — Wispr Flow inserts what you said the moment you let go of the key
— and a spoken paragraph was being met with "this is 4 separate commands, not
one". A line has to read as something a shell would run before the count
against it means anything. Text that can destroy something is still called out
however it arrives.

## You can drop a file on it

A path is the worst thing to type and the easiest thing to drag. Drop a file
onto the terminal and its path lands at the prompt, quoted if it needs to be,
with a space after it so you can carry on typing.

An image that has no file behind it — dragged off a web page, out of a message,
straight from a screenshot — is written out to a real file first, so there is
still a path to hand an agent. Terminal.app rejects those.

While you are over it the panel dims, a dashed box appears, and it says what
letting go will do: *the file's location is typed at the prompt, nothing is
uploaded and nothing runs.* That is the web gesture, not the native one — a
native app draws a two-point focus ring and says nothing, which is fine if you
already know that terminals take files and what they do with them. Nobody
arriving at this app knows either.

Then the path lands, and that is the whole of it. A chip under the prompt was
built — thumbnail, name, and an × that took the path back off the line — and it
was one thing too many: the path is already there, in the place you are about
to press Return on, so a second widget saying the same thing is furniture. The
overlay stays because it is the part that teaches. The receipt was never
needed.

## It explains what just broke

A command fails and prints something the person who ran it cannot read. For the
user this app is for, that is not an inconvenience — it is where the session
ends, because there is nothing they can do next.

Ocarina already knows the command failed and what is on the screen, and an agent
is usually installed a tab away. A banner offers to hand the exit code and the
visible screen to whichever of `claude`, `gemini` or `codex` is present.
Dismissing it means "I have read this one", not "stop telling me when things
break" — the next failure brings it back.

## It asks you what went wrong

A row under Theme opens a sheet. Say what is broken, and it either opens a
prefilled issue on this repository or copies the same report for whatever
channel you actually use. Your build and macOS version are appended, which are
the two facts every report needs and nobody remembers to include.

It composes; it does not send. There is no server behind Ocarina and no key in
the app, so anything that "just sent" would either be posting to a third party
you never agreed to or shipping a credential inside a binary anyone can
download. It also asks for no address: an earlier version opened a `mailto:`,
which quietly demanded both a configured mail client and the reporter's own
identity attached to a complaint. Neither is fair to ask of somebody whose whole
contribution is telling you a button is broken.

## Four panels, floating

The tab list, the settings, the terminal and the task panel are separate cards
with the window's own ground between them, sitting under a real titlebar with
nothing written in it — Apple Notes and Chrome hold their panes the same way.

The sidebar was one card with the settings drawn as an inset box inside it — a
card in a card, a shape used nowhere else in the window. The right-hand column
had already answered this, with the task list and the token meter as two
panels and the ground between them, so the left-hand side now answers it the
same way. Five panels of one kind beats four and a nested one.

It was one unbroken surface running up under a hidden titlebar, which meant
every edge had to clear a bar that was not drawn: a spacer in the sidebar, an
inset in the terminal, thirty points of padding on the error banner, and three
traffic lights floating on the tab list. The bar earns its place — somewhere to
hold the window that is not the text you are reading — and the gap around the
cards does the rest.

### Two shelves, because a switch is not a door

Under the tab list, **what is true right now**: Tasks and Keep Awake, two
switches. Under that, at the foot of the column, **what opens**: Skills and
Theme, each with a chevron.

They were one card of five rows, and the five were two different kinds of thing
wearing one shape. Three of them opened something; two of them were simply on or
off. Nothing about a row said which — you found out by pressing it — and the
window had already answered exactly this question one level up, when the
settings stopped being a box nested inside the tab card and became a panel of
their own. The same answer applies inside: two cards, with the window's ground
between them, and the shape tells you what kind of row you are looking at before
you have read a word.

The readings sit next to the list because the list is what they are about — one
says whether the panel listing that tab's asks is up, the other whether the Mac
those asks are running on may sleep. The doors sit at the foot, which is where a
row you press to leave the column belongs; both of them open a sheet over the
whole window.

**Share Feedback left for the app's own menu**, and that is what pays for the
split: four rows divide cleanly into two and two, five did not. It was in the
sidebar on the reasoning that the people this app is for are the ones least
likely to go looking for where to complain — which still holds, and the app menu
is not going looking. It is the first menu in the bar, it is there before a tab
is open, and it is where every Mac app has kept this for twenty years. Two cards
of two rows come to 152 points where the one card of five came to 155.

Rows are a fixed height rather than a minimum — as a minimum the rows carrying a
switch came out taller than the rows carrying a link, because a control has an
intrinsic height of its own and the row grew to it, so a card of identical rows
rendered as several different ones.

The marks on them are deliberately plain: a stack, a half-filled circle, three
lines, a bolt. They were a paint palette, two speech bubbles with text in them,
a checklist and a cup on a saucer — detail that reads as noise at ten points,
and detail nobody needs when every row is captioned. The glyph sits eight points
clear of its label, and that gap goes on the icon rather than on the stack's own
spacing, because the same spacing is what sits between a label and its value.

The chevron is quieter than both the label and the value it follows. It is the
part of the row that never changes, and the thing that is always true should not
be the thing that catches the eye — the same rule the frame around the menu bar's
card is drawn to.

### Photographing the app

`screencapture`, and everything else that reads the display, needs Screen
Recording granted to whichever bundle the calling process is attributed to — and
a shell running inside another app does not have it. So the app takes its own
picture instead, which is a thing any app may do about its own windows and needs
no permission at all:

```
OCARINA_SHOT=/tmp/shot.png OCARINA_SHOT_RUN='claude' OCARINA_SHOT_AFTER=12 \
  build/Kazoo.app/Contents/MacOS/Kazoo
```

`OCARINA_SHOT_RUN` opens a tab in the working directory and types the command, so
the picture has a real session in it rather than the landing screen, and the app
quits once the file is written — it was started to be photographed. Nothing
happens at all unless `OCARINA_SHOT` names a file. See `WindowShot`.

The window's own background is painted under the shot first.
`NSVisualEffectView` is the one thing in the hierarchy that cannot draw itself
into a bitmap: the blur is composited by the window server out of the desktop
behind the window, which is exactly what a self-portrait has no access to. Left
alone it comes back transparent and every panel floats on nothing.

That is the way to get a picture of the *real* thing — real SwiftTerm output,
real agent, real theme. The render preview below is for looking at chrome that
is hard to reach by hand.

### Drawing the chrome without running it

The window at the top of this file is not a screen capture either. It is
`OCARINA_RENDER=1 swift test --filter RenderPreview`: the view tree hosted in an `NSHostingView` in an
offscreen window, laid out, then `cacheDisplay` — the app drawing itself into a
bitmap at exactly the size the file is checked in at.

It is hosted rather than run through `ImageRenderer` because the renderer walks
the SwiftUI tree and two things in this window are not in it. A `LazyVStack` only
builds its rows when a real scroll view asks for them, so the tab list and the
task list came back as empty cards; and `NSSwitch` is AppKit, so the two switches
came back as placeholders. The terminal text is the one part that is not the
app's own view — SwiftTerm needs a running pty, so those lines are set in the
theme's own terminal font and ANSI palette.

### One fall, now cut in three

The sidebar is three cards where the right-hand column is two, and both have to
reach the window's ground by the same route or the two sides of the window stop
matching. `PanelPlace` names a *slice of the fall* rather than an ordinal for
this reason: `.bottom` is the lower half of a pair, `.middle` and `.foot` are the
second and third of a stack of three, and the handover between them sits exactly
halfway along the run `.bottom` crosses in one go. A single `.bottom` doing both
jobs would have had to start at two different colours depending on what happened
to be above it.

Only the head of a stack catches light. That rule is a function of its own —
`catchesLight` — so that adding a place to the enum is a decision about the
light rather than an omission; a card halfway down a falling gradient has
nothing above it for the light to come from, and putting a sheen there is what
made the second card glow in the middle of a fall.

The terminal's scroll indicator only appears while you are scrolling. SwiftTerm
puts a bare `NSScroller` in the view rather than one inside an `NSScrollView`,
and an overlay scroller only knows to fade out because a scroll view tells it
to — so it drew a permanent knob down the right-hand edge, over text, in a
window with no other always-on furniture in it.

## An agent tab wears nothing but its name

There is no icon on it. The strip drew each agent's own mark for a release —
Claude's burst, Codex's hexagon, Gemini's spark, all in the theme's accent so
you could scan twenty tabs for which of them were agents. Every part of that was
true and none of it was needed.

An agent tab is **named after what you asked it**, which is the only thing in
that row you did not already know. The dot beside the name says whether it is
still going. The menu bar says that again, from outside the window, where you
actually have the question. The mark was a fourth copy of a fact, and it was
sitting in the one part of the row that costs the name its width — and the name
is the part you are reading.

It was also the only picture in the app that belonged to somebody else. Three
vendors' logos down the side of a window make a strip that reads as a list of
products rather than a list of your work. The marks are not gone; they are on
the landing screen, where you are choosing between agents and the question they
answer is a real one.

Getting there took two wrong answers first. The marks began in their makers'
colours — Claude in Anthropic's orange, Gemini in Google's blue — and a brand
colour is by definition the one colour that does not move when the window changes
around it: pick Matcha and the sidebar went green with an orange spark sitting in
it. So the colour became the theme's accent and the *shape* carried which agent
it was. That fixed the clash and left the slot itself unjustified.

What survives is the case an icon was always for: a tab doing something you did
not start on purpose in this window and would not guess from the name — vim
holding a file open, a build, an ssh session. One symbol, at one weight, in the
tertiary text colour, so the icons that do appear read as a set. A shell at a
prompt still gets nothing, because every tab in a terminal app is a terminal.

An agent is still *recognised* — `claude`, `codex`, `gemini`, `opencode` are
matched on a prefix so the display name and the executable both land. What the
match earns is the empty slot: without it they would fall through to the
gearshape every unrecognised process gets, which is a picture, in the place this
went to empty.

## It looks like something you chose

<img src="docs/images/themes.png" alt="The theme picker, fourteen themes">

Fourteen bundled themes, applied as you pick. Each is a JSON file carrying the
chrome colours, the terminal bed and a sixteen-colour ANSI palette. Drop your own
in `~/.ocarina/themes/` and they appear beside the bundled ones.

They used to be one theme with different wallpaper. The terminal palettes had
always carried real colour; the *chrome* did not — panels at 5–30% saturation
read as near-black whatever hue was nominally in them, four themes drew their
borders and row washes in pure white, and the house theme had no hue at all.
Every panel, edge, wash, accent and text weight is now mixed from the theme's
own hue.

Getting there took four goes and two of them are worth recording. Adding hue at
the old lightness changed nothing you could see. Raising the *lightness* fixed
that and broke something better: panels at 19% are not a dark theme any more.

Colour at low lightness comes from saturation, not from light — a panel at 10%
lightness and 34% saturation is a navy or a wine, unmistakably that colour and
*darker* than the grey it replaced. The fourth pass is the same idea with the
volume down, because "enough saturation to see" and "as much as the formula
allows" are not the same number and the third pass reached for the second one.
A panel should read as a dark room with a colour in it, not as the colour:

    ground   3%      the window, behind everything
    bed      5%      the terminal card
    panel   7-10%    the sidebar, the task list, the settings

The terminal ramp gets the twelve-degree hue pull and nothing else — no
saturation or lightness push. Sixteen colours turned up together is the largest
bright surface in the window, and it was the other half of what made the set
feel lit rather than dark.

`terminal.background` is now set to what is genuinely behind the text — the bed
composited over the ground at the bed's own opacity — rather than to a colour
nothing draws. It is the number the legibility floor measures against, so the
floor now guards what the eye is actually reading.

The selected tab wears the accent, fill and edge, at 11% and 34% — enough to
say which theme you are in, not enough to be the brightest thing on screen. It
was a white-ish wash under a white-ish border, which is the same faint grey
rectangle in all fourteen themes, on the one row you look at most.

Ten of the fourteen also shipped the *same* sixteen terminal colours, so `git
status` came out identical whichever you picked — which is most of why the set
felt flat. Each ramp is now pulled towards its theme's hue, and pulled by no
more than twelve degrees. That cap is the whole lesson of the first attempt: a
fraction of the way round the wheel takes the shortest path, and from red to a
blue theme the shortest path runs backwards through magenta. Twenty per cent of
it landed on pink, and yellow landed on red — a theme whose "yellow" output
printed in the colour its errors print in. Twelve degrees is a family
resemblance that cannot be misread as a different colour; the rest of the
character comes from saturation and lightness, which carry no meaning to break.

Every colour is then checked against the reading floor and lifted until it
clears — turning saturation up takes light out of a colour, and one theme's dim
grey, which is where comments land, fell to 4.38 against a floor of 4.5.

Every theme also has a surface. Blueprint is ruled in an engineering grid,
Matrix in scanlines, Steel in the grain of rolled metal; Ocarina is a honeycomb,
Sakura a lattice of diamonds, Ocean rows of chevrons. Thirteen of them, no two
alike, at four to six and a half hundredths — you should not be able to say what
the pattern is without looking for it. The panel simply stops reading as a flat
rectangle. It is drawn between the panel's fill and its sheen, so the light
lands across the texture instead of the texture sitting on the glass.

The first version of this drew pictures — petals, leaves, embers, rain,
scattered on a jittered grid. Read at one row it was texture; read down a column
of tabs it was litter behind the thing you were trying to scan, and it came out
entirely. What was wrong with it was not that it sat behind content but that it
had a subject: the eye finds a blossom, resolves it, and has spent attention
that belonged to the tab you were reading. A lattice has nothing to resolve. It
is regular, it is about nothing, and it reads as what the panel is made of
rather than as things lying on it — which is also why these are ruled rather
than jittered. The scatter existed to stop nine repeated blossoms looking like
wallpaper, and a grid of lines has no such problem.

High Contrast has no surface, and `nil` is the honest value rather than a
quieter setting: texture is the last thing that helps somebody who needed to
turn contrast up. Steel is the one lattice that is not regular, because an
evenly ruled one is printed paper and that surface has to read as a material.

The pictures were not thrown away, though. `Trinket` keeps them on the one
surface in the app that has no content to be behind: the landing screen is empty
by definition — that is its whole name — so a handful of petals crossing it is
the only thing on screen that is neither the app's name nor a button, and there
is nothing there for it to get in the way of. It appears nowhere else, and there
is no field for making it appear anywhere else.

Each theme gets its own: Sakura has petals, Matcha leaves, Ember rising sparks,
Ocean bubbles, Midnight stars that fade where they are, Matrix its rain, Ocarina
a few musical notes. Mono and High Contrast have none, and `nil` is the honest
value for both rather than a quieter setting — Mono is a theme about not doing
this, and High Contrast exists for people for whom moving decoration behind text
is the problem rather than the charm.

Everything about them is measured to stay a trinket. They cross in twelve to
forty seconds, which is slow enough that you notice one has moved rather than
watching it move; rain is the deliberate exception, because rain is supposed to
read as weather and nothing else is. There are eleven to twenty-six on screen,
which is short of the number where you would have to count them. And every one
is drawn under a third opacity — a test enforces it — because the landing screen
has four icons and a button on it that somebody is choosing between, and the
moment a petal is as strong as the thing it crosses behind, the petal has won an
argument it should not have been in.

None of it is stored. Every particle's position is a function of the clock and
its own index, so there is no simulation running, nothing to reset when the
screen comes back, and no drift between one appearance and the next. It is one
`Canvas` under a `TimelineView` rather than a view per particle: twenty-two
SwiftUI views with animations of their own is twenty-two things for the layout
system to think about sixty times a second.

### The one Easter egg

The wordmark on the landing screen is the only thing there that does nothing,
which makes it the one thing that can afford to. Press it and the trinket surges
— everything quickens and brightens for two and a half seconds and then settles
— and the tagline gives way to a line the theme gets to say for itself. Matrix
says WAKE UP. Sakura says NOTHING HERE STAYS. Ember says STILL WARM. Ocarina's
own says PLAY IT AGAIN.

That is the entire feature, and its shape is the argument for it. The landing
page was just cut from seven things to five for being a menu with no order to
it, and the way to put personality back into a page like that is not to add a
sixth line that everybody has to read forever. `flavour` is never on screen
until you go looking, and a theme without one keeps the app's tagline and still
gets the flurry.

Body text is white with a *tinge* of the theme, not the theme's colour set as
words — and that is a ceiling rather than a rule about how much hue to add.
Thirteen of the fourteen were already written that way, at a chroma between
0.01 and 0.13; Matrix was the exception at 0.41, and its screen was the one
where the text *was* the theme rather than wearing it. Anything above 0.14 is
pulled towards the grey of its own luminance until it sits at the ceiling, so
Matrix's `#8CF5A3` is drawn as `#BFE2C6` and the other thirteen come through
untouched. The two whites in the palette answer to the same ceiling, because
they are the text colour in every bundled theme, and capping one without the
other would leave a program printing in white louder than the line above it.
Anyone's own theme gets this too, which a hand-edited palette would not have.

A theme also reaches inside the programs the terminal runs. Setting the sixteen
ANSI colours used to be the whole of a palette, and it is not how the tools
people run colour themselves any more: Claude Code names its gold outright,
`38;5;220`, and no theme can touch a colour named in full. Choosing Matrix and
opening an agent gave you a green window with a gold program sitting in it.

Sending every such colour to its nearest slot fixes that and breaks something
worse. Against a theme built around one hue — Matrix, whose palette's "yellow"
is a green — an agent's gold chrome and its added lines both came back green,
and *added* against *removed* is the one distinction in a terminal you cannot
afford to lose. So the rule is narrow, and it is about what a colour is for:

- **Red and green are left exactly as the program sent them.** They are the two
  colours that carry meaning rather than decoration — failed and passed, removed
  and added — and a theme does not get a vote on those.
- **A program's own accent is toned down to plain text.** The gold is branding:
  the loudest thing on the screen, saying nothing the words beside it do not.
  Plain text means the theme's foreground *with the hue taken out* — near-white
  on a dark theme, near-black on a light one — and not the foreground itself,
  which is not neutral in every theme: Matrix sets it to `#8CF5A3`, so an accent
  handed the text colour came out bright green, which is a long way from toned
  down. The way to stop a colour shouting is to give it no hue at all. As a
  *background* it keeps a hue — a warm bar is a marked row, a white one is
  nothing.
- **The cool hues take the theme's own — unless the theme answers with a red or
  a green.** Blue, cyan and magenta are where a TUI draws its furniture, and
  furniture is decoration. But the colour Claude Code paints the *selected*
  option of a yes/no prompt in is that pale blue, and Matrix answers "blue"
  with `#8AF0A5` — so "No, exit" came up green, a negative call to action
  wearing the colour of go. The theme's answer is checked before it is given:
  a recolour may change how decoration looks, never what it appears to mean.
- **Greys are left alone.** A grey is already neutral, so there is nothing in it
  for a theme to answer, and answering anyway is how a program's quiet secondary
  text came back faintly green, or faintly pink.

The eight ANSI colours and their bright variants pass through untouched — those
were already the theme's to answer. The ground is its own case: a program
painting its background the colour of the terminal's is asking for the
background, so it gets the *default* one and the window's glass shows through,
rather than an opaque slab of the theme's black. A switch under the swatches
turns the whole thing off.

The picker is not a sheet. A sheet on macOS is modal and will not dismiss on a
click outside it, and picking a theme is a thing you do by trying three and then
getting on with your work.

Choosing a theme also sets `NSApp.appearance`. System controls — the keep-awake
switch, the menus, the window's own furniture — draw themselves and take their
cue from `NSAppearance`, not from us; without this a light theme kept a dark
switch and dark scrollbars, which reads as a half-finished theme rather than a
choice.

The interface is set in Geist and the terminal in JetBrains Mono — the terminal
needs a fixed cell, and a proportional face there does not look wrong, it tears.
Both are bundled and registered before the first frame draws, so nothing flashes
through a fallback face on its way to the right one. Both are under the SIL Open
Font License, and because they come from different projects each carries its own
copyright line, so both licence files are in
`Sources/OcarinaUI/Resources/Fonts/`.

## It stays awake while you wait

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

## What the terminal is drawn on

The largest surface in the window was one flat colour, and a flat colour behind
monospaced text is a text field. Every other surface in here is lit from
somewhere and sits in the theme; that one did neither, so a Sakura window came
out pink down both sides and plain dark in the middle.

`TerminalBed` is four layers, none of which you are meant to look *at*. The bed
colour at the theme's own opacity, untouched — it carries the contrast the whole
app is checked against and is not a place to put a mood. A wash of the accent
falling from the top-left, gone by the middle of the card, so the bottom of a
long scrollback is not a different colour from the top of it. The board's dot
grid, which is the one thing that makes this Ocarina's terminal rather than a
terminal. And the edges falling away, which is what stops the grid reading as a
pattern: it is strongest where you are working and gone by the corners.

The first version of all this was measured in hundredths and came out as a
surface you had to be told was there, which is not a texture doing its job. The
grid runs at a 6pt pitch with a 1.9pt dot and the vignette reaches 0.62 of the
window's own ground. What keeps it out of the way is not faintness but where the
colours come from: the dots are the board's *unlit* colour, which is already
sitting behind every word on the empty screen, and the vignette darkens towards
the window's ground rather than towards black. The pitch stays clear of any
plausible line height, so the rows of dots never come into step with the rows of
text.

The grid is one rasterised tile repeated by the compositor rather than a `Canvas`
painting every dot: that is how `DotMatrix` does it and it is right for a panel
of forty characters, but a bed is tens of thousands of dots and redraws with the
window.

Across the top of the card is a rail in the colour of whatever the tab is doing,
in the same four colours the status dots use, so amber means the same thing three
feet from the screen as it does in the tab list. It earns the space by being the
one signal you can take in without looking at it — a long build turns the top of
your terminal amber and back again, and you never had to find the dot. Idle is
present but quiet: a tab waiting at a prompt is open and ready, which is the
argument the status dots already settled, but it is also the state a terminal is
in almost all the time, and a rail at full strength for the ordinary case is a
rail that says nothing. It fades out at both ends rather than running edge to
edge, because a full-width line in a saturated colour is a border and the card
already has one.

## And when there is nothing open

<img src="docs/images/empty.png" alt="The departure board with no tabs open, and the empty task panel">

### It remembers where you work

Under the button, a row of the folders you have been working in — name first,
and the agent you last ran there in a quieter weight beside it. Pressing one
opens a terminal already in that directory.

**Nothing asks you to add a folder.** The shell reports where it is on every
prompt — that is what OSC 7 is for, and `ShellIntegration` now emits it beside
the command boundaries it was already sending — so the list builds itself out of
ordinary use. A `cd` into a project is what puts that project on this screen. A
recent list you have to curate is one that goes stale the week you stop
curating it.

Your home directory is not a project. A terminal opens there when it has nowhere
better to be, so recording it would put the one folder you did not choose at the
top of a list of folders you did. A folder that has since been deleted is
dropped on the way *out* rather than on the way in: projects move, get
unmounted, and come back, and forgetting one the moment it disappears loses it
for good.

The agent is shown and never acted on. Which one you used here last says what
the folder is for in a single word — and it is not an instruction: an app that
launches Claude because you launched Claude last time has decided what you came
to do. Running a plain shell in a project does not clear it either, because
walking through a folder in zsh is not evidence that you have stopped using an
agent there.

The row is under the four tools rather than over them, and it is not drawn at
all on a first run. A row of your own folders is the fastest thing on this
screen for somebody who has used the app before, and it is meaningless to
somebody who has not — who is exactly who the tools above are for. So the screen
answers the new user first and the returning one second.

Names, not paths: at this size `~/Developer/clients/acme-rebuild` is a row you
read rather than scan, and the whole value of the row is that it is scanned. The
path is on the tooltip.

Five of them. It is a way back to work, not a file browser.

Close every tab — or launch Ocarina for the first time with nothing installed —
and the window is given over to a landing screen: the wordmark in dot matrix, a
row of tools under it, and a button for a plain terminal.

"Open new terminal" is a real button again, after a spell as one word in a line
of small grey text. Cutting it that far was overcorrecting for the lit slab it
used to be: that slab was the biggest object on the screen, which said opening a
bare shell was the main event on the day you install this, and it is not. But it
is still the second thing anybody wants from a terminal app, and the second
thing should look like something you can press. It sits under the tools rather
than over them, drawn in the accent at a quarter strength.

The screenshot above is the older version of this screen, with the lit NEW
TERMINAL slab that the row of tools replaced.

### It arrives rather than appearing

Everything on this screen is static by nature — a mark, four icons, a button —
so for a while the only thing saying the app had come to life was the trinket
drifting behind it, which reads as weather rather than as an arrival. Now the
screen assembles itself in three beats: the name lights up column by column the
way a departure board powers on, the line under it follows, and the row of tools
rises in behind them a tile at a time. One thing after another rather than all
at once — three things moving together is a transition, and three things moving
in order is something putting itself together.

All of it runs left to right, including the tiles, so the screen assembles in
one sweep rather than in two arguing about which way to read it. It takes about
a second, and it runs once: coming back here after closing a tab does not replay
it, because the app introducing itself every time you close the last tab is the
same joke told twice. Pressing ⌘T through it costs nothing.

When the name has finished arriving it keeps a slow sweep running through it —
the same chase the mark in the sidebar runs while an agent is working, and it
cannot be misread as that here, because this screen only exists when there is
not a single tab open and so there is nothing that could be running.

A tool under the pointer lifts two points as well as growing. Scale on its own
is a tile getting closer to you; a little rise with it is a tile picking itself
up off the screen.

### The tools

This is the screen somebody sees on the day they install Ocarina, and until now
it handed them a blinking prompt and wished them luck. A terminal with nothing
in it is not a starting point for the person this app is for — it is the end of
the road, because the next thing to type is the one thing they do not know.

So under the mark there is a row of four: Claude, Gemini, Codex, and a `+` for
everything else. Each one is an icon, a word, and what pressing it will do —
`Open` if it is on this machine, `Install` if it is not — and the ones already
installed come first, because on every launch after the first the thing somebody
is reaching for is the one they already have. A tool that is not here yet is
drawn with a dashed edge: missing has to look like an outline waiting to be
filled rather than like a tool that is present and switched off, and dimming
alone reads as the second thing.

The marks are geometry rather than image files. A bundled logo is somebody
else's trademark travelling inside this app; a PNG cannot take the theme's
colour, and every other lit thing on this screen does. They are recognisable
rather than exact — a burst, a spark, a hexagon — and the word underneath is
what actually names the tool.

The screen reads top to bottom now: the mark, one line for somebody who has
nothing yet, the row of tools, a button for a plain terminal, and one quiet key.
It was seven things — a wordmark, a tagline, a heading, a
row of dot-matrix plates, a caption explaining the plates, a lit slab reading
NEW TERMINAL, and three rows of shortcuts — and seven things competing on an
otherwise empty screen is not a landing page, it is a menu with no order to it.
The wordmark stays in dot matrix because that is the one piece of pure identity
Ocarina has; everything under it is ordinary type and ordinary icons, because it
is ordinary interface, and a tool's name drawn in a 5x7 grid looked like part of
the logo rather than part of the list.

Pressing one runs it. Installed, it opens in a new tab; missing, the install
runs in a new tab. That is a deliberate exception to the rule the rest of the
app follows — Quick Actions and the paste inspector type a command and stop, and
`TerminalSession.type` will not press Return for anybody — and the exception is
narrow on purpose. The distinction between "install this" and "open this" is one
the person on this screen cannot make yet: they pressed Claude, and what they
meant was *give me Claude*. The command is still sent as keystrokes rather than
run behind the screen, so it is echoed at the prompt with its output underneath.

Which tools are installed is read when the screen appears and again when the app
comes back to the front, rather than held from launch — this is exactly where
you land after an install, by closing the tab it ran in, and a value cached at
launch would tell you the thing you just watched arrive is not here.
`ErrorHelp.location(of:)` does the looking, the same search the error banner
uses, so the screen cannot call something missing that the banner is happily
offering. It includes `~/.local/bin`, which is where the native Claude installer
puts its launcher and is not on the `PATH` of an app launched from Finder.

On the very first launch, with nothing installed, no tab is opened — the screen
is the whole answer to "I just installed this, now what", and a tab opened on
top of it hides the answer behind a prompt. Once, though, and not once per
launch: somebody who has decided to use Ocarina as a plain terminal and never
install an agent has made a choice, and meeting them with the same pitch every
morning is nagging rather than helping. `⌘W` brings the screen back whenever
they want it.

A new tab's shell is still starting when an icon is pressed — `zsh -l` sources a
profile before it prints anything — so `runWhenReady` waits for the shell to
draw something and then go quiet for 250ms before sending. There is no readiness
signal from a pty, and text sent into that gap is echoed above the prompt or
read by whatever the profile is doing with stdin. A shell that prints no prompt
at all still gets the command, at a three-second deadline.

The install commands are the same `Recipe` entries Quick Actions uses, found by
id, so an icon and the drawer cannot drift into disagreeing about what "Claude"
installs — and an icon whose id has no recipe behind it is a test failure rather
than a button that silently does nothing.

It borrows the look of an airport departures board but not its furniture. A
clock, gate numbers and an ON TIME column are what such a board carries because
a flight has a time and a status; a terminal that does not exist yet has
neither, so drawing them was decoration dressed up as information. What earns
its place is the matrix itself.

The same alphabet carries the wordmark at the top of the sidebar, small and lit,
so the window wears its mark whether or not there is a terminal open. Its lamps
are brighter than the theme's accent on purpose: the accent's lightness is
right for a border and wrong for a lamp, and derived from it directly the mark
came out the dimmest thing on the panel. The
titlebar's own "Ocarina" is hidden to make room for it — otherwise the window
wore its name twice, ten points apart.

`DotMatrix` carries a 5x7 font and paints **every** cell of the grid, dark when
it is off. That is the whole character of the thing: the unlit dots stay visible
behind the words, so the text reads as lamps that happen to be on rather than as
glyphs floating on black. Characters are five cells wide with one blank column
between them, so padding two strings to the same length is all it takes to make
their columns line up.

---

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
Scripts/make-app.sh debug    # a separate app -> build/Kazoo.app
open build/Ocarina.app
```

The debug build is a *separate app*, not the same one rebuilt: its own name,
bundle identifier and executable name. Sharing any of the three meant Launch
Services, the Dock and ⌘-Tab could not tell a test build from the installed one.

It is called Kazoo rather than "Ocarina Dev". The identifier was already
separate; the name was not. Every list that sorts by name — Privacy & Security
above all, where Screen Recording, Accessibility and Full Disk Access are each
granted per app — showed "Ocarina" and "Ocarina Dev" as two near-identical rows
under the same icon, and a grant toggled on one is indistinguishable from a
grant on the other. A test build has to be unmistakable in that list, which
means a name sharing no prefix with the real one.

Both are signed against a designated requirement naming the bundle identifier,
rather than the one macOS derives on its own. Left to itself an ad-hoc
signature has no certificate to point at, so the requirement it derives is the
hash of that exact binary — which the next build changes. Anything granted
under Privacy & Security, Screen Recording most of all, is granted against the
requirement stored at the time, so every build read as an app the Mac had
never seen and asked again. Pinned to the identifier, one grant holds.

One behaviour differs between bundled and not. A binary run from a shell
inherits that shell's directory, so tabs opened where you were; an app launched
from Finder inherits `/`, and every new tab opened at the root of the disk and
was named for it. A session with no directory of its own starts at home.

## Keyboard shortcuts

| | |
|---|---|
| ⌘T | New tab |
| ⌘W | Close tab |
| ⇧⌘] / ⇧⌘[ | Next / previous session |
| ⌘1 … ⌘9 | Go to the nth session |
| ⇧⌘P | Command palette |
| ⌘J | Show or hide the task panel |
| ⌘K | Clear the terminal |
| ⇧⌘K | Quick actions |
| ⌘V | Paste, through the inspector |

**⌘K clears, and Quick Actions moved to ⇧⌘K.** Every Mac terminal since
Terminal.app has cleared on ⌘K, and somebody arriving here presses it expecting
an empty window — it opened a drawer of agent installers instead. Clear wipes
the screen and the scrollback, then sends Ctrl-L so whatever is in front redraws
itself: readline puts the prompt back and keeps a half-typed line, an agent's
own drawing repaints. Without that last step the window is left blank until the
next keystroke, which reads as a terminal that has died rather than one that has
been cleared.

**Next and previous walk the column, not the order you last used.** ⇧⌘] and ⇧⌘[
are what Terminal.app, Safari and Chrome all use to step along a row of tabs,
and they step through the order the sidebar draws — a pair of shortcuts moving
you through an order with no representation on screen is a pair you cannot
predict. They wrap, because the column is a ring you cycle rather than a list
you run off the end of.

Recency belongs to the palette instead, where the order is drawn: ⇧⌘P with
nothing typed lists sessions **most recently looked at first**. With ten open,
the two you are moving between are almost never neighbours in the sidebar, so
the column's order is the right one to read a list in and the wrong one to
search it in. Typing hands the order back to the match.

⌘9 is the ninth session, not the last one. Browsers make ⌘9 mean "the last one";
terminals do not, and somebody who has learned that ⌘3 is the third tab should
not find the rule stops holding at nine. Out of range does nothing rather than
clamping — ⌘7 with four tabs open is a slip, and landing on the fourth is a
silent answer to a question nobody asked.

They come from the menu bar in `MainMenu`, not from SwiftUI
`.keyboardShortcut`. AppKit offers a key equivalent to the main menu before the
event reaches the window or the responder chain, so a menu item always gets it;
a hidden SwiftUI button only sees what makes it as far as the view hierarchy,
which a terminal view holding first responder can swallow. Ocarina had no main
menu at all for a while, which is why ⌘W did nothing — and why ⌘Q didn't either.

The Edit menu's cut and copy have no target, so they travel the responder chain
to SwiftTerm, which implements them.

---

# How it is built

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
  StatusCardView         working, done or stopped, under the task list
  ThemeStore / Theme     bundled + user themes, and the colour model
  ThemePickerView        pick by looking, not by remembering names
  CommandPaletteView     jump by what a terminal is doing (⇧⌘P)
  QuickActionsView       recipe drawer (⇧⌘K); types, never runs
  PasteInspector         reads a paste before the terminal does
  ErrorHelp              hand a failure to an installed agent
  EmptyStateView         no tabs open: the departure board, and recent projects
  RecentProjects         the folders you work in, learned from the shell's own OSC 7
  AgentDock              the row of tools on it, and their state
  AgentCatalog           what the row offers, and what is installed
  AgentMarks             the marks each tool wears, drawn as geometry
  TerminalBed            what the terminal is drawn on, and the activity rail
  Trinket / TrinketField each theme's own small thing on the landing screen
  Pattern                the geometric lattice each theme's panels are ruled in
  DotMatrix              5x7 dot-matrix panel, the board is built from it
  ActivityCard           the departure-board cell the menu bar item wears
  OcarinaIcon            the bundled app mark, prepared for the dock
  FeedbackView           the report sheet, and the issue URL it builds
  ClearedTasks           the per-project line under the task list
  PackagedResources      finds the resource bundle inside a built .app
  Theme / ThemeColor     the colour model a theme file decodes into
  Recipe                 the quick-actions catalogue
  Skill                  the skills catalogue, and where each agent reads them
  SkillShelf             what is installed, going in, or waiting for an agent
  SkillNoticeView        the strip that says an install landed, or is waiting
  SkillInstaller         fetches a skill's folder out of its repository
  SkillsView             the browser: search, filter, one click to install
  ErrorBannerView        what a failed command puts on screen
  PasteReviewView        the sheet a risky paste stops at
  TactileClick           the click a switch makes
  AppIdentity            what this build calls itself
  TabIcon / StatusDot    a symbol, when one is owed, and a state for each tab
  SleepGuard             holds the Mac awake while Ocarina is open
  BundledFonts           registers Geist and JetBrains Mono before frame one
  MainMenu               the menu bar; every shortcut, and Share Feedback
  ToolTip                AppKit tool tips, because .help draws none here
Sources/Ocarina/         executable entry point
```

SwiftTerm is used only as the VT parser and screen grid. Ocarina spawns the pty
itself, via `forkpty`, because `login_tty` is what makes the pty the child's
controlling terminal — and without that `tcgetpgrp` reports nothing and the
naming layer is blind.

### Where the resources have to live

SwiftPM generates a `Bundle.module` accessor for `OcarinaUI` that looks in
exactly two places: `Bundle.main.bundleURL/Ocarina_OcarinaUI.bundle` — the root
of the `.app` — and the absolute `.build` path baked in when it compiled.

Neither is usable. The bundle root cannot hold the resources, because `codesign`
refuses to sign a bundle with anything loose at the top (`unsealed contents
present in the bundle root`), and a symlink there is refused for the same reason.
So they are sealed in `Contents/Resources` and `PackagedResources` looks for them
there, keeping `Bundle.module` as the fallback that `swift run` and the tests use.

This is worth knowing because getting it wrong is invisible on the machine that
built the app: the second candidate is a real path on that disk, so it loads and
everything works, while every downloaded copy dies on launch. `make-release.sh`
fails the build if the bundles are missing from the app, and the only honest way
to check by hand is with `.build` moved away entirely.

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
nothing; `TabIcon` gives one a symbol only when its foreground process is
something you would not guess from the row — so a tab holding a file open in vim
reads differently from a build across a sidebar of twenty, and an agent, which
its own name already describes, carries none.

Glass needs something behind it to blur. An `NSVisualEffectView` sits behind the
hosting view and the window is non-opaque, so the materials in the chrome have
the desktop to work with; without it they resolve to flat grey. The terminal
view's own background is cleared and a themed bed sits behind it — the glass
reads through, and the text stays legible.

## Tool tips

A tip is taken down when the control it explains is *removed*, not only when
the pointer leaves it. The close button on a tab exists only while its row is
hovered, and a view taken out of the tree never receives `mouseExited` — so
leaving a row briskly deleted the button while its "Close this tab (⌘W)" was
up, and nothing was left to retract it. It sat there until some other control
happened to replace it. Every control that can vanish under the pointer has the
same problem, which is why the fix is in the modifier rather than in the tab
row.


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
