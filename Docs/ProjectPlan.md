# Project Plan: Lazarus Repository Tools + Project Assistant

**Michell Computing Style Lazarus Package Suite**  
**Version:** 0.2 (Planning revision)  
**Date:** 2026-07-26  
**Author:** FreePascal Engineer  
**Target Platforms:** Linux (GTK2/GTK3/Qt5/Qt6), Windows (Win32/Win64), macOS (Cocoa)  
**Lazarus / FPC Baseline:** Lazarus 3.x / 4.x + FPC 3.2.2+ (ObjFPC mode)

---

## 1. Vision & Goals

Create two tightly integrated, first-class Lazarus IDE packages that feel native:

1. **LazRepositoryTools** — A modern Git life-cycle UI with a commit history graph, live monitoring, and push/pull/fetch.
2. **LazAssistantTools** — A **Project Assistant** window that runs in explicit **modes** (Chat / Plan / Code). Each mode has a clear purpose and **implicit tool permissions**, so the model cannot silently escalate from “answer a question” to “rewrite the project.”

**Core principles**
- Seamless IDE integration (dockable windows, IDE menus/actions, project-aware state).
- Cross-platform from day one.
- Michell Computing conventions strictly applied.
- Loose coupling via interfaces / event bus so either package can install alone.
- High performance: background threads for Git and LLM work; never block the IDE UI.
- **Mode-gated agency**: permissions come from the active mode, not ad-hoc tool lists buried in prompts alone.
- **Project-local memory**: assistant state lives under a hidden project `.assistant/` folder (not only global IDE config).
- Extensible: new modes or tools can be added without redesigning the shell.

---

## 2. High-Level Architecture

```
┌──────────────────────────────────────────────────────────────────────────┐
│                        Lazarus IDE (LCL + IDEIntf)                       │
├───────────────────────────────┬──────────────────────────────────────────┤
│   LazRepositoryTools.lpk      │         LazAssistantTools.lpk            │
│  ┌─────────────────────────┐  │  ┌────────────────────────────────────┐  │
│  │ GitService              │  │  │ AssistantService (SSE + tools)     │  │
│  │  - CLI / future libgit2 │◄─┼──┤  - OAuth / OpenAI-compatible       │  │
│  │  - watchers             │  │  │  - mode-scoped tool registry       │  │
│  └──────────┬──────────────┘  │  └──────────┬─────────────────────────┘  │
│             │                 │             │                            │
│  ┌──────────▼──────────────┐  │  ┌──────────▼─────────────────────────┐  │
│  │ Manage Repository       │  │  │ Project Assistant (main form)      │  │
│  │  tabs: History | Files… │  │  │  tabs: Chat | Plan | Code          │  │
│  │  actions bottom/edge    │  │  │  current turn view + bottom bar    │  │
│  └─────────────────────────┘  │  │  history browser (JSONL + index)   │  │
│                               │  │  plan TODO panel (Code mode)       │  │
│                               │  └────────────────────────────────────┘  │
│                               │  Markdown live windows (Plan artifacts)  │
└───────────────────────────────┴──────────────────────────────────────────┘
                    │
                    ▼
         Project root/
           .assistant/          ← project-private assistant state
             history.jsonl      ← append-only conversation log
             history.index.json ← compact index for fast list/open
             config.json        ← optional per-project options
             plans/             ← optional mirror/index of active plan
           Documents/           ← default Plan-mode MD location (user-visible)
```

**Shared foundation:** `LazWorkflowCommon.lpk`  
Event bus, logging, status footer, shared messaging.

---

## 3. Package Breakdown

### 3.1 LazRepositoryTools (Primary Git UI)

*(Unchanged in spirit — see implementation log for current Manage Repository form.)*

**Key UI:** dockable **Manage Repository** with a top `TPageControl` (History, Files, …) and action affordances that do not steal the tab strip’s primacy.

### 3.2 LazAssistantTools — Project Assistant

#### 3.2.1 Main window rename and shell

| Item | Target |
|------|--------|
| Form caption / product name | **Project Assistant** (replace “Project Chat”) |
| Primary chrome | Top **tabs**: **Chat** · **Plan** · **Code** (same pattern as Manage Repository) |
| Actions | **Bottom** action bar (Send, Stop, Settings, mode-specific actions) — not a top toolbar fighting the tabs |
| Status | Existing three-part footer (model, context, status / elapsed) |
| Working surface | **Current turn only**: prompt · thinking (optional) · response |
| History | Separate **browser / list** backed by JSONL + index — not an infinite scroll transcript |

