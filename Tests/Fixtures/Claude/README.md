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

To refresh: rerun the commands in an empty scratch directory, redact as above, and keep the file names.

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
