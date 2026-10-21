# ChatGPT / Codex connection diagnosis and resilience plan

Date: 21 October 2026. Repository baseline: `5a2f1ab`.

This report covers the Lazarus Project Assistant's ChatGPT connection through the local Codex app server. It records the investigation and proposes implementation work; it does not change the application's connection code or saved runtime selections.

Evidence comes from the repository, saved connection settings, generated runtime schemas, existing tests and direct process probes. The running Lazarus GUI was not instrumented and its last displayed error was not captured. Release acceptance must therefore include rebuilding/loading the revised package and checking the actual settings and send paths in the IDE.

## Findings

The immediate failure is a local compatibility policy, rather than an inability of the installed Codex runtime to connect. The installed executable reports `codex-cli 0.162.0-alpha.17.2`. LazWorkflow rejects every prerelease before starting the app server, even though this binary passes all 34 existing schema-field checks and successfully completes the connection operations tested below.

There is also a separate saved-path problem: the second ChatGPT connection still references an extension directory that no longer exists. Fixing the version check alone will not repair that saved selection.

The investigation also found a concrete protocol defect beyond initial connection: the client refuses permission requests using `scope: "none"`, which is invalid in the installed runtime's schema. The existing compatibility check cannot detect this because it checks property names, not values or message structure.

Both real account profiles were checked with the installed runtime outside the diagnostic network sandbox. Initialization, ChatGPT authentication, workspace routing, allowance retrieval, model discovery, external-tool isolation, and ephemeral thread creation succeeded. Codex refreshed both expired access tokens during those checks. There is no evidence of a remaining account, routing, basic network, model-catalog, or sandbox-negotiation blocker for the operations exercised.

No inference turn, user tool execution, browser login, logout, profile deletion, runtime installation, or application-code workaround was performed. Successful inference and an actual dynamic-tool round trip remain separate acceptance checks; neither can be inferred from account or catalog success.

## 1. Diagnosis and evidence

### 1.1 Confirmed primary blocker: blanket prerelease rejection

The installed runtime is:

```text
/home/paul/.vscode/extensions/openai.chatgpt-26.1007.21434-linux-x64/bin/linux-x86_64/codex
codex-cli 0.162.0-alpha.17.2
```

There is no `codex` executable on this diagnostic shell's `PATH`. The extension binary exists and executes successfully; absence from `PATH` is not the cause for a connection that already names that absolute path.

The relevant sequence is:

```text
TAssistantCodexAccount.Execute / TAssistantCodexRun.Execute
  -> PrepareCodexProfile
  -> TAssistantCodexClient.Connect
  -> ReadCodexVersion
  -> QualifyCodexRuntime
  -> CodexVersionIsRelease: rejects the alpha suffix
  -> failure, before app-server startup or account/read
```

An isolated Pascal diagnostic compiled against the unchanged production qualification units reproduced:

```text
read_version=TRUE version=codex-cli 0.162.0-alpha.17.2 error=
release_gate=FALSE
qualification=FALSE error=Codex is not a release build (found codex-cli 0.162.0-alpha.17.2). Alpha and prerelease builds are not used.
```

See [AssistantCodexQualification.pas](Source/LazAssistantTools/AssistantCodexQualification.pas), particularly `CodexVersionIsRelease` at line 82 and `QualifyCodexRuntime` at line 526, and [AssistantCodexClient.pas](Source/LazAssistantTools/AssistantCodexClient.pas), `Connect` at line 370.

This is no longer an exact-version pin. Commit `1642901` already replaced a version pin with release-shape and schema checks, but deliberately retained prerelease rejection. Adding another accepted version number would repeat that earlier failure mode.

Running the actual binary's `app-server generate-json-schema --experimental --out ...` succeeded. Evaluating all 34 entries in `RequiredSchemaFields` against its generated files found no missing file or property. The version gate prevents the application from reaching that otherwise-passing check.

An old successful qualification cache exists for `codex-cli 0.160.0` at the removed extension path. It cannot bypass this failure: prerelease rejection happens before cache lookup. Clearing the cache or deleting an account profile would not repair the primary blocker.

### 1.2 Confirmed independent blocker: obsolete saved executable path

The saved connections in `~/.lazarus/LazWorkflow.json` differ:

