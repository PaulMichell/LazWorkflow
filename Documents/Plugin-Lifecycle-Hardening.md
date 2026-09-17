# Repository manager and project assistant lifecycle review

Reviewed 17 September 2026 after a report of Lazarus exiting when reopening the
repository manager. No trace of the original crash was available. A subsequent rapid reopen/dispose
test was terminated by a signal, exposing a concrete Git launch/cancel race.
The test passes after fixing that race, but this does not establish the cause
of the original Ecology Survey Scheduler incident.

## Findings and changes

- Git cancellation could call TProcess.Terminate before Execute had assigned a
  process ID. Free Pascal's Unix implementation calls kill(0, SIGTERM) in that
  case, signalling the entire process group. The active process is now published
  only after launch, cancellation requires a positive process ID, and its shared
  flag uses atomic reads/writes. A cancellation arriving during launch is handled
  by the first drain-loop check. The assistant Codex transport also requires a
  positive process ID before issuing termination signals; build-worker cleanup
  already had this check.

- Both IDE window factories now assign their output only after a normal form
  constructor returns. Lazarus's CreateForm helper assigns a raw instance before
  calling its constructor. On constructor failure that pointer can refer to an
  already destroyed form; the repository fallback previously freed it again.
  Failed creation now logs the error and returns no form, allowing a later retry.
- Window-opening and project lifecycle hooks contain exceptions at the plugin
  boundary. Assistant registration is guarded too. The repository project-close
  hook no longer queries the half-destroyed ActiveProject to update its menu.
- Repository resize, paint, selection and timer callbacks check teardown or
  missing initialization state. Destruction removes listeners and detaches diff
  notifications before releasing models, avoiding new refresh jobs during close.
  Failed periodic callbacks are logged and their timers are disabled.
- Git busy callbacks now have the same exception isolation as completion
  callbacks, so a failed view update cannot interrupt job submission/delivery.
- Assistant teardown disconnects stream/trace callbacks and disables its timer
  before cancellation can pump queued calls. Saving a session or settings cannot
  abort the remaining form cleanup. Connection settings tolerate unavailable IDE
  services and log load errors. The explicit ProcessMessages call before review
  builds was replaced with a local status-control repaint.
- Unexpected exceptions escaping an assistant turn are converted into a finished
  error snapshot. Service destruction removes deferred subagent cleanup callbacks;
  access to the deferred cleanup list is locked, with destruction outside the lock.
- Assistant trace/surface destructors handle incomplete initialization.
- The shared event bus snapshots registration tokens instead of retaining raw
  non-refcounted form interfaces. Unregistering clears the token before disposal,
  so a listener removed/freed by an earlier callback is skipped safely. Listener
  exceptions remain isolated. UI notifications must still run on the IDE thread.

## Validation

- All 19 default console tests pass, including repository safety, real local Git
  pulls, and a new event-bus test that destroys a pending listener while notifying.
- Repository safety tests inject exceptions into both busy and completion
  callbacks and verify a subsequent job still completes.
- The reconnection test verifies that queued stream callbacks cannot reach a
  detached view.
- Qt5 offscreen form tests run ten create/show/hide/show/destroy cycles for the
  repository manager and ten assistant create/destroy cycles. Assistant settings
  writes fail deliberately on every close; all forms still unregister cleanly.
- Qt5 offscreen trace-view, provider, and subagent tests pass.
- Both assistant and repository packages compile with range/overflow checks.
- The broader conversation-surface test fails its published paint-revision check
  under Qt5 offscreen. The identical assertion fails against the previous commit
  (6b2a3d5); this is not introduced by the lifecycle changes.

Console/build logs: `/tmp/laz-guards-final`. Additional fault-injection/Qt logs:
`/tmp/laz-guards-tests`. No live model requests or user repositories were modified
by tests. Windows and the running Ecology Survey Scheduler IDE were not tested.

These are in-process Lazarus plugins. Exception guards and lifetime fixes reduce
crash risks but cannot isolate the IDE from every native/widgetset fault or memory
corruption. A stack trace would still be needed to diagnose the original crash.
