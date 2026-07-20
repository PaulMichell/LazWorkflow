# Project Plan: Lazarus Git Manager + Grok Chat Add-ins

**Michell Computing Style Lazarus Package Suite**  
**Version:** 0.1 (Planning)  
**Date:** 2026-07-20  
**Author:** FreePascal Engineer (Grok)  
**Target Platforms:** Linux (GTK2/GTK3/Qt5/Qt6), Windows (Win32/Win64), macOS (Cocoa)  
**Lazarus / FPC Baseline:** Lazarus 3.x / 4.x + FPC 3.2.2+ (ObjFPC mode)

---

## 1. Vision & Goals

Create two tightly integrated, first-class Lazarus IDE packages that feel native:

1. **LazGitManager** — A modern, high-quality Git life-cycle UI with a VS Code Git Graph-style commit history tree, live monitoring, and seamless push/pull.
2. **LazGrokChat** — A rich UI replacement for the Grok command-line tool, featuring persistent chat history, live Markdown document windows (auto-updating for plans/TODOs), compiler integration, and bidirectional hooks into LazGitManager.

**Core principles**
- Seamless IDE integration (dockable windows, IDE menus/actions, project-aware, options pages).
- Cross-platform from day one (no Windows-only or Linux-only paths).
- Michell Computing conventions strictly applied (unit structure, naming, 2-space indent, PascalCase keywords, etc.).
- Loose coupling via well-defined interfaces / message buses so either package can be used independently.
- High performance: background threads for Git operations and LLM calls; never block the IDE UI.
- Extensible: clear extension points for future models, VCS backends, or document renderers.

---

## 2. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                     Lazarus IDE (LCL + IDEIntf)                 │
├──────────────────────────────┬──────────────────────────────────┤
│      LazGitManager.lpk       │         LazGrokChat.lpk          │
│  ┌────────────────────────┐  │  ┌────────────────────────────┐  │
│  │ GitService (core)      │  │  │ GrokService (core)         │  │
│  │  - libgit2 or CLI      │◄─┼──┤  - xAI / OpenAI-compatible │  │
│  │  - watcher threads     │  │  │  - streaming chat          │  │
│  └──────────┬─────────────┘  │  └──────────┬─────────────────┘  │
│             │                │             │                    │
│  ┌──────────▼─────────────┐  │  ┌──────────▼─────────────────┐  │
│  │ UI Layer               │  │  │ UI Layer                   │  │
│  │  - Commit Graph        │  │  │  - Chat History + Footer   │  │
│  │  - Status / Diff       │  │  │  - Markdown Preview Windows│  │
│  │  - Menu / Toolbar      │  │  │  - Tool / Function Call UI │  │
│  └────────────────────────┘  │  └────────────────────────────┘  │
│             ▲                │             ▲                    │
└─────────────┼────────────────┴─────────────┼────────────────────┘
              │                              │
              └────────── Shared Bus ────────┘
                 (ILazGitEvents / ILazGrokEvents
                  via IDEIntf or simple observer)