**Rationale:** Long Markdown transcripts are hard to revisit. The working surface should stay focused; retrieval and analytics live in a structured store.

#### 3.2.2 Modes = purpose + implicit permissions

Modes are not mere labels. Switching mode changes:

1. System prompt flavour (role and success criteria).
2. **Tool allow-list** (hard gate in `ExecuteAssistantTool` / request JSON).
3. Secondary panels (e.g. Code mode TODO list).
4. Default artefact locations.

| Mode | Purpose | Implicit tools / capabilities | Explicit non-goals |
|------|---------|-------------------------------|--------------------|
| **Chat** | Q&A, explanation, design discussion | Read-only project tools: `read_file`, `list_directory`, `get_project_info`; open Markdown **read-only** or open existing MD without write tools | No source writes; no plan document mutation; no compile |
| **Plan** | Author and maintain project plans / design notes | Everything in Chat **plus** create / open / update Markdown under the project (default `Documents/`), open live Markdown windows, list plan docs | No arbitrary source edits; no compile (optional later: “link to Code”) |
| **Code** | Implement, edit, verify | Everything in Plan **plus** live source edits via IDE buffers, `run_compile` / `run_build`, read Messages / compiler output, structured “next TODO” workflow | No unattended mass rewrite without mode being Code; still respect path sandbox |

**Hard rule:** the service builds `tools` JSON from the **active mode**. The model cannot call a tool that the mode does not allow, even if it invents the name.

##### Suggested refinements (mode permissions)

- **Promotion is explicit:** user switches tab to Code (or confirms “Enter Code mode for this task”). Chat never silently gains write tools mid-stream.
- **In-flight mode lock:** while a stream / tool round is active, mode tab changes are disabled or require cancel first (avoids mid-round permission flips).
- **Per-mode “allow writes” is redundant** if the tab *is* the permission — keep one concept. Optional future: Code mode sub-toggle “Apply edits without confirmation” vs “Stage edits for Apply”.
- **Plan writes are sandboxed** to project root, preferably under `Documents/` by default, with escape hatch for other project-relative paths (e.g. `Docs/ProjectPlan.md`).
- **Code writes** use IDE-mediated buffer edits (undoable), not silent disk overwrite of open files.

#### 3.2.3 Chat mode (current product, reshaped)

- Current streaming behaviour (content + `reasoning_content` / thinking).
- IDE context attach (active editor / selection) remains useful.
- **Thinking** region is **easily toggled** (toolbar button, checkbox, or split header) — default can be “show while streaming, collapse when finished” or user preference in `.assistant/config.json`.
- Transcript scrollback of dozens of turns is **removed** from the main surface; completed turns are appended to `history.jsonl` (and the index) and drop off the working view (with optional “keep last N turns on screen” = 1 by default).

#### 3.2.4 Plan mode

- Tools: create / open / update Markdown; default directory **`{ProjectRoot}/Documents/`** (create if missing when first Plan write occurs).
- Existing **live Markdown windows** remain the viewer/editor (watch + debounce reload).
- Plan mode can maintain a **canonical plan file** (user-chosen or default e.g. `Documents/Plan.md` or continue using `Docs/ProjectPlan.md` when already present).
- Structured **TODO extraction** (see §3.2.6) so Code mode has a task list without re-parsing free prose every time.

#### 3.2.5 Code mode

- Tools: Chat + Plan capabilities as needed for context, **plus**:
  - `replace_in_file` / buffer-aware apply (exact match; path sandbox).
  - optional `replace_selection` / insert at cursor for the active editor.
  - `run_compile` / `run_build` via `LazarusIDE.DoBuildProject` (or existing Review Compile/Build paths).
  - `get_compiler_messages` / feed last build output into the next turn.
- **Plan TODO panel** visible when a plan is associated with the project (see below).
- Primary loop: *select or “next” TODO → implement → compile → fix → mark TODO done → update plan MD*.

#### 3.2.6 Plan ↔ TODO linkage (flexible, formal enough)

**Goal:** Code mode can move through work formally (“next part of the plan”) without locking the user into a rigid Gantt format.

**Recommended model (refinement):**

