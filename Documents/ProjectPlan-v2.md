# Project Plan v2: Agentic Pascal in the Lazarus IDE

**Michell Computing Style Lazarus Package Suite**
**Version:** 2.2 (Planning)
**Date:** 2026-08-21
**Author:** FreePascal Engineer
**Supersedes:** [ProjectPlan.md](ProjectPlan.md) for LazAssistantTools architecture. LazRepositoryTools and LazWorkflowCommon stay as shipped in v0.2.
**Reference:** [xai-org/grok-build](https://github.com/xai-org/grok-build) (Apache 2.0) — workflow and software *structure*, not a Rust port.
**Target Platforms:** Linux (GTK3/Qt6), Windows, macOS (Cocoa)
**Lazarus / FPC Baseline:** Lazarus 3.x / 4.x + FPC 3.2.2+ (ObjFPC)

---

## 1. Vision

Build the best-in-class **agentic Free Pascal / Lazarus programming tool**, fused with the IDE — not a chat box that happens to live in a dock.

Grok Build is the quality bar for chain-of-thought feedback, tool visibility, harness discipline, and agent structure. This plan copies that *architecture* into Michell Computing Pascal, and uses the IDE as the native surface (editors, Messages, forms, compile, Git).

v0.2 delivered a working Project Assistant (Chat / Plan / Code, streaming, tools, history JSONL). v2 replaces the assistant *runtime and working surface*. It does not throw away OAuth, path sandbox, plan `Status:` scan, IDE buffer edits, or Repository tools.

**Success looks like this**

- Thinking is a live, structured agent trace: reasoning, tool cards, compile, subagents — as readable as Build.
- Watching that trace, the user can **steer** the still-running turn (a clarification, correction, or extra idea) without stopping it.
- Every capability is **discoverable** from the window (menu, palette, slash, footer) — nothing useful lives only as a `/` secret.
- One conversation. Modes are permission overlays, not three different products.
- The harness (system prompt, skills, project rules, todos) is in the same family as Build, specialised for Michell Pascal.
- The compiler is the syntax checker. LLM subagents are for *review lenses* and *bounded parallel work*, not for re-doing `lazbuild`.

---

## 2. Direct answer: specialist subagents vs one pass

**Grok does not internally spawn a naming agent, a syntax agent, and a structure agent on every turn.**

A Build turn is one model, one reasoning stream, tools as needed. Naming, clashes, and subroutine shape are handled in that pass when the skill / project rules are in context. Subagents in grok-build exist for a different job:

| Build uses subagents for | Build does **not** use them for |
|--------------------------|---------------------------------|
| Bounded parallel research (`explore`) | Per-concern lint on every edit |
| Isolated implementation (own context, optional worktree) | Replacing the compiler |
| An explicit second-pass review (`/review`) | Always-on three-way debate |
| Goal planner / classifier (optional, capped) | “Syntax specialist” vs “naming specialist” as default architecture |
| Depth **one** (a child cannot spawn children) | Unbounded agent trees |

That split is the right one here.

**Keep in the primary agent (one pass)**

- Michell naming, `F` vs streamed components, reserved-word collisions, `Begin`/`End` style — via `free-pascal-engineer` always on in Plan/Build.
- Tool loop: search → read → edit `.pas`/`.lfm` → `run_compile` → fix.
- Ordinary judgement about subroutine structure while writing the code.

**Do not use an LLM subagent for**

- **Syntax.** `lazbuild` / IDE compile is deterministic, faster, and the ground truth. Feed Messages back into the parent. A “syntax subagent” would guess what the compiler already said.
- **Name clashes that a grep can prove.** `search_in_project` / a small Pascal symbol scan is cheaper and exact.

**Do use specialist subagents as review *lenses*, on demand**

After a Build turn (or on **Review**) the parent may fan out **read-only** children against the *changed files only*:

| Lens | Job | Tools |
|------|-----|--------|
| `pascal-naming` | Michell identifiers, `F` prefix, streamed-component names, collisions with `TControl`/`TForm` members | read, grep, project search |
| `pascal-structure` | Unit size, interface/implementation split, form `.lfm` pairing, layering | read, grep |
| `pascal-review` | Correctness, threading, memory, “does this actually fix the request” | read, grep, optional compile messages (no writes) |

Rules copied from Build:

- Depth one.
- Children return a structured summary; they do not edit unless isolation is explicit and the user asked for it.
- Default Code/Build turn does **not** spawn them. Cost, latency, and contradictory advice are real.
- Cap live children (e.g. 3). Changed-file list is the input contract.

**Hybrid that actually works**

```
User request
  → one primary agent (skill + tools + compile)
  → optional Review: parallel read-only lenses
  → parent (or user) applies or discards findings
```

That is what Build already does with `/review` and `explore`. It is not a committee inside every keystroke.

---

## 3. What grok-build actually does (and what we copy)

Studied from the public tree (`crates/codegen/…`), not from folklore.

### 3.1 Layer cake (structure to mimic)

```
Sampler          Responses API stream; encrypted reasoning round-trip
  → Session actor  Turn loop, tool dispatch, persistence, permissions
    → Event log    Typed turn events (not two concatenated strings)
      → Tracker    Maps events onto scrollback entries
        → Blocks   Thinking, tool cards, agent markdown, subagent rows
          → TUI    Incremental paint, collapse/truncate/expand
```

Corresponding grok-build crates (names only — we reimplement in Pascal):

| Build crate | Responsibility | v2 Pascal home |
|-------------|----------------|----------------|
| `xai-grok-sampler` | HTTP, SSE, Responses vs Chat Completions | `AssistantSampler` |
| `xai-grok-sampling-types` | Conversation items, reasoning, tool calls | `AssistantProtocol` |
| `xai-grok-session-events` | `TurnStarted`, `PhaseChanged`, `ToolStarted`, … | `AssistantEvents` |
| `xai-grok-agent` | Prompt assembly, skills, AGENTS.md, agent defs | `AssistantHarness` |
| `xai-grok-shell` session actor | Run loop, tool rounds, subagent spawn | `AssistantSession` (thread) |
| `xai-grok-pager` scrollback | Typed blocks, thinking widget, tool cards | `AssistantTrace` + frames |
| `xai-grok-subagent-resolution` | Agent types, personas, capability modes | `AssistantSubagents` |

We do **not** embed the `grok` binary or speak ACP as the v2 product path. Native Pascal talking to `api.x.ai` keeps the IDE package self-contained. ACP as a later *optional* host is noted in §12, not in the critical path.

### 3.2 Why Build thinking feels rich and dynamic

Four separate mechanisms, all missing today:

1. **API channel.** Sampler uses the **Responses** API, always `include: ["reasoning.encrypted_content"]`. Displayable text is `response.reasoning_summary_text.delta` (and related reasoning items). Encrypted blobs are **round-tripped** on the next request so later tool rounds still “remember” how they thought. Chat Completions is the legacy path; grok-build’s own comparison is that reasoning support lives on Responses.
2. **Event stream, not two strings.** Thought deltas, content deltas, and tool start/update/end are *different events*. The UI never has to guess whether a blob is thinking or a tool.
3. **Typed scrollback blocks.** `ThinkingBlock` is its own widget: pre-created as “Thinking…” before the first token, `push_chunk` for incremental markdown, live elapsed, default **truncated** (last N lines), collapsed “Thought for Xs”, expand on demand. Tool calls are **cards** (read / edit / execute / search), not footer text. A new thinking block starts after tools; old ones stay.
4. **Coalesced paint.** Chunks merge; the UI is not a full-document reparse on every token.

### 3.3 What the Project Assistant does today (gap)

| | v0.2 assistant | Build |
|--|----------------|-------|
| Endpoint | `POST /v1/chat/completions` | `POST /v1/responses` (Chat Completions fallback) |
| Thinking field | `delta.reasoning_content` / `delta.reasoning` (summaries, often empty) | `reasoning_summary_text.delta` + encrypted round-trip |
| Per tool round | `FThinkingAccum := ''` — **wipes** prior thinking | Blocks accumulate; tools are siblings |
| Tools in the trace | Footer “Running tools…” | First-class cards with path, status, elapsed |
| Paint | Rebuild one Markdown document (~80 ms), full reparse | Incremental `push_chunk` on a thinking block |
| Prompt | Short mode string + optional one skill pasted in | Templated `prompt.md` + skill *catalog* + AGENTS.md + reminders |
| Modes | Chat / Plan / Code swap tools, prompt, **and side panel** | One session; Plan is a permission overlay |
| Subagents | None | `explore` / `plan` / `general-purpose`, depth 1 |

That is why thinking here is neither as rich nor as dynamic. It is not that Grok “thinks less” in the IDE.

---

## 4. Target architecture

```
┌─────────────────────────────────────────────────────────────────────────┐
│ Lazarus IDE                                                             │
│  ┌─ Project Assistant (dockable) ─────────────────────────────────────┐ │
│  │  Mode chip (Ask · Plan · Build)     permission, not a page swap    │ │
│  │  ┌─ Work ─┐  ┌─ Trace (scrollback of typed blocks) ─┐  ┌ History ┐ │ │
│  │  │ tiles  │  │ thinking · tool · compile · answer   │  │ JSONL   │ │ │
│  │  │ plan   │  │ subagent rows                        │  │         │ │ │
│  │  └────────┘  └──────────────────────────────────────┘  └─────────┘ │ │
│  │  Prompt  [Send] [Stop]          overflow: Review · Fix · Settings  │ │
│  │  Footer: model · skill · context · phase · elapsed                 │ │
│  └────────────────────────────────────────────────────────────────────┘ │
│  Editors · Messages · Forms · Manage Repository (unchanged packages)    │
└─────────────────────────────────────────────────────────────────────────┘
         ▲ events (main thread, coalesced)
         │
┌────────┴─────────┐     ┌──────────────────┐     ┌─────────────────────┐
│ Session actor    │────▶│ Sampler          │────▶│ api.x.ai /v1/       │
│ (worker thread)  │◀────│ SSE parse        │◀────│ responses (stream)  │
│ tool loop        │     │ encrypted store  │     └─────────────────────┘
│ subagent spawn   │     └──────────────────┘
└────────┬─────────┘
         │ tools on the thread that owns them
         ├─ file / grep          (worker, results queued)
         ├─ IDE compile/open     (Synchronize / Queue to main)
         └─ child session actors (one thread each, depth 1)
```

### 4.1 Unit map (keep units under ~1000 lines)

Replace the current “god form + god service” split (`ProjectAssistantForm.pas` ~4000 lines, `AssistantService.pas` ~1900, `AssistantTools.pas` ~2500) with:

| Unit | Layer | Notes |
|------|-------|--------|
| `AssistantProtocol` | Foundation | JSON types for Responses + Chat Completions fallback; no UI |
| `AssistantEvents` | Foundation | `TAssistantEvent` variants; JSONL writer |
| `AssistantSampler` | Service | HTTP + SSE; no tools; no form |
| `AssistantHarness` | Service | System prompt template, skill catalog, AGENTS.md, mode overlay |
| `AssistantSession` | Service | Actor thread: turn loop, tool rounds, encrypted reasoning store |
| `AssistantTools` | Service | Mode allow-list + executors (split files if still huge: Read / Plan / Code) |
| `AssistantSubagents` | Service | Spawn, capability mode, depth gate, summary back |
| `AssistantTrace` | Bridge | In-memory block list; not a form |
| `ThinkingBlockFrame` | UI | Streaming thinking |
| `ToolBlockFrame` | UI | Tool card |
| `AnswerBlockFrame` | UI | Final markdown (existing `TMarkDownControl`) |
| `SubagentBlockFrame` | UI | Child lifecycle row |
| `AssistantCommands` | UI | Action catalog: caption, category, slash alias, palette |
| `ProjectAssistantForm` | UI | Shell only: mode chip, work list, history, prompt, footer, menus |

Event bus stays `WorkflowEvents`. Git stays in LazRepositoryTools.

### 4.2 Threading (explicit, not accidental)

The v0.2 stream thread already exists; v2 makes the actor the centre.

| Thread | Owns | Must not |
|--------|------|----------|
| Main / LCL | Forms, frames, IDE APIs, coalesced event drain | HTTP, long compile wait without `Queue` |
| Session actor (one per conversation) | Sampler, event log, tool *policy*, encrypted reasoning, child handles | Touch LCL objects |
| Tool workers | `search_in_project`, disk reads, `lazbuild` quiet | LCL; use IDE compile via `Queue`/`Synchronize` |
| Subagent actors | Same as session, depth 1, own sampler | Spawn further children |

Rules:

- Events go onto a lock-free or CS-protected ring. Main drains at ~30–60 Hz and **coalesces** consecutive thought/content deltas into the current block.
- Never `Synchronize` per token (v0.2 snapshot queue is the anti-pattern to keep, but snapshots become *events*, and the UI applies deltas instead of replacing two giant strings).
- Tool-round thinking is **not** cleared. A `teLoopStarted` event opens a new thinking block; previous blocks stay in the trace.
- Cancel: set a flag on the actor; abort HTTP; children terminate; UI marks blocks cancelled.

Fine to have “a more elaborate structure.” This *is* that structure. It matches grok-build’s session actor vs pager split.

---

## 5. Reasoning feedback mechanism (the Build analogue)

This is the centre of v2.

### 5.1 Protocol

**Primary:** `POST {apiBase}/responses` with `stream: true`.

Request shape (conceptual):

```json
{
  "model": "grok-4.5",
  "input": [ /* conversation items, including prior encrypted reasoning */ ],
  "tools": [ /* mode allow-list */ ],
  "reasoning": { "effort": "high" },
  "include": ["reasoning.encrypted_content"],
  "store": false,
  "stream": true
}
```

Parse (from grok-build’s SSE fixtures):

| SSE type | UI / actor |
|----------|------------|
| `response.created` | `teTurnStarted`; **pre-create** thinking block (“Thinking…”) |
| `response.reasoning_summary_text.delta` | `teThoughtDelta` → `ThinkingBlock.Append` |
| `response.output_text.delta` | `teContentDelta`; finish thinking; append answer |
| function / tool call items | `teToolStarted` / argument deltas / `teToolCompleted` |
| encrypted reasoning on completed item | store opaquely on the session; **never display** |
| `response.completed` | `teTurnEnded` |

**Fallback:** existing Chat Completions parser if Responses is unavailable (HTTP 404/400). Document that thinking will be thinner on that path.

**Round-trip:** every subsequent request in the same turn *and* the next user turn includes the last encrypted reasoning item(s). That is how Build keeps multi-round thought coherent. v0.2 sends only `content` + `tool_calls` and drops reasoning.

### 5.2 Event model

`AssistantEvents` — one variant record / tagged object per line of `events.jsonl` (alongside existing history JSONL):

```
TurnStarted { session, turn, model, mode }
PhaseChanged { waiting | thinking | streaming | tools | review }
ThoughtDelta { text }
ContentDelta { text }
LoopStarted { index }          { new thinking block; do not wipe }
ToolStarted { id, name, argsPreview }
ToolProgress { id, detail }    { e.g. compile line counts }
ToolCompleted { id, ok, durationMs, resultPreview }
SubagentStarted { id, kind, title }
SubagentProgress { id, phase }
SubagentCompleted { id, ok, summary }
PermissionNeeded { tool, summary }
SteerQueued { text }           { shown in the trace immediately }
Interjected { text, at }       { merged at a safe gap; turn continues }
TurnEnded { outcome, error }
```

History JSONL v0.2 rows remain the *human* archive (prompt + thinking text + response). The event log is the *replay* source so a reopened turn can rebuild the trace (thinking blocks + tool cards), not a single blockquote.

### 5.3 Thinking widget (must not be a markdown blockquote)

Copy `ThinkingBlock` behaviour, not its Rust:

| State | Display |
|-------|---------|
| Pre-create | Header “Thinking…” + spinner / elapsed from local `Now` |
| Streaming | Body dim + italic; **truncated**: last ~8–12 lines, live append |
| Content started | Freeze elapsed; collapse to “Thought for 4.2s”; body hidden |
| User expand | Full text; optional markdown parse **once** on expand/finish |
| Hidden toggle | Skip creating blocks (preference `show_thinking`, already in config) |

Implementation for LCL (pragmatic):

- During stream: `TMemo` or a light custom paint of plain text (append-only, no lazmarkdown). Full markdown reparse of a growing blob is what makes v0.2 feel dead.
- On finish/expand: optional `TMarkDownControl` for that block only.
- Quote-bar / dim style to keep it visually secondary to the answer.

Multiple thinking blocks per turn (one per model loop) sit in the same scrollback as tool cards.

### 5.4 Tool cards (this is most of “dynamic”)

Every tool call is a block:

```
● read_file  Source/Foo.pas  12–80     0.3s
● replace_in_file  Source/Foo.pas      running…
● run_compile  quiet                   4 errors → click to Messages
```

- Start: name + argument preview (path, pattern).
- End: duration, ok/fail, short result (line counts, first error).
- Compile card can jump to Messages / Fix Error.
- Edit card can open the buffer at the change.

Without these, even perfect `reasoning_content` still feels like a wall of prose.

### 5.5 Coalescing and paint

- Actor pushes events as they happen.
- Main drain: merge consecutive `ThoughtDelta`/`ContentDelta` for the current block; apply at most ~30–60 Hz.
- Final event of a turn always flushes immediately.
- Do not copy the entire accumulated thinking string on every token (v0.2 `TStreamSnapshot`).

### 5.6 What we will *not* get

Public grok-4.6 thinking is still a **summary** of internal chain-of-thought, not the raw private trace. Build’s first-party path may be thicker. v2 can match Build’s *client* (Responses + blocks + tools + no wipe). It cannot decrypt encrypted content for display. That is a product/API limit, not a Pascal one.

### 5.7 Steering comments (mid-turn interjection)

This is a first-class v2 feature, copied from grok-build’s `xai-interjection-core` / session-actor drain — not a follow-up chat after the turn dies.

**The problem today.** v0.2 sets `InputMemo.ReadOnly` and disables `SendAction` for the whole stream (`SetSending`). The only mid-turn verb is **Stop**. If thinking reveals a better approach, the user must wait, or abort and lose in-flight work.

**You cannot splice tokens into an open SSE body.** The public API has no “append to this completion.” Steer happens at a **safe gap** in the actor loop, then the next model request includes the comment. That is how Build does it (`drain_interjections_at_safe_point`: after a tool batch, at loop top, before the turn returns).

Safe gaps in our actor:

1. After the current HTTP round finishes (thinking + content + tool_calls received).
2. After the current *in-flight tool* finishes — **do not cancel `run_compile`** because the user typed a note.
3. Before the next `POST /responses` (or Completions) round.

Until that gap, the UI still shows the comment in the trace as **Steer · pending**. Footer: “Steering at next tool gap…”.

**Envelope** (same idea as Build’s `format_interjection`; Michell-owned wording):

```
The user sent a message while you were working:
<user_query>
…steering text…
</user_query>
Incorporate this into the current task. Finish unfinished work unless the user
clearly cancelled or replaced it.
```

That goes on the conversation as a synthetic user item. Encrypted reasoning from the round just finished is still round-tripped, so the model does not amnesia the thought the user was reacting to.

Display in the trace as a normal user block with a small **Steer** badge — not a system footnote. Persistence: store the human text in history/events; do not store the envelope boilerplate as the visible prompt.

**Two verbs — do not collapse them**

| Verb | When | Effect |
|------|------|--------|
| **Steer** | Default mid-turn send | Queue the text; merge at the next safe gap; **turn continues** |
| **Stop and send** | User wants a hard redirect | Abort HTTP (and optionally running tools); next turn is a new prompt with an interrupt note (“The user interrupted the previous turn”) |

Build’s default `follow_up_behavior = "queue"` waits until the turn *ends*. That is the weaker product for “I just read the thought and need to correct it.” **Steer is the default mid-turn send in v2.** Queue-until-done can live in Settings for people who only want notes after the answer.

**In-flight tools.** A steer never kills `run_compile` / file writes already started. Stop does. If the user steers “don’t compile yet” while compile is running, the result still arrives; the next model round sees both the compile tool result and the steer.

**Idle / stranded.** If the turn ends before drain, the pending steer becomes the next user turn (Build’s interjection fallback). Never silently drop it.

**UI (shell)**

- Prompt stays editable while a turn is running (`ReadOnly := False`).
- Primary button while busy: **Steer** (caption swap on `SendAction`). Shortcut: `Ctrl+Enter` (Lazarus-friendly; matches Build’s “send now” family without fighting IDE `Enter` in a memo).
- **Stop** stays abort. After Stop, Send is a normal new turn.
- Optional later: a short “queued steer” chip above the prompt if several notes pile up (concatenate in order at one drain, or inject one-per-gap — prefer **concatenate one drain** so we do not multiply HTTP rounds).

**Out of scope for the first cut:** steering a *child* subagent independently (parent steer is enough; children finish or the parent cancels them). Images on a steer. Slash-command expansion inside a steer.

---

## 6. UI: one agent surface, modes as permission

v0.2 chrome is the other half of “clunky”:

- `TRadioGroup` Chat / Plan / Code **swaps the left panel** (Chat is a paragraph of help).
- Bottom bar shows **every** action (Review Compile/Build, Fix Error, Toggle Thinking, Auto New Chat) in every mode.
- Working surface is **current-turn-only** Markdown, so the tool story disappears.
- Mode change looks like a different app. It is not obvious whether history, the plan, and the prompt survive.

Build’s lesson: **the transcript never leaves the centre. Mode is a chip, not a page.**

### 6.1 Mode model (keep three intents, fix the meaning)

Rename **Code → Build** in the UI (package/type names can stay `amCode` until a rename pass). One line always visible:

| Chip | Permission | One-liner |
|------|------------|-----------|
| **Ask** | Read-only project tools | “Explains and inspects. Will not write files.” |
| **Plan** | Ask + Markdown under `Documents/` (and active plan path) | “Writes the plan file. Will not edit sources.” |
| **Build** | Plan + source tools + compile | “Edits project files and compiles.” |

Hard tool gates stay. In-flight mode lock stays.

**Same conversation across chips.** Switching Ask → Plan → Build does not start a new chat. The harness overlay and `tools` JSON change at the next request (or after cancel). History is the session, not “Chat history vs Code history.”

### 6.2 Layout

```
┌─ Project Assistant ──────────────────────────────────────────────────────┐
│ [ Ask | Plan | Build ]   Plan · Documents/ only          model  context │
├────────────┬──────────────────────────────────────────────┬─────────────┤
│ Work       │  Trace (always this)                         │ History     │
│ plan tiles │  user prompt                                 │ sessions    │
│ always     │  thinking block                              │ turns       │
│ visible    │  tool cards …                                │             │
│            │  answer markdown                             │             │
├────────────┴──────────────────────────────────────────────┴─────────────┤
│ Prompt   (stays live during a turn)                                     │
│ [Steer] [Stop]  Review ▾   Commands…   Fix Error   ⋯   ← palette, not 12 buttons │
├─────────────────────────────────────────────────────────────────────────┤
│ grok-4.5 · free-pascal-engineer · 12% · Thinking 4.2s                   │
└─────────────────────────────────────────────────────────────────────────┘
```

- **Work** is the plan-tile list in every mode (empty-state: “No active plan — switch to Plan to create one”). Selecting a tile seeds the prompt; **Work on this** is a Build action, disabled in Ask.
- **Trace** is a `TScrollBox` (or virtual list) of typed frames, not one `TMarkDownControl` for the whole turn.
- **History** stays the JSONL browser.
- Bottom bar is **short**. Review Compile/Build live under **Review**. **Commands…** (and `/` in the prompt) open the same catalog as the window menu. Auto-new-chat is a setting, not a permanent checkbox.

### 6.3 Mode interaction (the missing UX)

1. **Stay.** Default is last mode per project (`config.json`).
2. **Promote, don’t scold.** If Ask hits a write-shaped request, the answer can say so *and* the shell shows **Switch to Build to apply**. Same for “write a plan” in Ask → **Switch to Plan**.
3. **Plan approval.** When Plan mode finishes a write to the active plan, show a thin bar: **Build this** (chip → Build, seed “Implement the next incomplete section”) · **Revise**. This is grok-build `exit_plan_mode` in IDE clothes.
4. **Fix Error / Review** force Build (already true) and explain why in the badge, not a mystery tab jump.
5. **Empty states are one sentence**, not a help essay in the side panel. Chat’s current 300 px of documentation goes away.
6. **Steer while thinking** — prompt stays live; Send becomes Steer; see §5.7. This is the main reason the composer must not go `ReadOnly` during a turn.

### 6.4 Native IDE fusion (keep and deepen)

This is the product difference vs running `grok` in a terminal:

- Edits via IDE buffers (undo).
- `run_compile` → Messages; compile tool card links there.
- `ensure_form_component` remains a first-class tool (Build has no LFM).
- Open file / jump to line from tool cards.
- Repository **Suggest** commit message stays Chat/Ask (read-only diff).

### 6.5 Discoverability — nothing useful is `/`-only

Build’s power is real; a lot of it is easy to miss. The TUI puts compact, rewind, effort, skills, plan view, usage, doctor, and user-invocable skills behind **type `/` in the prompt** (and a `Ctrl+P` palette that many people never find). A Lazarus dock must not copy that hiding. The IDE user will look at **menus, buttons, and the footer** first.

**Rule:** every command has a caption, a category, and at least one visible surface besides slash. Slash is a *shortcut* for people who already know Build, not the catalog.

**One registry, many surfaces.** `AssistantCommands` (or the form `TActionList`, Michell default) is the only list. Every row is a `TAction` with:

| Field | Purpose |
|-------|---------|
| Caption | Human name (“Compact context”, not `/compact`) |
| Category | Session · Work · Review · View · Model · Skills · Help |
| ShortCut | Where it does not fight the IDE |
| Hint | One line for palette and status |
| Slash alias | Optional `/compact`, `/rewind`, … for the prompt popup |
| Enabled | Mode / busy / “has plan” predicates |

Surfaces that **all** read that list:

1. **Window menu** — `Session`, `Work`, `Review`, `View`, `Help` on the Project Assistant form (and a matching **Tools → Project Assistant** submenu in the IDE). This is the primary discovery path for a desktop IDE.
2. **Command palette** — `Ctrl+P` (and `?` while the assistant is focused). Searchable: caption, slash alias, hint. Same window as Build’s palette, but labelled **Commands** so it is not a secret. Button **Commands…** on the short bottom bar opens it.
3. **Slash popup** — typing `/` in the prompt filters the same catalog. Keyboard users who know Build keep the muscle memory; the popup shows the **caption** in the first column and `/name` dimmed, so a new user learns the name.
4. **Footer clicks** — model name → model/effort picker; context % → context breakdown (`/context`); skill name → skills list; status phase → session info. The footer is not decoration.
5. **Context menus** — on a history row: rewind to here, export, delete, rename. On a thinking/answer block: copy, expand, collapse. On a tool card: open file, jump to Messages.
6. **Empty-state line** in the trace, once: “Type a request, or open **Commands…** (`Ctrl+P`). Prefix `/` for the same list.” Not a 300 px help essay.

Do **not** put every command back on the bottom bar. That is how v0.2 became clunky. Discoverable ≠ always visible. The bar keeps the *verbs of the current state* (Send/Steer, Stop, Review ▾, Commands…, overflow). The catalog holds the rest.

**Map Build slash commands onto this product** (v2 must implement the left column; slash aliases in parentheses):

| Catalog caption | Build analogue | Surface besides `/` |
|-----------------|----------------|---------------------|
| New conversation | `/new` `/clear` | Session menu, existing button |
| Compact context | `/compact` | Session menu; offer when context ≥ ~85% (banner, not only auto) |
| Context breakdown | `/context` | Click context % |
| Session info | `/session-info` | Click model / Help |
| Rewind to this turn | `/rewind` `/undo` | History and trace context menu |
| Copy last answer | `/copy` | Trace context menu; Session menu |
| Export conversation | `/export` | Session menu (already an action) |
| Delete / rename conversation | `/delete` `/rename` | History panel |
| Model… | `/model` | Footer, Settings, Commands |
| Thinking level… | `/effort` | Footer, Settings (already a combo) |
| Approval mode… | `/always-approve` `/auto` | Settings, Session menu |
| Ask / Plan / Build | `/plan` + permission cycle | **Chips** (already visible) |
| Open active plan | `/view-plan` | Work panel, Work menu |
| Work on this / next package | (Code tiles today) | Work panel + Work menu |
| Review compile / build | Review actions today | **Review ▾** |
| Review changes (lenses) | `/review` skill | Review ▾ |
| Fix error | Fix Error today | Review ▾ / Messages |
| Show thinking | thinking toggle | View menu, existing button in overflow |
| Skills… | `/skills` | Footer skill, Settings, View menu |
| Run skill: *name* | user-invocable skills | Palette + slash; Skills dialog |
| Sign in / out | `/login` `/logout` | Settings (already) |
| Commands / Help | `/docs` `/tutorial` | Help menu; this plan’s user-facing guide later |

**Not in v2** (TUI- or product-specific; do not pretend): `/dashboard` multi-session roster, `/vim-mode`, `/theme` (IDE already themes), `/imagine*`, `/loop`, `/workflow*`, `/hooks` `/plugins` `/marketplace` `/mcps`, `/fork`, `/btw` (aside panel — related to steer, later), `/dream` `/memory` unless we add memory. They stay off the catalog so the menu does not fill with dead items.

**Skills.** Any discovered skill with `user-invocable: true` (frontmatter; default true if omitted) is a catalog row **Run “commit”** / `/commit`. Built-in names win the bare slash; the skill is still listed with a **skill** badge (Build’s collision rule). Pinning a skill in Settings is separate from *invoking* it once.

**IDE keys.** `Ctrl+P` in the assistant must not steal the IDE’s command palette if that is bound globally — use the form’s `KeyPreview` only while the assistant is focused, and also register IDE commands (`ProjectAssistant.Palette`, `ProjectAssistant.NewConversation`, …) so they appear in Lazarus’s own key-mapping dialog. That is the IDE-native discovery path Build does not have.

**First session.** Help → **Commands** opens the palette with an empty filter so the full list is visible. Do not rely on a tutorial overlay.

---

## 7. Harness (system prompt, skills, rules)

v0.2 prompt is a short mode paragraph plus an optional skill pasted in full. Build’s `xai-grok-agent` assembles a **template** with named sections, then a **skill catalog**, then **project instructions**.

### 7.1 Prompt skeleton (adapt, do not paste grok-build `prompt.md` as ours)

`AssistantHarness` renders a Michell-owned template:

```
You are the Lazarus Project Assistant (Ask | Plan | Build).
<work_policy>     finish the request; don't claim unverified work; stay in mode
<tool_calling>    prefer named tools; no bash-echo to the user
<ide_fusion>      buffers, Messages, .pas+.lfm pairing, no probe units
<communication>   lead with the answer; current-turn user didn't see tools
<formatting>      markdown for the answer channel only
<mode_overlay>    the three-mode hard rules (from today's ModeSystemPromptBase)
<skills>          catalog (name + description + when to use); not the full body
<project_rules>   AGENTS.md / Documents conventions in scope
<user_info>       OS, project root, active file, FPC/Lazarus version
```

`free-pascal-engineer` is **always attached in Plan and Build** (full body, existing 120k cap). Ask gets the catalog only unless the user pinned a skill.

### 7.2 Skill discovery (closer to Build)

Today: `~/.grok/skills/<name>/SKILL.md` only, one combo in Settings.

v2 scan order (stop at first name win):

1. `{ProjectRoot}/.grok/skills/`
2. `{ProjectRoot}/.assistant/skills/`
3. `~/.grok/skills/`
4. Bundled (optional later)

Catalog in the system prompt: `name`, `description`, `when-to-use`. A `read_skill` tool loads the body on demand so we do not dump every skill into every turn.

User-facing: Settings still has a **pin**; pinned skill is always injected. Default pin for this product: `free-pascal-engineer`. Skills with `user-invocable: true` also appear in the command catalog (§6.5) so they are not Settings-only.

### 7.3 Project rules

Read `{ProjectRoot}/AGENTS.md` if present (and keep using the plan file as work-package source of truth). Do not invent a second style guide in the prompt when the skill already is that guide.

### 7.4 Todos

Keep **plan Markdown as durable work-package state** (v0.2 decision — good).

Add an **ephemeral** in-turn todo list (Build `todo_write`) for the *current* Build turn only: “read Foo, patch Bar, compile.” It dies with the turn unless we later persist it. It does not replace `Status:` lines.

### 7.5 Tool descriptions

Rewrite tool JSON descriptions to match how Build tools teach the model (when to use, paging, exact-match `replace_in_file`, quiet compile default). The v0.2 Code prompt already has good LFM rules; those move into `<ide_fusion>` + tool schemas so they survive mode overlay changes.

### 7.6 New tools (small set)

| Tool | Role |
|------|------|
| `read_skill` | Load a catalogued SKILL.md |
| `todo_write` | Ephemeral turn todos |
| `spawn_subagent` | Depth-1 child (see §8) |
| `grep` (or upgrade `search_in_project`) | Ripgrep-quality, line numbers |

No general shell in v2. Compile stays `run_compile`. Sandbox stays project root.

---

## 8. Subagents (product, not a default loop)

### 8.1 Built-in kinds

| Kind | Capability | Use |
|------|------------|-----|
| `explore` | read / grep / project info | Parallel codebase questions |
| `plan` | read + markdown | Draft a plan section without source writes |
| `general-purpose` | parent’s current mode tools | Isolated chunk of implementation |
| `pascal-naming` | read-only | Review lens |
| `pascal-structure` | read-only | Review lens |
| `pascal-review` | read-only + last compile messages | Review lens |

Personas are instruction overlays (Michell engineer, concise reviewer), not extra kinds.

### 8.2 Runtime

- `spawn_subagent` on the parent only (`AssistantSubagents` rejects nested spawn).
- Each child: own actor thread, own sampler, own encrypted reasoning, own trace (viewable from a row in the parent).
- Parent sees a compact row: `Subagent running: naming review — Thinking` → completed summary.
- Isolation: shared project (default). Worktrees are out of scope for v2 (Git package can grow that later).
- Budget: max 3 live children; Review action is the usual fan-out.

### 8.3 When the parent should spawn

**Yes:** user says “review this,” Review menu, independent file reads, a long search that would pollute the parent context.

**No:** every `replace_in_file`, syntax, or “check naming while I implement.” The skill plus compile already covers that in one pass.

---

## 9. Storage

Keep `.assistant/`:

```
{ProjectRoot}/.assistant/
  config.json              # mode, show_thinking, plan_file, pinned skill
  conversation.jsonl       # existing human turns
  history.index.json
  events/<turn-id>.jsonl   # NEW: replayable trace
  reasoning/<turn-id>.bin  # NEW: encrypted blobs (not for display, gitignored)
```

`.assistant/` stays gitignored. Encrypted reasoning must never be committed or shown.

---

## 10. Relationship to v0.2

| Keep | Replace | Defer |
|------|---------|--------|
| OAuth, settings, model list | Chat Completions as primary | ACP host for `grok` binary |
| Mode **gates** (not the RadioGroup chrome) | Two-string thinking + one Markdown view | Worktree isolation |
| Plan `Status:` scan + tiles | Current-turn-only working surface | MCP / plugins |
| IDE buffer edits, `ensure_form_component` | `AssistantService` god-object stream loop | Mermaid |
| History JSONL + index | Prompt = mode paragraph + one pasted skill | SQLite |
| Path sandbox, no shell | Bottom bar kitchen sink | |
| LazRepositoryTools | | |

v0.2 `ProjectPlan.md` remains the implementation log for what already shipped.

---

## 11. Work packages

Each section is a Code/Build tile (`Status:` line immediately under the heading).

## 1. Protocol and sampler (Responses)

Status: not started

`AssistantProtocol` + `AssistantSampler`: Responses stream, encrypted include, Chat Completions fallback. Unit tests with fixture SSE (reasoning deltas, tool calls, completed). No UI yet.

## 2. Event log and session actor

Status: not started

`AssistantEvents` + `AssistantSession` thread. Turn loop without wiping thinking. Tool dispatch via existing `ExecuteAssistantToolForMode`. Coalesced queue to main. Cancel/abort HTTP. **Steering buffer:** accept mid-turn comments from the UI, drain at safe gaps (after HTTP round / after in-flight tool, never mid-compile), inject synthetic user envelope, round-trip encrypted reasoning, do not abort the turn. Stranded steers become the next prompt.

## 3. Trace UI: thinking + tools + answer

Status: not started

`AssistantTrace` + frames. Pre-create thinking, append deltas, collapse on content, tool cards, answer markdown. Wire into `ProjectAssistantForm` as the centre. Toggle thinking keeps working.

## 4. Shell: one surface, mode chips

Status: not started

Remove mode-swapped help panel. Work tiles + history always visible. Short bottom bar. Promotion banners. Plan “Build this” bar. Rename Code → Build in captions. Prompt stays editable during a turn; Send caption **Steer**; `Ctrl+Enter` injects; pending steer block in the trace. **Command catalog:** window menus, `Ctrl+P` palette, `/` popup, footer clicks — one `TActionList`, no `/`-only verbs.

## 5. Harness

Status: not started

Templated system prompt, skill catalog + `read_skill`, always-on `free-pascal-engineer` in Plan/Build, AGENTS.md, richer tool descriptions, ephemeral `todo_write`.

## 6. Subagents and Review lenses

Status: not started

`spawn_subagent`, depth 1, explore + three Pascal lenses. Review menu fans out over changed files. Parent rows in the trace.

## 7. History replay and polish

Status: not started

Rebuild a turn from `events/*.jsonl`. DPI, theming, large-trace virtualization if needed. Docs / README catch-up. Drop Chat Completions-only thinking path from the default settings once Responses is proven.

---

## 12. Alternatives considered

| Option | Why not (for v2) |
|--------|------------------|
| **Embed `grok agent stdio` (ACP)** | Fastest Build-identical thinking, but the product becomes a client of a Rust binary, IDE tools (`ensure_form_component`, Messages) sit behind a protocol, and packaging/signing gets worse. Revisit as an *optional* backend once the native trace UI exists (same blocks can paint ACP `AgentThoughtChunk` / `ToolCall`). |
| **Stay on Chat Completions, only pretty-print `reasoning_content`** | Still empty/thin on current API; still wipes per round; still no tool cards. Does not meet the quality bar. |
| **Always-on naming+syntax+structure subagents** | Syntax is the compiler. Always-on LLMs are slow, costly, and argue. Review-on-demand is the Build pattern. |
| **Port grok-build UI widgets literally** | Ratatui ≠ LCL. Copy the *block model and states*, implement as frames. |
| **Three separate conversations per mode** | Makes Plan → Build a copy-paste problem. One session, overlay permissions. |
| **Steer by aborting the HTTP stream every time** | Wastes the round the user was reading; kills compile. Drain at the next gap; **Stop and send** is the interruptive verb. |
| **Queue-until-turn-ends as the only mid-turn send** | That is Build’s default `follow_up_behavior=queue`. Too late for “I just saw the thought and need to correct it.” Steer is v2’s default; queue-until-done is a setting. |
| **Slash menu as the only way to find compact / rewind / skills** | That is Build’s hiding problem. Slash stays as a shortcut; menus, palette, and footer are the catalog. |
| **Put every command on the bottom bar** | v0.2 clunk. Short bar for current-state verbs; the rest live in Commands… |

---

## 13. Key decisions

1. **Native Pascal harness**, structure from grok-build, not a Rust wrap.
2. **Responses API + encrypted round-trip** is the thinking channel; Chat Completions is fallback.
3. **Typed event log + typed trace blocks** replace two accumulated strings and one Markdown document.
4. **Session actor thread** owns HTTP and the tool loop; LCL only paints coalesced events.
5. **Modes stay as hard tool gates**, but become chips on **one** transcript; Code caption becomes Build.
6. **Plan file remains durable todos**; in-turn `todo_write` is ephemeral.
7. **Subagents are depth-1, on-demand.** Review lenses yes; per-edit syntax/naming committee no. Compiler is syntax.
8. **`free-pascal-engineer` always on** in Plan/Build; other skills catalogued.
9. **No general shell** in v2.
10. **ACP optional later**, same trace UI.
11. **Steer is the default mid-turn send.** Merge at the next actor-loop gap; do not cancel in-flight tools. Stop-and-send is a separate verb. Prompt stays live (`ReadOnly` is a v0.2 bug for this product).
12. **One command catalog, several surfaces.** Every user-facing verb has a caption and a non-slash home (menu, palette, footer, or context menu). `/` is muscle memory, not discovery.

---

## 14. Risks

| Risk | Mitigation |
|------|------------|
| Responses API differs from fixtures / needs extra headers | Sampler isolated; fixtures; keep Completions fallback; log raw SSE in debug |
| Encrypted content size blows context | Store last N reasoning items; drop on compact; never put blobs in history JSONL bodies |
| LCL scroll of many frames is slow | Virtualize later; start with typical turn sizes; freeze finished thinking as static height |
| Mode rename confuses existing users | Chip helper text; config value can stay `code` internally |
| Prompt size with full skill | Existing 120k cap; catalog + `read_skill` for extras |
| Review fan-out cost | Default off; cap 3; changed files only |
| `ProjectAssistantForm` rewrite risk | Shell-first: new trace in the centre, keep send/stop/history until chips land |
| Steer during a long compile feels “stuck” | Footer “Steering at next tool gap…”; never kill `run_compile`; Stop remains the abort |
| `Ctrl+P` fights the IDE command palette | Only while the assistant is focused; also register IDE commands for Lazarus keymap |
| Several steers in one gap | Concatenate in order in one drain so we do not spawn extra HTTP rounds |

---

## 15. Success metrics

- During a Build turn the user can **watch thinking grow, see each tool by name/path, and expand thought after**.
- Mid-turn, they can type a correction and **Steer**; the next model round incorporates it without throwing away the current compile or thought so far.
- A new user can find Compact, Rewind, Skills, Review, and Model **without knowing any `/` name** — via Commands…, the window menu, or the footer.
- Switching Ask → Plan → Build does not wipe the transcript or start a silent new chat.
- A Plan write offers **Build this** without hunting tabs.
- Review of a change can run naming + structure lenses in parallel; syntax still comes from compile.
- Thinking across tool rounds is still on screen (not reset to empty).
- `ProjectAssistantForm` is a shell; new units stay near the 1000-line preference.

---

## 16. Next immediate step

Package **1. Protocol and sampler** — fixture-driven Responses parser and encrypted round-trip in `AssistantSampler`, with Completions fallback, no UI change. Everything else hangs off that channel.

---

**This plan is living.** Update `Status:` lines when a package lands. v0.2 `ProjectPlan.md` remains the historical log of the shipped assistant.
)
