# LazWorkflow

**Lazarus IDE add-in suite for Git and a project-aware Assistant**

Michell Computing style packages: a native Git UI and a Project Assistant (xAI Responses API, Chat Completions fallback) fused with the Lazarus IDE.

## Packages

| Package | Description | Depends on |
|---------|-------------|------------|
| **LazWorkflowCommon** | Event bus, logging, status footer, spell-check helpers | LCL |
| **LazStyledText** | Styled edit/memo/list controls and compact Markdown loader | LCL |
| **LazRepositoryTools** | Manage Repository: history graph, files, fetch/pull/push | LazWorkflowCommon |
| **LazAssistantTools** | Project Assistant: Ask / Plan / Build, streaming, tools, Git suggest | LazWorkflowCommon, LazStyledText |

## Features

### LazRepositoryTools
- Dockable **Manage Repository** (History graph, Files, remotes)
- Working tree status, staging, commit, fetch / pull / push
- Project-aware Git root from the active Lazarus project
- **Suggest** commit message via the Assistant (read-only diff)

### LazAssistantTools
- **Project Assistant** dock: one transcript, **Ask · Plan · Build** chips (hard tool gates)
- Streaming with a typed trace (thinking, tool cards, subagent rows, answer)
- **xAI OAuth** (SuperGrok / X Premium) or an OpenAI-compatible API key
- **Responses API** is the thinking channel; Chat Completions is automatic fallback
- Plan Markdown under `Documents/` with live windows; Build mode scans `Status:` tiles
- Source tools (`replace_in_file`, `run_compile`, `ensure_form_component`, …) in Build
- Depth-1 **spawn_subagent** and **Review Changes** (Pascal naming / structure / review lenses)
- Command catalog on **Commands…** / `Ctrl+P`, `/` in the prompt, and footer clicks (model, skill, context, session)
- After a Plan write, **Build this** / **Revise**
- Project-local `.assistant/` (conversation JSONL, events log, config). Gitignore it.

### Git commits from Build mode

Build mode provides `run_git` (API backend) or `lazarus_run_git` (ChatGPT backend)
for `status`, `diff`, `log`, `show`, `rev-parse`, `ls-files`, explicit `add`, and
normal `commit -m` commands in the active project directory. Git must be on PATH.
Save authorized editor changes before staging; inspect the staged diff and keep
unrelated changes out of the commit.

You can put this instruction in the conversation or active plan:
"After completing and validating each work package, automatically commit its changes."
Use **Approval: Auto** to execute these tool calls without individual prompts;
**Ask** continues to request approval. Ask and Plan modes cannot execute Git.
Remote operations, destructive commands and history rewriting are not exposed.

## Requirements

- Lazarus 3.x / 4.x (or trunk)
- Free Pascal 3.2.2+ (tested with 3.3.1)
- Linux, Windows, macOS
- SuperGrok / X Premium for xAI OAuth, or another OpenAI-compatible endpoint

## Installation

1. `Packages/LazWorkflowCommon.lpk` → Compile → Install
2. `Packages/LazStyledText.lpk` → Compile → Install
3. `Packages/LazRepositoryTools.lpk` → Compile → Install
4. `Packages/LazAssistantTools.lpk` → Compile → Install
5. Restart the IDE

## Repository layout

```
LazWorkflow/
├── Source/
│   ├── LazWorkflowCommon/
│   ├── LazStyledText/
│   ├── LazRepositoryTools/
│   ├── LazAssistantTools/
│   └── Tests/
├── Packages/
├── Documents/          # project plans (v2 architecture is ProjectPlan-v2.md)
├── Lib/                # unit output per CPU-OS, one subdirectory per package
└── README.md
```

All Pascal source lives under `Source/` (Michell Computing conventions).

## Licence

LGPL-2.1-or-later with static linking exception (standard Lazarus package licence).  
Copyright (c) 2026 Michell Computing / contributors.

## Status

**v2 work packages 1–7 plus package 4 leftovers are complete** (protocol, actor, trace, shell, harness, subagents, history replay, slash catalog, footer clicks, Plan **Build this**).

Next: package 8 shell density (`Documents/ProjectPlan-v2.md`). Large-trace virtualization is only needed if a turn overflows the GTK ~30k coordinate cap.

See `Documents/ProjectPlan-v2.md` for architecture. `Documents/ProjectPlan.md` is the v0.2 implementation log.