1. **Source of truth for narrative:** the plan Markdown file(s) the user cares about.
2. **Source of truth for task state:** a small structured store under `.assistant/` (e.g. `todos.json`), **derived from** and **written back to** the plan MD.
3. **Supported MD conventions** (documented, not exclusive):
   - GitHub-style checkboxes: `- [ ]` / `- [x]`
   - Optional stable IDs: `- [ ] <!-- id:auth-form --> Implement auth form`
4. **Sync rules:**
   - Opening Plan/Code mode or detecting plan file change → re-parse checkboxes → upsert TODO rows (preserve `status`, `updated_at` when IDs match).
   - Completing a TODO in Code mode → update MD checkbox + DB row + history event.
   - User/LLM edits plan MD → re-parse; new items appear; removed items are archived (not hard-deleted immediately) to avoid losing stats.
5. **Code mode UI:** compact list (status, title, plan section, “Current”, “Mark done”, “Skip”, “Open in plan”). “Next” = first open item in document order unless user pins another.

**Roadblock if skipped:** free-form “update the plan” without checkbox conventions makes TODO sync unreliable. Mitigation: Plan-mode system prompt + a “normalise plan tasks” tool that rewrites only the task list section.

#### 3.2.7 Project-local storage: `.assistant/`

Hidden folder at **project root** (alongside sources), not in the global IDE config tree.

```
{ProjectRoot}/.assistant/
  history.jsonl       # append-only full turns (one JSON object per line)
  history.index.json  # compact index for fast list/filter/search (rebuilt if missing)
  todos.json          # plan task state (optional; derived from plan MD)
  config.json         # per-project options (mode defaults, plan path, thinking visible, …)
  README.txt          # managed by LazAssistantTools; safe to exclude from VCS if desired
```

**VCS policy (refinement):** default recommend **ignoring** `.assistant/` in project `.gitignore` templates (local conversation may contain secrets / noise). Optional “share plan todos” later via committing `Documents/` only. Document both choices.

##### History format: JSONL (chosen — zero native dependency)

**Decision (2026-07-26):** use **JSONL + a sidecar index**, not SQLite. Avoids libsqlite3 packaging across Linux/Windows/macOS IDE installs while still supporting fast retrieval for large histories.

**Why this is fast enough**

| Operation | Strategy | Cost |
|-----------|----------|------|
| Append completed turn | Write one JSON line + update index entry | O(1) |
| Open Project Assistant | Load **index only** into memory (not full bodies) | O(N) on small index rows; N = turn count |
| History list / filter by mode / date | Scan in-memory index | O(N), fine for 10⁴–10⁵ turns |
| Text prompt/response text | Prefer index **preview** fields; optional full-body scan only when needed | Preview search O(N); deep search streams JSONL once |
| Open one turn | Use index `file_offset` → seek + read one line | O(1) disk |
| Stats (counts, duration averages by mode) | Aggregate from index | O(N) in memory |

Typical project history is hundreds to a few thousand turns. Even 50k turns with ~200-byte index rows is ~10 MB of index — trivial. Bodies (thinking + long answers) stay on disk until a row is opened.

**Do not** load entire `history.jsonl` into a `TStringList` on every paint. That is the slow path; the index exists to prevent it.

##### One JSONL record (fields)

Same logical fields as the earlier SQL sketch, one object per line:

```json
{"id":"01J…","mode":"code","prompt":"…","thinking":"…","response":"…",
 "created_at":"2026-07-26T12:04:00Z","started_at":"…","finished_at":"…",
 "duration_ms":12345,"model":"grok-4.5","skill":"free-pascal-engineer",
 "token_estimate":800,"error":"","plan_file":"Documents/Plan.md","todo_id":"auth-form"}
```

- UTF-8, one record per line, **append-only** for the common case.
- Escape newlines inside strings as JSON `\n` (standard JSON).
- `id`: ULID or UUID string (stable for index and “continue from here”).

##### Sidecar `history.index.json`

Array (or NDJSON) of **lightweight** rows only — no full thinking/response:

| Field | Notes |
|-------|--------|
| `id` | Matches JSONL record |
| `mode` | chat / plan / code |
| `created_at` | For sort/filter |
| `duration_ms` | Stats |
| `model` / `skill` | Optional filters |
| `prompt_preview` | First ~120–200 chars |
| `response_preview` | First ~120–200 chars |
| `has_thinking` | Boolean |
| `error` | Short or empty |
| `plan_file` / `todo_id` | Optional linkage |
| `file_offset` | Byte offset into `history.jsonl` for seek |
| `byte_length` | Optional; line length for validation |

