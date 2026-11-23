# Claude Code fixtures

Captured on 28 October 2026 from Claude Code 2.1.312 on Linux, signed in with a Claude Pro subscription, using
`--model haiku`. Used by `Tests/AssistantClaudeClientTest.lpr`.

Redaction: account email, organisation and directories are replaced with `redacted`; working-directory paths are
replaced with `/work`; `init` events keep only the fields the client reads plus a few for orientation; thinking
signatures and `commands_changed` events are removed. Session IDs, message IDs and token counts are as captured.

| File | Command (prompt on stdin) | Shows |
|------|---------------------------|-------|
| `auth-sub.json` | `claude auth status --json` | A claude.ai subscription (`subscriptionType: pro`). |
| `auth-key.json` | `ANTHROPIC_API_KEY=<dummy> claude auth status --json` | The environment key overrides the subscription (`authMethod: api_key`). |
| `plain-result.json` | `-p --output-format json` | Single-result output. |
| `plain.jsonl` | `-p --output-format stream-json --verbose` | `init` with `apiKeySource: none`, one text block, `rate_limit_event`, `result`. |
| `tool.jsonl` | as above, `--tools Read --session-id <uuid>` | `tool_use`, `tool_result`, then the answer. |
| `resume.jsonl` | as above, `--resume <same uuid>` | The resumed session remembers the earlier read. |
| `denied.jsonl` | as above, `--tools Read,Write` | A denied `Write`: the turn still ends `success`, with `permission_denials`. |
| `maxturns.jsonl` | as above, `--max-turns 1` | `error_max_turns`: `is_error`, no `result`, reason in `errors`. |
| `badresume.jsonl` | `--resume` with an unknown session | `error_during_execution`, `errors: ["No conversation found …"]`. |
| `image-input.jsonl` | `-p --input-format stream-json --output-format stream-json --verbose --session-id <uuid> --tools=`; stdin is one user message with a text block and a base64 PNG `image` block | The plain user-message shape is accepted and the turn describes the picture (a red circle on yellow). |
| `image-resume.jsonl` | as above, `--resume <same uuid>`; stdin is one text-only user message | The resumed session still knows the earlier picture without it being sent again. |
| `mcp-image.jsonl` | `-p --output-format stream-json --verbose --tools=Read,Grep,Glob --mcp-config=<file> --allowedTools=mcp__capture__*`; prompt as plain text | An MCP `image` item (`data`, `mimeType`) reaches the model (a green triangle on white). The stream's `tool_result` shows it in API form, `{"type":"image","source":{"type":"base64",…}}`, in both `content` and `tool_use_result`. |

The three image files were captured on 22 November 2026 from Claude Code 2.1.322, otherwise as above.

To refresh: rerun the commands in an empty scratch directory, redact as above, and keep the file names. The three image
files come from the capture program below.

## Images

`CaptureClaudeImages.lpr` captures the three image files, and probes how stdin must be closed and what size and
format Claude Code accepts. Its work is in `Tests/ClaudeCaptureProgram.pas` and `Tests/ClaudeCaptureSupport.pas`;
`Tests/ClaudeCaptureTest.lpr` checks those without starting claude, so the runner keeps them compiling.

The program checks `claude auth status` (through `ReadClaudeAccount`) and stops unless Claude Code is on a claude.ai
subscription. Every turn gets the environment of `BuildClaudeEnvironment`, the one IDE turns get. It never reads or
copies Claude sign-in files, and never passes `--bare`, `--max-budget-usd` or `--betas`. Each turn runs in an empty
scratch directory in the system temporary directory, so Claude Code finds no project instructions; the directory is
removed at the end. The only pictures are synthetic and drawn by the program: a red circle on yellow (256 × 256) for
input, a green triangle on white for the MCP result, and 1600 × 1600 random noise for the size probe.

Build and run from the repository root, signed in to the subscription, with `<Lazarus>` the Lazarus checkout and
`<cpu-os>` such as `x86_64-linux`:

```sh
mkdir -p Temporary/ClaudeCapture
fpc -MObjFPC -FUTemporary/ClaudeCapture -FETemporary/ClaudeCapture -FuTests -FuSource/LazAssistantTools \
  -FuSource/LazWorkflowCommon -Fu<Lazarus>/components/lazutils/lib/<cpu-os> \
  Tests/Fixtures/Claude/CaptureClaudeImages.lpr
Temporary/ClaudeCapture/CaptureClaudeImages --output-dir Temporary/ClaudeCapture/Run
```