- **ChatGPT Improbable Productions:** points to the existing `openai.chatgpt-26.1007.21434-linux-x64` executable. Its immediate application blocker is the prerelease policy.
- **ChatGPT Interface Design:** points to `openai.chatgpt-26.930.51102-linux-x64/bin/linux-x86_64/codex`. That file is absent. This selection must be resolved to an installed compatible executable before a run can start.

The settings frame already tries detection when loading a missing executable and asks the user to save the new path. The send path loads `Item.Runtime` directly; it does not perform equivalent recovery. An existing but incompatible path is also not reconsidered by that settings fallback.

See [AssistantCodexSettings.pas](Source/LazAssistantTools/AssistantCodexSettings.pas), `LoadConnection` at line 478, and [ProjectAssistantForm.pas](Source/LazAssistantTools/ProjectAssistantForm.pas), the connection loading code around line 3615.

`FindCodexExecutable` returns the first PATH match, otherwise the lexicographically greatest VS Code extension directory. That ordering is unreliable for numeric versions: a directory containing `26.930` sorts after one containing `26.1007`, despite the latter being newer. It also does not compare actual runtime capabilities. Only the newer directory was found in the inspected VS Code installation, so that ordering defect is a future selection risk, not the observed choice between two installed binaries today.

The persisted active connection was `grok` when inspected. This does not disprove a failure while checking or selecting a ChatGPT row; it means the saved file alone does not establish which row produced the user's last visible error.

### 1.3 Authentication and network: tested beyond the local gate

Both dedicated profiles contained ChatGPT authentication state. At the start of the investigation, their access-token expiry metadata indicated 15 October, and their last-refresh metadata indicated 5 October. Token metadata alone does not establish whether refresh will work.

The investigation separated restricted-sandbox effects from the real host:

1. In an isolated empty profile, the installed binary accepted the application's launch arguments and fixed policy, initialized, reported that sign-in was needed, listed zero external MCP servers, and created an ephemeral thread with the expected sandbox.
2. In private temporary copies of the existing authentication/configuration files, `account/read` returned JSON-RPC error `-32603`, with the message `workspace routing discovery failed`. DNS resolution for the authentication and ChatGPT hosts also failed inside the diagnostic network sandbox. Credential copies were removed after the probes.
3. Outside that sandbox, DNS and TLS completed for both hosts. Unauthenticated HEAD requests returned HTTP 403; that establishes connectivity, not authenticated endpoint access.
4. Most decisively, app-server checks using the two original profiles outside the diagnostic sandbox succeeded. Both returned `account.type = chatgpt`, `requiresOpenaiAuth = true`, and workspace-routing information. Both also answered `account/rateLimits/read` successfully.

After those live checks, each original profile recorded a 21 October refresh and an access-token expiry of 31 October. Codex performed its normal authentication maintenance; the investigation did not replace tokens or implement a separate OAuth flow. Thus token expiry was a condition requiring refresh, and refresh worked. It is not an unresolved cause of the current application failure.

Existing profile logs inspected before the probes contained events only through 10 October for the first account and 5 October for the second. Older plugin/tool errors are not evidence of today's failure. The reproducible production-code gate is stronger evidence than those historical logs.

### 1.4 Live connection checks with the actual profiles

Both profiles passed the following operations using the installed alpha binary directly, bypassing only LazWorkflow's local qualification decision in the diagnostic harness:

- `initialize`, followed by `initialized`.
- `account/read` with `refreshToken: false`; Codex nevertheless maintained expired credentials as needed.
- `account/rateLimits/read`.
- `model/list`: seven visible entries, no next page, and each connection's selected model present (`gpt-6-astra` and `gpt-6.1-sol`, respectively).
- `mcpServerStatus/list`: empty data and no next page, satisfying the existing external-tool isolation check.
- `thread/start` using the application's provider, approval policy, named permissions, `ephemeral: true`, `environments: []`, and a diagnostic dynamic-tool definition. No turn was started and that tool was never called.

Each thread response reported:

```json
{
  "modelProvider": "openai",
  "approvalPolicy": "on-request",
  "sandbox": {"type": "readOnly", "networkAccess": false},
  "activePermissionProfile": {"id": "lazarus_ide", "extends": null}
}
```