**Rebuild:** if index missing or `history.jsonl` mtime/size disagrees with index header, stream JSONL once and rewrite index (background or on open with progress for huge files).

**Concurrency:** single IDE writer assumed; append with flush; rewrite index atomically (write temp + rename).

##### Search & “large chats”

- **Default search:** case-insensitive match on `prompt_preview` + `response_preview` + mode — instant from memory.
- **Deep search:** stream `history.jsonl` for substring in full prompt/thinking/response (cancellable); acceptable occasionally, not on every keystroke.
- **Optional later:** maintain a simple inverted token map in `history.tokens.json` if deep search becomes common — still no SQLite.
- **Retention:** settings to drop thinking bodies after N days, or compact old turns to “prompt + response only,” to keep files lean.

**UI for history:**

- Side panel: filter by mode, search, date range (from index).
- Click row → seek-load full turn into current-turn view; or “Continue from here.”
- Export selected turns to Markdown.

**What this replaces:** session `.lazgrokchat-session` / giant in-memory transcript as the primary UX. Migration: one-shot import of old session files if present.

##### SQLite (deferred, not required)

SQLite remains a **possible future** backend if analytics/query complexity outgrows JSONL. It is **not** required for v1. No libsqlite3 dependency for Project Assistant history.

#### 3.2.8 UI layout sketch (Project Assistant)

```
┌─ Project Assistant ─────────────────────────────────────────┐
│ [ Chat ] [ Plan ] [ Code ]                    (TPageControl) │
├─────────────────────────────────────────────────────────────┤
│  Optional: History list (filter)  │  Current turn            │
│  • 12:01 Chat …                   │  User: …                 │
│  • 12:04 Plan …                   │  [▼ Thinking] …          │
│  • 12:10 Code …                   │  Assistant: …            │
│                                   │  (Code: TODO panel)      │
├─────────────────────────────────────────────────────────────┤
│  Input multi-line                                           │
├─────────────────────────────────────────────────────────────┤
│  [Send] [Stop] … mode actions … [Settings]     (bottom bar) │
├─────────────────────────────────────────────────────────────┤
│  Model | Skill | Context %              | Status / elapsed   │
└─────────────────────────────────────────────────────────────┘
```

Code mode adds a **TODO** strip or side panel when a plan is linked.

---

## 4. Suggested Ease-of-Use & Capability Enhancements

### High-Value (aligned with modes)
1. **Mode-appropriate tool cards** in the current turn (read / wrote plan / applied edit / compile result) without flooding history.
2. **AI commit messages** from LazRepositoryTools using Assistant in Chat mode (read-only diff).
3. **Fix Error** remains a Code-mode entry point (pre-fill prompt + jump to Code tab).
4. **Plan-driven Code loop** with Next / Done TODO actions.
5. **History search** (index previews + optional deep JSONL scan) replacing scroll archaeology.
6. **Thinking toggle** + “copy thinking” for debugging model behaviour.
7. **Audit trail** of writes (plan + code) as rows or a separate `actions` table.
8. Keyboard-first: IDE commands “Project Assistant: Chat|Plan|Code”.

### Nice-to-Have
- Mermaid in Markdown windows.
- Multi-model routing per mode (e.g. stronger model for Code).
- Shareable session export (selected history + plan snapshot).
- Stats view: tokens over time, duration percentiles, mode mix.

---

## 5. Technical Implementation Plan

### Status summary (as of 2026-07-26)

| Area | Status |
|------|--------|
| Packages / rename Assistant + Repository | Done |
| Project Chat streaming + thinking + OAuth | Done (to be reshaped into Project Assistant) |
| Read-only tools + multi-round tool calls | Done |
| Markdown live windows | Done (entity/`&` and table fixes in lazmarkdown tree) |
| Mode tabs / bottom bar / JSONL history | **Not started** |
| Plan write tools / Code write tools | **Not started** |
| Plan TODO sync | **Not started** |

### Phase 0 – Foundations — **done**
Monorepo, three packages, event bus, logging, status footer.

### Phase 1 – LazRepositoryTools MVP — **largely done**
Graph, status, fetch/pull/push refresh, Manage Repository form shell.

### Phase 2 – LazAssistantTools MVP — **largely done** (pre-mode redesign)
Streaming chat, footer, sessions, Markdown windows, settings/OAuth, read tools.

