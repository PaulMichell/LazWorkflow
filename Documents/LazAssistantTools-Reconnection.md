# Reconnecting interrupted model streams

The direct model streaming actor retries transient connection failures indefinitely,
waiting 30 seconds after each failed attempt. This includes socket read/write errors,
connection resets, timeouts, and streams that close without a completion event.
The assistant stays busy; no manual continuation prompt is needed.

The footer shows `Re-establishing Connection mm:ss`, or
`Re-establishing Connection h:mm:ss` after an hour. Its elapsed clock starts when
reconnection begins and continues during connection attempts. Normal streaming
status resumes when new answer or thinking text arrives. Stop cancels both the
retry wait and an active request. Application shutdown still tears down the worker.

Retries resend the current model request with its existing conversation and tool
results. Partial output from a failed attempt is discarded when retrying. Tools
from that attempt are executed only after a complete successful response; tools
from earlier completed rounds are not replayed. Permanent API errors still report
an error, and the existing Responses-to-Chat-Completions fallback is retained.

`AssistantReconnectTest` uses a fake transport to verify recovery after five
failures, socket errors, interrupted streams, permanent errors, and prompt Stop
cancellation during the real retry wait. No live model calls are needed.