```

**Shared foundation package (recommended):** `LazWorkflowCommon.lpk`  
Contains:
- Event bus / observer interfaces
- Common UI helpers (status footer frame, Markdown renderer wrapper)
- Cross-package messaging (e.g. “Git state changed”, “Compiler finished”, “Markdown document updated”)
- Logging façade

---

## 3. Package Breakdown

### 3.1 LazGitManager (Primary Git UI)

**Responsibilities**
- Detect project Git root (via IDE project or manual open).
- Full Git life-cycle menu/actions (status, add, commit, push, pull, fetch, branch, checkout, merge, rebase, stash, tag, cherry-pick, reset, clean…).
- High-quality interactive commit history tree (inspired by VS Code Git Graph / GitLens).
- Live repository monitoring (file system watcher + optional periodic remote poll).
- Diff viewer, blame, stage/unstage hunks (stretch goal).
- Remote management (add/remove remotes, set upstream).
- Conflict resolution helper (basic).

**Key UI Windows (all dockable via IDE window system)**
1. **Git Graph Window** — main visual history (branches as coloured lanes, commits as nodes, tags/heads annotated). Supports:
   - Zoom / pan
   - Filter by branch / author / date / message
   - Right-click context menu (checkout, create branch, cherry-pick, revert, soft/hard reset, copy SHA, etc.)
   - Double-click → show commit details + diff
   - Live refresh on local/remote changes
2. **Git Status / Working Tree** — classic staged/unstaged lists + diff pane.
3. **Git Log / Simple History** (fallback or secondary).
4. **Remotes & Branches** side panel or notebook page.

**Technology Choices**
- **Preferred backend:** libgit2 via existing Free Pascal bindings (`libgit2-delphi` / community forks) for speed and no external process dependency. Fall back to `git` CLI via `TProcess` / `RunCommand` when libgit2 is unavailable or for complex operations (interactive rebase, etc.).
- File system monitoring: `TFileSystemWatcher` (or platform equivalents + inotify/FSEvents/ReadDirectoryChanges).
- Periodic remote check: configurable timer (default 5–15 min) that does lightweight `git ls-remote` or libgit2 equivalent; only full fetch on user request or when new commits detected.
- Graph rendering: custom-drawn `TPaintBox` / `TScrollBox` with virtualised drawing, or leverage existing graph components if mature. Prefer pure LCL for zero external deps.

**Menu Integration**
- Main menu: **Git** (or under **Project → Git**).
- Context menu on Project Inspector / Source Editor.
- Toolbar buttons (optional, user-configurable).
- Keyboard shortcuts (configurable via IDE).

### 3.2 LazGrokChat (Grok / LLM UI)

**Responsibilities**
- Full replacement UI for the Grok CLI (or any OpenAI-compatible / xAI API endpoint).
- Persistent multi-conversation chat history (SQLite or JSON + markdown files).
- Rich chat view with streaming responses, tool-call visualisation, code blocks with “Insert into editor” / “Apply patch”.
- Status footer bar: context window usage (tokens / %), current model, rate-limit / usage stats, connection status, last error.
- **Live Markdown Document Windows**:
  - Open any `.md` file (or create new) as a dockable / floating window.
  - Live preview (using a Markdown → HTML renderer or native LCL rich text if feasible).
  - File-system watcher: when the LLM (or user) edits the file on disk, the window auto-refreshes.
  - Perfect for “plan.md”, “todo.md”, “progress.md”, architecture diagrams (Mermaid support stretch goal).
- **Compiler Integration**:
  - “Build Project” / “Compile Current Unit” buttons that invoke the Lazarus/FPC compiler via IDEIntf (`TLazCompilerOptions`, `LazarusIDE.DoBuildProject`, etc.).
  - Capture compiler output → feed back into chat context or a dedicated “Build Results” pane.
  - On successful build, automatically notify LazGitManager (e.g. “suggest commit” or refresh status).
- Tool / Function calling support so the model can:
  - Read/write project files (with user confirmation for writes).
  - Run compiler / tests.
  - Trigger Git operations via LazGitManager API.
  - Update Markdown plan documents.

**Key UI**
- Main Chat Window (dockable): conversation list + current chat + input area + footer.
- Markdown Document Windows (multiple, each with own toolbar: Edit / Preview / Split / Pin / Reveal in Finder).
- Settings page: API keys (secure storage), model selection, temperature, system prompts, context limits, proxy, etc.
- Optional “Agent Mode” sidebar for long-running multi-step tasks.

**Backend**
- Pure Object Pascal HTTP client (fphttpclient or Indy / Synapse) with streaming SSE support.
- Support xAI Grok API primary; also OpenAI-compatible endpoints (Ollama, LM Studio, Claude via Anthropic, etc.) for flexibility.
- Background `TThread` or `TTask` for all network / long operations.
- Token counting approximation (or exact if model provides).

### 3.3 Integration Points (Seamless Feel)

- Shared event bus (interfaces in `LazWorkflowCommon`):
  - `IGitRepositoryChanged`
  - `IGitCommitCreated`
  - `ICompilerFinished`
  - `IMarkdownDocumentChanged`
  - `IGrokToolCallRequested` (Git actions, file ops, etc.)
- LazGrokChat can call `LazGitManager.Commit(...)`, `Push`, etc. with confirmation dialogs.
- After a successful Grok-driven edit + compile cycle, LazGitManager can auto-stage or offer “Commit with AI message”.
- Both packages register IDE options frames under **Environment** or a dedicated **Workflow** node.
- Both appear in **View** menu as dockable windows.
- Project session state saved/restored with Lazarus desktop layout.

---

## 4. Suggested Ease-of-Use & Capability Enhancements

### High-Value Additions
1. **AI-Powered Commit Messages** — LazGrokChat can generate conventional-commit messages from staged diff (one-click from Git Graph or Status window).
2. **Visual Diff + AI Explain** — Select a commit or hunk → “Explain this change” sends to Grok.
3. **Plan-Driven Development Mode** — User drops a `plan.md`; Grok maintains it, marks todos complete, and the Markdown window shows live progress checkboxes.
4. **One-Click “Grok Fix Compiler Error”** — Click an error in the Messages window → auto-open chat with context + error + surrounding code.
5. **Branch Protection / Pre-commit Hooks UI** — Simple GUI for common hooks.
6. **Multi-repo Support** — If a project has submodules or is a monorepo, show a repo switcher.
7. **Keyboard-first Workflow** — Command Palette-style “Git: …” and “Grok: …” actions (leverage existing IDE command system).
8. **Session Persistence** — Chat history, open Markdown windows, Git Graph filters restored per project.
9. **Offline / Local Model First-class** — Full support for Ollama / LM Studio so the workflow works without internet.
10. **Audit Log** — All AI file writes and Git operations logged with timestamps for review.
11. **Theme Awareness** — Full support for Lazarus light/dark/custom IDE themes (use ThemeServices / LCL theming).
12. **Accessibility** — Proper focus order, screen-reader friendly labels, high-contrast graph mode.

### Nice-to-Have (Phase 2+)
- Mermaid / PlantUML live rendering inside Markdown windows.
- Interactive rebase visual editor.
- Git LFS awareness.
- Blame annotations in source editor (gutter).
- “Time Machine” view (checkout old commit in temporary worktree).
- Integration with Lazarus To-Do List / Bookmarks.
- Export chat + plan as a single reproducible “session package”.

---

## 5. Technical Implementation Plan

### Phase 0 – Foundations (1–2 weeks)
- Create monorepo structure:
  ```
  LazWorkflow/
  ├── Source/
  │   ├── LazWorkflowCommon/
  │   ├── LazGitManager/
  │   ├── LazGrokChat/
  │   └── Tests/
  ├── Packages/          (.lpk files)
  ├── Docs/
  └── README.md
  ```
- Scaffold three packages with Michell Computing desktop conventions adapted for IDE packages (no splash, proper `Register` procedures).
- Implement shared event bus + logging.
- Decide & vendor/bind libgit2 (or pure CLI fallback).
- Basic IDE registration: menus, dockable windows, options frames.

### Phase 1 – LazGitManager MVP (3–5 weeks)
1. Git repository detection & basic status.
2. Full action set via CLI (later migrate hot paths to libgit2).
3. Commit Graph window (virtualised custom draw, coloured lanes, basic interactions).
4. File watcher + auto-refresh.
5. Push / Pull / Fetch with progress.
6. Remote polling timer.
7. Integration tests on Linux/Windows/macOS.

### Phase 2 – LazGrokChat MVP (3–5 weeks)
1. Chat UI + streaming.
2. Footer status bar (tokens, model, etc.).
3. Conversation persistence.
4. Markdown document windows + file watchers + live reload.
5. Compiler invocation via IDEIntf + output capture.
6. Basic tool calling (read file, list directory, run compiler).
7. Settings page (API key secure storage via IDE or OS keyring).

### Phase 3 – Deep Integration & Polish (2–4 weeks)
- Bidirectional events (Git ↔ Grok).
- AI commit message generation.
- “Fix this error” from Messages window.
- Plan.md live TODO tracking.
- Theming, high-DPI, accessibility pass.
- Performance profiling (large repos, long chats).
- Documentation + example workflows.
- Package release (OPM / GitHub releases).

### Phase 4 – Advanced Features (ongoing)
- Visual interactive rebase.
- Mermaid support.
- Multi-model routing.
- Agent mode with approval gates.
- Submodule / worktree support.

---

## 6. Key Technical Decisions & Risks

| Decision                  | Choice                          | Rationale / Risk Mitigation                     |
|---------------------------|---------------------------------|-------------------------------------------------|
| Git backend               | libgit2 primary + CLI fallback | Speed + no process; CLI for complex ops        |
| Graph rendering           | Custom LCL paint                | Full control, zero deps, themeable             |
| Markdown renderer         | HTML via `TIpHtmlPanel` or similar / native | Mature, cross-platform                         |
| HTTP / Streaming          | fphttpclient + SSE parser       | Pure FPC, no external libs                     |
| Threading                 | TThread + Synchronize / Queue   | Proven LCL pattern                             |
| Secure secrets            | IDE config + OS keyring fallback| Avoid plain-text API keys                      |
| Package coupling          | Interfaces + observer bus       | Independent install possible                   |
| Large repo performance    | Virtualised graph + lazy load   | Critical for real projects                     |

**Risks**
- libgit2 binding maturity / binary distribution → ship static or clear install instructions + CLI fallback.
- IDEIntf API stability across Lazarus versions → pin minimum version, use feature detection.
- Streaming + UI responsiveness → careful thread design + cancel support.
- Markdown live reload race conditions → debounce + generation counters.

---

## 7. Development Conventions (Michell Computing Strict)

- All units under `Source/`.
- Standard FPC mode block, PascalCase reserved words, 2-space indent, 150-char line limit.
- Classes for UI & services; Packed Objects only for lightweight value types if needed.
- No UI access from worker threads.
- Full `Result` assignment, `Assigned` checks, `FreeAndNil` in destructors.
- Every public method documented with `///`.
- Packages must compile cleanly on all three major platforms in Debug + Release modes.
- Git commits follow Michell style: area prefix + imperative summary + explanatory body.

