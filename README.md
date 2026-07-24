# LazWorkflow

**Lazarus IDE Add-in Suite for Git + Grok LLM Workflow**

Michell Computing style packages that provide a seamless, native Git management UI and a rich Grok (xAI / OpenAI-compatible) chat interface inside the Lazarus IDE.

## Packages

| Package              | Description                                                                 | Depends on          |
|----------------------|-----------------------------------------------------------------------------|---------------------|
| **LazWorkflowCommon** | Shared event bus, interfaces, logging, common UI helpers                   | LCL, IDEIntf       |
| **LazRepositoryTools**    | Full Git lifecycle UI + high-quality commit history graph (VS Code style)  | LazWorkflowCommon  |
| **LazAssistantTools**      | Grok chat UI, live Markdown document windows, compiler integration         | LazWorkflowCommon  |

## Features (Target)

### LazRepositoryTools
- Dockable Git Graph window (coloured lanes, interactive, live refresh)
- Full Git lifecycle menus & actions
- Working tree status, staging, commit, push/pull/fetch
- File-system watcher + optional remote polling
- Project-aware (detects Git root from current Lazarus project)

### LazAssistantTools
- Persistent multi-conversation chat with streaming
- **xAI OAuth sign-in** (SuperGrok / X Premium) — no console API key required
- Status footer (context usage, model, tokens, connection)
- Live Markdown document windows (auto-reload on disk change) — ideal for `plan.md` / TODOs
- Direct compiler invocation via IDEIntf
- Tool calling so the model can drive Git operations and file edits
- Bidirectional integration with LazRepositoryTools

## Requirements

- Lazarus 3.x / 4.x (or trunk)
- Free Pascal 3.2.2+ (tested with custom 3.3.1 builds)
- Cross-platform: Linux, Windows, macOS
- For LazAssistantTools: SuperGrok or X Premium subscription (OAuth via `accounts.x.ai` / `auth.x.ai`)

## Installation

1. Open `Packages/LazWorkflowCommon.lpk` in Lazarus → Compile → Install
2. Open `Packages/LazRepositoryTools.lpk` → Compile → Install
3. Open `Packages/LazAssistantTools.lpk` → Compile → Install
4. Restart IDE

Or use Online Package Manager when published.

## Repository Layout

```
LazWorkflow/
├── Source/
│   ├── LazWorkflowCommon/     # Shared foundation
│   ├── LazRepositoryTools/         # Git UI package
│   ├── LazAssistantTools/           # Grok chat package
│   └── Tests/
├── Packages/                  # .lpk files
├── Docs/
├── Lib/                       # Compiled units (per platform)
└── README.md
```

All Pascal source lives under `Source/` following Michell Computing conventions.

## Licence

LGPL-2.1-or-later with static linking exception (standard Lazarus package licence).  
Copyright (c) 2026 Michell Computing / contributors.

## Status

**Phase 0 – Foundations** (in progress)

See `Docs/ProjectPlan.md` for the full roadmap.