A thread identifier was returned in each case. These checks establish that the current launch arguments, authentication-response shape, named permission profile, and basic thread/dynamic-tool registration are accepted. They do not establish inference entitlement, remaining usable allowance, or execution of every IDE tool.

In the network-restricted probes, `model/list` returned eight catalog entries even while `account/read` failed. The working host returned seven. This is direct evidence that catalog success must not be presented as proof that authentication or remote inference is working.

### 1.5 Confirmed later protocol defect: invalid permission-refusal scope

[AssistantCodexClient.pas](Source/LazAssistantTools/AssistantCodexClient.pas), `CodexNativeApprovalReply` at line 127, emits:

```json
{"result":{"permissions":{},"scope":"none"}}
```

The installed binary's generated `PermissionsRequestApprovalResponse.json` defines `PermissionGrantScope` as `turn` or `session`. Validation of the current result object against that schema failed:

```text
'none' is not one of ['turn', 'session']
```

Both `{"permissions":{}}` and `{"permissions":{},"scope":"turn"}` passed schema validation. An implementation should use a validated representation that grants no permissions; changing this field must not grant any requested access.

This does not cause the current pre-handshake rejection. It is an independent defect that can prevent correct handling of a later permission request. It also demonstrates why the current property-name check is insufficient: this response type is not checked, and checking the presence of `scope` would not validate its value anyway.

## 2. Why another version update would remain fragile

The following issues are established by source inspection. Unless separately demonstrated above, they are risks rather than additional observed causes of this incident.

- **Compatibility is all-or-nothing and too early.** Sign-in requires schemas for steering, turn summaries, named permissions and dynamic tools, even though those features are not needed to authenticate. A change to an optional run feature can disable account setup.
- **The schema check is syntactic.** `CollectPropertyNames` recursively collects names from unrelated nested definitions and union branches. It does not resolve the intended message shape, types, enums, required properties, or actual outgoing values. `SchemaFile` can fall back to a same-named file elsewhere in the generated tree.
- **Schema generation has inconsistent meaning.** A produced schema missing a field rejects the runtime, while a failed or timed-out generator clears the error and returns success. “Not checked” is therefore treated as qualified. Generator diagnostics are discarded.
- **Cache identity is incomplete.** Qualification uses the path, version, binary size, and SHA-1 samples of the first/last MiB. It can miss changes in the middle of a binary or behind an unchanged launcher. The cache has no compatibility-evaluator revision. Schema output directories and cache `.tmp` names are deterministic, creating contention between simultaneous checks.
- **Account errors lose their cause.** The handshake collapses RPC failures to a generic connection/account rejection. Transport stderr is drained and discarded. A workspace-routing, configuration, refresh, or proxy problem can look like an unspecified connection failure.
- **Fallback is not classified.** Browser login falls back to device-code login on any RPC error, rather than distinguishing an unsupported flow from network, account or policy failures.
- **Catalog and UI state are too optimistic.** `ListModels` requests only one page. Cached model/effort selections can survive changes without revalidation. Some status paths infer sign-in from non-empty runtime/model settings instead of a recent account result.
- **Experiments are enabled for every connection.** `Connect` always starts the handshake with experimental capabilities enabled. Account checks inherit the dependency on the IDE execution feature set.
- **The diagnostic utility duplicates the product's rules.** [QualifyCodexRuntime.pas](Tests/QualifyCodexRuntime.pas) maintains another release parser and schema-field list. It merges stderr into stdout, then treats the whole output as a version. A runtime warning can therefore make its verdict differ from the product's.

Relevant implementations are in [AssistantCodexQualification.pas](Source/LazAssistantTools/AssistantCodexQualification.pas), [AssistantCodexHandshake.pas](Source/LazAssistantTools/AssistantCodexHandshake.pas), [AssistantCodexProfile.pas](Source/LazAssistantTools/AssistantCodexProfile.pas), [AssistantCodexTransport.pas](Source/LazAssistantTools/AssistantCodexTransport.pas), and [AssistantCodexSettings.pas](Source/LazAssistantTools/AssistantCodexSettings.pas).

## 3. Proposed compatibility design

### 3.1 Keep the app-server integration; make capability evidence decisive