---

## 8. Deliverables

1. Three Lazarus packages (`.lpk` + source).
2. Comprehensive README with screenshots, installation (via OPM or manual), and workflow examples.
3. User guide (Markdown + optional PDF).
4. Developer documentation (architecture, extension points).
5. Unit / integration test suite (where feasible with IDEIntf mocking).
6. Example project demonstrating the full Grok → edit → compile → commit loop.
7. GitHub repository with CI (at least Linux + Windows builds).

---

## 9. Success Metrics

- Feels completely native inside Lazarus (no “foreign” look-and-feel).
- Git Graph is competitive with VS Code Git Graph in clarity and speed.
- A developer can go from “write plan.md” → Grok implements → compile → commit without leaving the IDE.
- Zero platform-specific bugs in core paths after Phase 3.
- Positive feedback from Lazarus community / forum.

---

## 10. Next Immediate Steps

1. Confirm API preferences (xAI Grok primary? OpenAI-compatible? Local-first?).
2. Decide on libgit2 vs pure CLI for v1 (recommend hybrid).
3. Create the monorepo skeleton and empty packages.
4. Prototype the Commit Graph rendering (most visually critical piece).
5. Prototype Markdown live window + file watcher.
6. Review this plan and adjust priorities.

---

**This plan is living.** It will be refined as we scaffold the first packages and validate technical choices on real Lazarus versions and platforms.