Options: `--claude <path>` (default: `claude` on `PATH`), `--model <name>` (default `haiku`, as for the other
fixtures; `--model ''` leaves it to Claude Code), `--timeout <seconds>` per turn (default 300), and `--case <name>`,
which may repeat. Without `--case` every case runs:

| Case | What it sends | What it shows |
|------|---------------|---------------|
| `image-input` | One stream-json user message: a text block, then `{"type":"image","source":{"type":"base64","media_type":"image/png","data":…}}`. Stdin is closed after the line. | Whether stream-json input works in print mode and the picture is described. If this shape gets no successful result, `image-input-sdk` tries again with the Agent SDK's extra `parent_tool_use_id: null` and `session_id: ""`; the resume turn then uses whichever shape worked. |
| `image-resume` | `--resume` on that session, one text-only stream-json message. Runs `image-input` first. | Whether the session still holds the picture. |
| `mcp-image` | The prompt as plain text. Claude Code starts this same program with `--mcp-server <log>` as the stdio server `capture`, whose tool `show_picture` returns a text item and an `image` item. | Whether the picture reaches the model, and the `tool_result` the stream shows. |
| `stdin-open` | A text-only stream-json message, with stdin left open until 15 s after the `result` event. | Whether one stream-json turn ends by itself or waits for stdin to close. |
| `limits-large` | The noise picture, over 5 MB as a PNG: the Anthropic API's documented limit is 5 MB per image, 8000 pixels a side, and JPEG, PNG, GIF or WebP. | What Claude Code does with an image over the size limit: refuses it, shrinks it, or passes the API's error on. |
| `limits-format` | The input picture declared as `image/bmp`. | How a format outside the accepted list is refused. |

The probe turns pass `--no-session-persistence`. Everything goes to `--output-dir`, which must be under `Temporary/`:
`<case>.jsonl` (stdout as received), `<case>.stderr.txt`, `<case>.input.txt` (the exact stdin), the pictures,
`mcp-config.json`, `mcp-server.log` (each request, and each reply with image data shortened), and `summary.md`. The
summary gives, for each case, the command, the stdin with image data shortened, when the `result` event came, when
stdin was closed and when the process ended, whether the answer names the expected colour and shape, and one line per
stream event. Record the accepted shape, the resume and MCP findings, the limits and the stdin rule from it.

To make the fixtures: copy `image-input.jsonl` (or `image-input-sdk.jsonl` if only that shape worked),
`image-resume.jsonl` and `mcp-image.jsonl` here and redact them as at the top of this file. Replace the scratch
directory path with `/work`, and the path of the capture program and its log in the `init` event's `mcp_servers` with
`/work/CaptureClaudeImages`. Keep the base64 data of the synthetic pictures as captured; they are small and contain no
user material. Commit no other picture, and no prompt other than the program's own. Leave the probe output in
`Temporary/`: record its findings in the plan instead.

## MCP requests

`mcp-requests.jsonl` is used by `Tests/AssistantMCPProtocolTest.lpr`: one JSON-RPC message per line, the HTTP
request bodies Claude Code sends to a `--mcp-config` server called `lazarus`, in the order it sends them
(`server/discover`, `initialize`, `notifications/initialized`, `tools/list`, `tools/call` for `read_buffer`).

**Not yet captured.** The lines are written by hand in the shape of the MCP TypeScript SDK that Claude Code uses;
the methods and their order are the ones seen with a stub server (review §12.1), but that run kept no request
bodies. To capture: serve a stub over HTTP that logs each request body and offers one tool `read_buffer`, run
`claude -p --model haiku --tools=Read --mcp-config=<file> --strict-mcp-config --allowedTools=mcp__lazarus__*` with
a prompt asking it to read `Main.pas` through that tool, then replace the lines with the logged bodies, keeping the
`tools/call` arguments as `{"path":"Main.pas"}`.

## Offer snapshots

`inspect.txt`, `document.txt`, `plan.txt`, `build.txt` and `chat.txt` are the tool names a Claude turn is offered and the system text actually appended, for each conversation mode. `Tests/AssistantOfferSnapshotTest.lpr` compares them. A catalogue or prompt change fails until the file is updated on purpose. `<if-can-create-file>` stands for `mcp__lazarus__create_file`, which the IDE offers only when `CanCreateNewText` is true. Sibling snapshots are `Tests/Fixtures/Grok/` and `Tests/Fixtures/ChatGPT/`. OpenAI-compatible has none.