### Phase 2.5 – Project Assistant shell & history (next major UX)
1. Rename UI to **Project Assistant**.
2. Top **Chat | Plan | Code** tabs; **bottom** action bar (mirror Manage Repository interaction model).
3. Current-turn-only working surface; **thinking toggle**.
4. Create `.assistant/` on first use; **`history.jsonl` + `history.index.json`** with schema above.
5. History browser (list + search + open turn).
6. Persist mode + options in `.assistant/config.json`.
7. Mode-scoped tool allow-lists (Chat = read-only tools only).

### Phase 3 – Plan mode
1. Default `Documents/` directory; create on demand.
2. Tools: `write_markdown`, `update_markdown` / `replace_in_file` limited to MD (+ path policy).
3. Open live Markdown window after create/update.
4. Canonical plan path in config; checkbox parse → `plan_todos`.
5. Plan-mode system prompt: keep tasks checkbox-shaped for Code sync.

### Phase 4 – Code mode
1. IDE-mediated source edit tools (sandbox, exact match, undoable).
2. Compile/build tools + message capture (wire existing Review Compile/Build).
3. TODO panel + Next/Done/Skip; write-back to plan MD.
4. Optional edit confirmation policy for first release.
5. End-to-end loop: plan task → edit → build → fix → mark done.

### Phase 5 – Deep integration & polish
- Git ↔ Assistant events; AI commit message; Fix Error → Code mode.
- Theming, high-DPI, performance (large history.jsonl + index).
- Docs, example workflow, package release.

### Phase 6 – Advanced (ongoing)
- Mermaid, multi-model routing, agent approval gates, worktrees/submodules.

---

## 6. Key Technical Decisions & Risks

| Decision | Choice | Rationale / Mitigation |
|----------|--------|------------------------|
| Assistant UX unit | Modes with hard tool gates | Prevents permission escalation |
| Main form name | Project Assistant | Matches product role |
| History store | JSONL + sidecar index in `.assistant/` | Zero native dep; fast list/open via offsets |
| Working surface | Current turn only | Reduces scroll fatigue |
| Plan artefacts | `Documents/` default + live MD windows | Visible to user; assistant state stays hidden |
| Plan tasks | Checkbox MD ↔ structured todos | Flexible + formal enough |
| Code edits | IDE buffers, not silent overwrite | Undo + no “file changed on disk” fights |
| Git backend | CLI now; libgit2 later | Already working |
| Markdown preview | Lazarus `TMarkDownControl` | Upstream bugs (`&`, tables) fixed in local Lazarus tree |
| Secrets | OAuth tokens in IDE config; not in `.assistant/` by default | Avoid committing credentials with project |

**Risks & roadblocks**

1. **JSONL index integrity** — Crash mid-append can leave a partial last line. Mitigate: write record then flush; on open, ignore corrupt last line and rebuild index; atomic index rewrite (temp + rename).
2. **Mode confusion** — Users may stay in Chat and expect edits. Mitigate with clear empty-state copy (“Switch to Code to edit sources”) and Fix Error auto-switching to Code.
3. **Plan/TODO drift** — LLM rewrites plan structure and breaks checkboxes. Mitigate with ID comments, archive-on-delete, and a “reconcile todos” command.
4. **Large thinking blobs** — JSONL size growth. Mitigate with optional “store thinking” preference, retention limits, or compact-old-turns.
5. **Context vs history** — Current-turn UI must still build **API context** from selected prior turns / summary. Roadblock if we only send the last user message: model forgets the plan. Mitigate with explicit “include last K turns” + “pin plan summary” in Code/Plan modes.
6. **Concurrent editors** — Plan MD open in Markdown window and updated by tools; need debounced reload (already partially present).
7. **Security** — Code mode is powerful; path sandbox + no shell tool in v1.
8. **lazmarkdown AVs** — Bare `&` and table `ChildCount` bugs fixed in local Lazarus sources; IDE must reinstall `lazmarkdown` or AVs return on plan docs.
9. **Form migration cost** — Toolbar-to-tabs/bottom-bar is a non-trivial LFM rewrite; do shell first with Chat-only content, then Plan/Code panels.
10. **Analytics scope creep** — Ship index fields with timestamps/duration first; defer charts. Deep SQL-like queries are out of scope until/unless SQLite is revisited.

---

## 7. Development Conventions (Michell Computing Strict)

- All units under `Source/`.
- Standard FPC mode block, PascalCase reserved words, 2-space indent, 150-char line limit.
- Classes for UI & services; no UI from worker threads.
- Full `Result` assignment, `Assigned` checks, `FreeAndNil` in destructors.
- Packages compile on major platforms in Debug + Release.
- Git commits: area prefix + imperative summary + explanatory body.