## 11. Implementation Log

### 2026-07-20 – Phase 0 Scaffolding Complete

- Created monorepo structure under `LazWorkflow/` with `Source/`, `Packages/`, `Docs/`, `Lib/`.
- **LazWorkflowCommon**:
  - `WorkflowEvents.pas` – full observer bus with Git, Compiler, Markdown and ToolCall interfaces + thread-safe `TWorkflowEventBus`.
  - `WorkflowLog.pas` – simple levelled logger.
  - `StatusFooterFrame.pas` – reusable three-part status bar.
  - Package `.lpk` ready (no `HasRegisterProc` unit; shared library only).
- **LazGitManager**:
  - Registration unit `RegLazGitManager` (name must differ from package) + menus/commands under Tools → Git.
  - Dockable `TGitGraphForm` with toolbar, paintbox placeholder for graph, detail pane, status footer.
  - `GitService.pas` – CLI-based Git operations (detect repo, status, fetch/pull/push) + event notifications.
  - Listens to repository events.
- **LazGrokChat**:
  - Registration unit `RegLazGrokChat` (name must differ from package) + menus under Tools → Grok.
  - Dockable `TGrokChatForm` with chat memo, input area, Send/New/Build actions, live status footer (model + context %).
  - Implements `ICompilerFinished` and `IMarkdownDocumentChanged`.
  - `GrokService.pas` – credential + history stub (streaming HTTP SSE in Phase 2).
- All units follow Michell Computing conventions (ObjFPC, PascalCase keywords, 2-space, proper Create/Destroy, FreeAndNil, Assigned checks, Result assignment).
- `.gitignore` and top-level README added.

**Next:** Compile-check the packages inside Lazarus, then implement real commit graph rendering and basic Grok HTTP streaming.