Official documentation describes version-specific schema generation, the initialize/initialized sequence, and explicit experimental API opt-in. It identifies dynamic tools as experimental and distinguishes named permission profiles from legacy sandbox fields. It does not provide a promise that arbitrary future experimental changes will be automatically compatible. See the [official App Server documentation](https://learn.chatgpt.com/docs/app-server).

Retain Codex-managed ChatGPT authentication and the app-server transport. A direct API replacement or a new SDK dependency would be a separate migration, not a necessary fix for this incident. Codex supports both ChatGPT and API-key authentication; this product should preserve its existing ChatGPT-only policy. See [official authentication documentation](https://learn.chatgpt.com/docs/auth).

Introduce a shared compatibility component used by settings, account checks, sending, and the diagnostic utility. Its result should contain:

- Runtime identity: selected/resolved paths, installation source, observed version/channel, platform/architecture, and executable identity.
- Evidence: schema availability/fingerprint, selected adapter, evaluator revision, completed live probes, and timestamp.
- Per-capability state: supported, unsupported, or unknown, with a specific reason.
- Separate connection state: executable found, protocol initialized, account needs sign-in/authenticated, catalog available, and IDE execution ready.

Parse numeric versions, prerelease identifiers and build metadata for display, candidate ordering and known compatibility exceptions. Do not reject an otherwise verified runtime simply because its version contains a suffix or is newer than the application. An unparseable version can remain “unknown” while identity and protocol checks proceed; malformed protocol responses must still fail.

A release-channel preference may rank candidates, but it must not masquerade as proof of protocol support. Keep a narrow, documented denylist only for reproduced runtime defects, with an explanation and replacement option.

### 3.2 Discover capabilities locally and verify behavior

Use the selected executable's own help/schema commands with bounded output and deadlines. Preserve separate outcomes for unavailable tooling, failed generation, invalid schema, and incompatible schema. A generator failure should never silently become a successful qualification.

Implement schema lookup by message identity and references, resolving `$ref`, unions, types, required fields and enum values for the messages actually used. Support known bundle/split-file layouts through explicit readers. Do not search all nested properties for a matching word or guess a renamed field by similarity.

Validate representative serialized requests and client responses against the installed schema, including approval refusals and dynamic-tool results. Associate each supported wire shape with a small reviewed adapter. Additional response properties and unknown informational notifications should normally be tolerated; changed execution or permission semantics require an adapter update.

Do not assume that `initialize` returns a complete server capability map or a negotiable protocol-version number. Treat its client capability flags as opt-ins. Build LazWorkflow's capability record from available schemas, recognized responses and bounded probes.

Use separate prerequisites:

- **Account access:** process startup, framing, initialization, supported account/read and login shapes. A missing steering or IDE-tool capability must not prevent an account check.
- **Basic conversation:** recognized thread/turn lifecycle and message events, with the application's required permission boundary demonstrably applied.
- **IDE execution:** dynamic-tool registration/call/result support, exact tool correlation, external-tool isolation, and validated approval handling. If a required guarantee is unknown, disable this mode with a precise reason.
- **Optional features:** steering, reasoning summaries, image inputs, usage display and particular login alternatives. Disable or omit an unsupported option instead of disabling the entire connection.

Only offer a reduced conversation mode if its tool and filesystem restrictions can actually be enforced. A missing tool capability must never trigger a fallback that lets native Codex tools perform the IDE's actions unchecked.

For the current runtime, preserve the validated `permissions: "lazarus_ide"` route. A legacy adapter may use the older sandbox fields only after tests show equivalent restrictions; do not send both representations or treat a profile name alone as proof of enforcement. Verify provider, approval policy, filesystem and network restrictions from appropriate runtime evidence before allowing a turn.

### 3.3 Resolve installations at connection time

Separate the user's selection policy from the last resolved absolute path:

- **Automatic selection:** discover candidates, validate platform/executability, inspect actual runtime identity and capabilities, then select a compatible candidate using deterministic precedence.
- **Explicit selection:** preserve the user's chosen installation. If it disappears or becomes incompatible, report that condition and offer discovered replacements; do not silently execute an unrelated PATH program.

Re-run resolution before account checks and before a new session when the saved identity is missing or changed. Recover an automatically managed extension selection after an extension update without discarding the account profile. Account identity must remain tied to the connection ID, independently of installation location.

Use numeric version comparison rather than directory-name ordering. Account for supported installation roots and architectures explicitly. Discovery on another platform must not imply that its process transport is qualified; the present transport intentionally supports Linux only.

Cache successful discovery, but do not keep running through a missing-path failure indefinitely. Show the chosen source, actual version, and why another candidate was rejected in diagnostics.

### 3.4 Make cache and process lifecycle reliable

Use a fast stat/identity check to trigger revalidation, followed by a full executable digest off the UI thread when needed. Identify the actual payload behind symlinks or launchers; where that cannot be established reliably, repeat bounded schema/live checks. A head/tail sample is a performance hint, not complete identity evidence.

Key compatibility caches by runtime identity, relevant schema fingerprint, adapter/evaluator revision, platform, and configuration-policy revision. Store individual capabilities and their provenance. Never cache authentication or entitlement as part of binary compatibility. Negative transient results need short expiry and an explicit retry action.

Generate schemas in unique private temporary directories. Publish cache records atomically with unique temporary files, and coordinate concurrent work on the same runtime. Cancellation must reach version probing, schema generation and handshake stages. Bound process-group cleanup and keep diagnostics on worker threads.

Detect replacement of the executable between inspection and launch. Allow an already-running compatible process to finish if safe; resolve and validate the new executable before the next session.

### 3.5 Separate authentication, discovery, execution and recovery

Keep each connection's dedicated profile and Codex-owned token refresh. Do not delete authentication state as a response to a compatibility failure. Preserve intended proxy/CA settings, while reviewing the child environment for newer credential/provider overrides that could defeat the ChatGPT-only policy. Such overrides were not present in this investigation's environment.

Record method, stage, JSON-RPC code, elapsed time and a sanitized explanation. Distinguish missing executable, incompatible feature, malformed protocol, rejected configuration, routing discovery, refresh failure, sign-in required, network/TLS failure, quota and model access. Keep account identities, tokens, login URLs and message contents out of routine diagnostic logs.

Capture a bounded, redacted stderr tail separately from protocol stdout. Retain process exit status. Separate stderr warnings from version output and require meaningful command exit-status handling. A failed bootstrap must not turn into an indefinite generic reconnect loop.

Use browser/device-code fallback only for recognized unsupported-flow conditions. Let Codex handle authentication maintenance, and distinguish a recoverable network failure from a response requiring renewed user sign-in. Preserve useful runtime error details instead of replacing all of them with one account-error sentence.

Paginate model discovery, cache it with freshness and account/runtime context, and validate the selected model and reasoning effort. Catalog presence is not an entitlement check. If a selection disappears, retain the saved preference for explanation and require an explicit replacement choice rather than silently changing the model.

Publish connection status from actual probe snapshots. “Configured,” “signed in,” “model list loaded,” and “ready for IDE actions” must be different states.

Retry bounded read-only discovery requests on transient failures with backoff and jitter. Do not blindly replay `turn/start`, an accepted steering request, or a completed IDE action after a disconnect. Reconcile request/turn state first and use documented deduplication where supported. The current threads are ephemeral; durable resume cannot be assumed. Any move to persistent threads requires an explicit history and recovery design.

## 4. Implementation sequence

### Stage A: repair the present blockers

1. Replace blanket prerelease rejection with capability qualification for the current wire adapter. Retain the authentication, provider, approval and sandbox checks. Add the installed alpha as a real-runtime regression case, not as a one-off version exception.
2. Fix `CodexNativeApprovalReply` to emit a schema-valid empty permission grant. Validate all native approval response variants, including unknown variants being refused safely.
3. Move runtime resolution into the common connection-start path. Recover obsolete automatically selected extension paths and retain the existing profile ID. Make explicit selections visibly actionable when missing.
4. Preserve diagnostic error stages/codes and report schema-tool failures as unknown or unavailable. Keep account setup usable when only optional execution capabilities are missing.

Primary files: `AssistantCodexQualification.pas`, `AssistantCodexClient.pas`, `AssistantCodexProfile.pas`, `AssistantCodexHandshake.pas`, `AssistantCodexSettings.pas`, `AssistantCodexAccount.pas`, and the runtime loading path in `ProjectAssistantForm.pas`.

Completion evidence: the unmodified installed `0.162.0-alpha.17.2` passes application Check Connection for both rows after appropriate path resolution; permission refusals validate; incompatible permission/tool behavior remains blocked.

### Stage B: introduce adapters and capability-specific behavior

Create the shared capability/evidence model and semantic schema reader. Split account preflight from run preflight, select recognized adapters, paginate the catalog, and gate optional UI features. Replace hard-coded request assembly incrementally with adapter-owned serialization, while retaining the existing JSONL transport and IDE tool broker.

Completion evidence: removing an optional schema feature disables only that feature; changing a required approval or permission contract blocks IDE execution with a specific message. Added response fields and new model IDs do not require a client release.

### Stage C: harden updates and diagnostics

Implement revised cache identity/invalidation, unique schema directories, concurrency control, cancellation, structured diagnostics and classified recovery. Have `Tests/QualifyCodexRuntime.pas` call the same evaluator as the product. Extend the diagnostic command to emit a redacted stage report with an explicit no-inference mode.

Completion evidence: concurrent checks, extension replacement, cache corruption, wrapper changes, slow startup, process death and failed schema generation all have deterministic outcomes without blocking the IDE thread or weakening execution restrictions.

### Stage D: qualify future releases before promotion

Maintain immutable fixtures for a verified older stable runtime, the current production candidate and a current extension/prerelease candidate. Record where each binary/schema came from and its digest. Do not treat the old `0.160.0` cache as sufficient evidence to declare that release supported today.

Run the contract suite on every client change. Add periodic CI checks of candidate Codex releases and schema diffs, with reviewed adapter updates for incompatible changes. Separate qualification of a candidate from selecting it for users; retain a previously verified installation where the installation method permits it. Do not automatically download, downgrade, overwrite extension binaries, or migrate credentials as a connection repair.

Arbitrary future breaking changes cannot be made impossible. The achievable contract is that additive changes and known alternate shapes adapt automatically, optional capabilities degrade individually, and an unknown essential contract produces a precise explanation while preserving working account access and recoverable state.

## 5. Validation and release acceptance

### Checks performed for this report

- Compiled a temporary Pascal probe against the production qualification/profile units and reproduced the exact prerelease rejection.
- Generated the installed runtime's experimental schema and verified all 34 existing field checks.
- Validated the permission-refusal result against the generated JSON Schema: current `scope: "none"` failed; the two empty-grant alternatives described above passed.
- Exercised empty-profile startup and both real profiles through the non-inference operations listed in section 1.4.
- Distinguished sandbox DNS/routing errors from the working host's authenticated results. Confirmed normal token refresh in both original profiles.
- Ran the existing regression runner for `AssistantCodexHandshakeTest`, `AssistantCodexTransportTest`, `AssistantCodexClientTest`, and `AssistantConnectionsTest`, using the local Lazarus checkout and temporary test/config directories.

`AssistantCodexHandshakeTest` passed 101 checks and `AssistantCodexTransportTest` passed 17 checks. The runner also reported successful assistant/repository package builds and monitor package/link checks.

The selected regression run was **not fully green**:

- `AssistantConnectionsTest` failed to compile at its `ExecuteAssistantToolForMode` calls around lines 321 and 338 because their argument lists do not match the current overloads.
- `AssistantCodexClientTest` failed to link with unresolved LCL widgetset symbols, including `WSRegisterToolBar` and related `WSRegister*` functions. Its program does not include `Interfaces`; repair and verify its intended widgetset initialization rather than counting the test as passed.

These failures predate any implementation proposed here; this task changed no product source. They reduce confidence in the current regression barrier and should be repaired before releasing the connection changes. The original client fixtures also explicitly expect alpha rejection and use synthetic schema property lists, so they need meaningful contract coverage as well as an updated expected policy.

### Required acceptance cases

1. A compatible stable, prerelease, and previously unseen version passes by capability. An incompatible runtime is rejected by the specific contract it violates, not its version label.
2. Missing or relocated executables, several PATH candidates, numeric extension ordering, launcher-payload changes and architecture mismatch resolve or fail predictably.
3. Missing schema tooling, unsupported generator options, timeouts, malformed JSON, changed `$ref` layouts, added fields, changed enum values and required-field changes produce distinct results.
4. The actual emitted initialize, account, thread, turn, steer, interrupt, approval and dynamic-tool messages validate against each supported runtime schema. Include the current invalid-scope regression.
5. Missing optional steering, reasoning or image capability leaves supported connection functions usable. Missing required execution isolation prevents an IDE action.
6. Expired credentials with successful refresh, failed refresh, workspace-routing failure, device-flow unavailability, provider changes and authentication notifications are exercised separately. No API-key fallback occurs.
7. Catalog pagination, empty catalogs, stale cached model/effort selections and catalog success during account failure have truthful UI outcomes.
8. Concurrent checks, cancellation at every preflight phase, stderr warnings, nonzero version-command exit, large binaries, partial JSONL frames, late responses and process exit do not hang or corrupt state.
9. Recovery never repeats a completed IDE write or blindly resubmits a turn whose acceptance is uncertain.
10. A controlled live acceptance run demonstrates one harmless inference, streamed completion, a read-only dynamic-tool call/result, refusal of a native permission request, interruption and reconnection. Confirm `turn/completed` status rather than treating the arrival of the notification as success. Keep this separate from the default no-inference connection check.

### Reproduction commands and evidence locations

The following read the installed version, generate its schema into a private temporary directory, and run the selected existing tests. The tests currently have the failures recorded above.

```bash
runtime='/home/paul/.vscode/extensions/openai.chatgpt-26.1007.21434-linux-x64/bin/linux-x86_64/codex'
"$runtime" --version
schema_dir="$(mktemp -d /tmp/laz-connection-schema.XXXXXX)"
"$runtime" app-server generate-json-schema --experimental --out "$schema_dir"

XDG_CONFIG_HOME=/tmp/laz-connection-tests/config \
instantfpc --set-cache=/tmp/laz-connection-tests/runner \
  Tests/RunAssistantTests.pas \
  --lazarus-root /home/paul/Projects/FreePascal/Lazarus \
  --output-dir /tmp/laz-connection-tests/results \
  --only AssistantCodexHandshakeTest \
  --only AssistantCodexTransportTest \
  --only AssistantCodexClientTest \
  --only AssistantConnectionsTest
```

Session-local evidence is under `/tmp/laz-connection-2vbbs99k` and `/tmp/laz-connection-tests/results`. The sanitized live diagnostic script is `/tmp/laz-connection-live-probe.py`; it uses existing profiles and allows Codex's normal authentication maintenance, so it is not a purely offline check. These temporary paths are not durable repository dependencies; the material results are recorded in this report. No credentials or raw account responses are included here.

The remaining uncertainty is end-to-end inference and tool execution after the proposed changes. The investigation establishes the present local blockers and a later protocol mismatch, and directly verifies the account/network stages that could otherwise have been hidden behind the version error. It does not claim that a catalog, successful thread creation, or a passing field-name check proves every future Codex behavior compatible.

## Implementation and verification — 21 October 2026

The preceding diagnosis records the original code and failures. The implementation now removes the release-channel gate; the old version-format helper is informational. The installed `codex-cli 0.162.0-alpha.17.2` passes every implemented capability check and selects `named-permissions-tagged-v1`.

Implemented changes:

- A shared, bounded schema evaluator follows local references and checks actual outgoing values, types, enums, required fields and union branches. It checks the incoming fields the adapter consumes without rejecting additive response requirements. Unsupported schema constraints fail closed. This is a deliberately limited contract evaluator, not a general-purpose JSON Schema implementation.
- Account, browser login, device login, model discovery, execution, steering, summaries, images and allowance lookup have separate evidence. Account-only connections use stable initialization. A missing schema generator permits account checks but cannot authorize IDE execution. Optional summary omission and tagged/legacy dynamic-tool serializers are chosen by schema evidence, not version ranges. The real schema also revealed the newer required `type: "function"` discriminator on dynamic tools.
- Permission refusals use `scope: "turn"` with empty grants. Unknown approval methods receive `-32601`. Execution still requires a verified OpenAI provider, on-request approval, read-only sandbox, disabled runtime network access, and no external MCP tools. Neither compatibility failures nor authentication failures switch to a metered provider.
- Preflight has cancellation, process-group cleanup, a 15-second limit per subprocess, bounded output and unique private schema directories. Cache keys include the complete executable hash, path, reported version and evaluator revision. Cache writes use unique files and atomic replacement; corrupt/unwritable caches are nonfatal. Launcher scripts are requalified because their underlying payload can change independently. Identity is checked again before launch. Concurrent callers may generate duplicate evidence, but do not share or delete each other's temporary directories.
- Extension discovery compares version components numerically and searches VS Code, VS Code Insiders and Cursor extension directories. Missing recognized extension-managed paths are resolved again at connection time. Existing paths and missing custom paths are preserved. This intentionally conservative migration does not silently substitute a runtime for an arbitrary custom selection.
- Browser-to-device fallback is restricted to an unsupported browser-login parameter response. Other RPC failures retain operation and numeric code with a safe diagnostic category, rather than displaying arbitrary server text. Process exits include the exit status and a category derived from bounded private stderr; raw stderr is never displayed.
- Model discovery follows bounded, nonrepeating cursors and publishes the complete catalog. Each new IDE run refreshes that catalog and rejects a removed model or reasoning effort before creating its thread. Settings distinguish an authenticated account from unavailable IDE execution, and show the runtime version. A known unsupported model-list contract ends account discovery with a specific note instead of waiting indefinitely.
- Dropped Codex turns stop rather than automatically replaying possibly completed IDE actions. Reconnect does not attempt to resume or replay an uncertain turn.
- The offline qualification command uses the production evaluator. A versioned fixture manifest records source and retained-schema SHA-256 hashes from the installed runtime. Contract tests cover enums, types, required fields, additive incoming requirements, references, recursion, unsupported constraints, version ordering and diagnostic redaction. Client tests cover prerelease/unknown versions, schema-generator failure, account-only degradation, large executables, paginated models and the existing streaming/tool/cancellation behavior.
- A GitHub Actions workflow runs the offline contract suite for relevant pull requests and checks the latest published runtime without credentials on a weekly schedule or manual invocation. This workflow has been added but has not yet executed on GitHub. The committed real-runtime fixture represents the verified installed candidate; older release labels in the fake-runtime tests are presentation tests, not evidence that those released binaries were tested.

### Actual verification

The revised production client was compiled and run against both existing isolated ChatGPT profiles on the host, with normal runtime authentication maintenance allowed. For **both profiles**, all of these passed:

1. Executable qualification and initialize handshake.
2. ChatGPT subscription account authentication.
3. Paginated model discovery.
4. Account allowance lookup.
5. External-tool isolation check.
6. Thread creation with a tagged diagnostic dynamic tool, including verification of provider, approval policy, read-only sandbox and disabled runtime tool network access.

No model inference turn or IDE tool execution was submitted during these live checks. Thus live generation/streaming and tool execution remain outside the verified boundary; their regression coverage is supplied by the fake-runtime tests. No credential, account identity or raw account response is stored in this report or the fixtures.

The selected schema, client, handshake, transport, recovery and connection regression programs pass. The assistant package compile and all four monitor link-isolation checks pass. The runner's separate full `LazAssistantMonitor` lazbuild step still fails because this local installation cannot find the `qt5` unit used by `AssistantFileDropQt`; this is distinct from the passing assistant compilation and Codex tests. The old connection-test signature and image-fixture failures described above were repaired.

The implementation prevents known version-related failures and detects incompatible future contracts; it cannot promise compatibility with arbitrary future protocol redesigns. Such a redesign may still need a new adapter. Further release engineering can add independently verified older stable fixtures, broader operating-system coverage, explicit persisted automatic/manual selection controls, live inference acceptance tests. These are not claimed as verified behavior in this change.

### Shared offline diagnostic

Build/run the shared qualifier with the project's compiler and Lazarus utility paths (adjust the Lazarus location for the host):

```bash
instantfpc --set-cache=/tmp/laz-codex-qualifier \
  -Fu"$PWD/Source/LazAssistantTools" \
  -Fu"$PWD/Source/LazWorkflowCommon" \
  -Fu/home/paul/Projects/FreePascal/Lazarus/components/lazutils/lib/x86_64-linux \
  Tests/QualifyCodexRuntime.pas \
  --runtime /absolute/path/to/codex --output-dir /tmp/laz-codex-evidence
```

`qualification.json` records version, executable identity, schema identity, adapter, and individual capability reasons. It contains no authentication evidence. `Tests/AssistantCodexProbe.lpr` is the explicit host-network diagnostic for an existing isolated profile; it exercises account, catalog, allowance and thread-policy checks without sending an inference turn.