**New conventions for this feature set**
- Mode permission checks live in **one unit** (e.g. `AssistantModeTools.pas`) — UI does not assemble allow-lists ad hoc.
- All project-local paths resolve via helpers that create `.assistant/` and `Documents/` safely.
- History I/O in a dedicated helper (`AssistantHistory.pas`): append JSONL + update index on the **main thread at turn end** (or a single writer queue); never parse full JSONL on the UI paint path.

---

## 8. Deliverables

1. Packages: LazWorkflowCommon, LazRepositoryTools, LazAssistantTools.
2. **Project Assistant** with Chat / Plan / Code modes and mode-gated tools.
3. `.assistant/history.jsonl` (+ index) history browser + current-turn UI.
4. Plan mode Markdown workflow + Code mode TODO panel.
5. README / user guide: modes, permissions, `.assistant` VCS guidance.
6. Example: plan → code → compile → commit loop.
7. Tests where feasible (history DB, path sandbox, mode allow-list).

---

## 9. Success Metrics

- Native feel inside Lazarus; Manage Repository and Project Assistant share interaction patterns (top tabs, calm chrome).
- User can revisit any past turn in seconds via history search (not scroll).
- Chat cannot modify sources; Plan can only touch intended docs; Code can implement with compile feedback.
- Plan TODOs stay understandable at a glance in Code mode after plan edits.
- Full loop without leaving the IDE: plan → implement → build → fix → commit (with Repository tools).

---

## 10. Next Immediate Steps

1. **Agree refinements** in this document (especially: history panel placement, whether Code edits auto-apply, VCS ignore for `.assistant/`).
2. Implement **Phase 2.5 shell**: rename, tabs, bottom bar, current-turn view, thinking toggle.
3. Implement **history.jsonl + index** + browser; migrate off primary transcript scrollback.
4. Wire **mode tool allow-lists** (Chat stays read-only).
5. Phase 3 Plan writes → Phase 4 Code edits + TODO panel.

---

## 11. Refinements recommended by engineering (summary)

| Topic | Recommendation |
|-------|------------------|
| Permission model | Tab = mode = hard tool gate; lock mode while busy |
| History store | JSONL append + `history.index.json` with file offsets; no SQLite for v1 |
| History UX | Side list + search on index; seek-load full turn; optional “continue from turn” |
| API context | Do not send only the visible turn — include plan summary / last K turns / pinned TODO |
| Plan default path | `Documents/` for new plans; allow linking existing `Docs/ProjectPlan.md` |
| TODO sync | Checkboxes + optional HTML comment IDs; archive removed tasks |
| Code apply | IDE buffer edits; start with auto-apply in Code mode + undo; add confirm later if needed |
| Thinking | Toggle + still store in DB when present |
| Secrets | Keep OAuth out of `.assistant/`; gitignore `.assistant/` by default |
| Stats | Index fields ready now; charts later |
| SQLite | Deferred only if query needs outgrow JSONL |

---

## 12. Implementation Log

### 2026-07-20 – Phase 0 scaffolding
- Monorepo, three packages, event bus, logging, status footer, stubs.

### 2026-07-21…25 – Repository + Assistant progress
- Manage Repository graph, status, fetch/pull/push refresh, helper renames.
- Assistant OAuth streaming, thinking, Markdown windows, session files.
- Package renames: LazAssistantTools / LazRepositoryTools.
- Read-only tool calling (`read_file` with paging, `list_directory`, `open_markdown`, `get_project_info`); tool-round limits raised.
- lazmarkdown fixes (local Lazarus tree): table `ChildCount` off-by-one; bare `&` entity AV.

### 2026-07-26 – Plan revision 0.2
- Product direction: **Project Assistant** with **Chat / Plan / Code** modes.
- UI: top tabs, bottom actions, current-turn focus, thinking toggle.
- Storage: project `.assistant/` with **JSONL history + sidecar index** (no SQLite dependency for v1).
- Plan mode MD workflow (`Documents/`); Code mode edits + compile + plan TODO panel.
- Explicit phase 2.5–4 sequencing and roadblocks documented.

**Next:** implement Phase 2.5 shell and history store once this plan revision is accepted.

---

**This plan is living.** Mode details and schema may tighten when the first shell lands in the IDE.
