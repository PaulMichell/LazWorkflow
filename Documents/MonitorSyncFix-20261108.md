# Monitor sync repair — 2026-11-08

The physical phone capture showed block-close events without duration_ms. Android required that metadata, discarded each close, and detected sequence gaps on subsequent events. Repeated resumes replaced queued body transfers, while the phone retained occupied fetch slots.

Android now accepts an absent block duration as zero and releases/retries outstanding fetches when resume or a committed snapshot completes. The desktop now includes the new-turn prompt, block duration, turn duration/error text and image dimensions required by the catalogue. No catalogue 2 path was added.

Validation: protocol tests, focused SyncApplier/ScreenFetch tests, the broader Android data tests and assembleDebug pass. AssistantMonitorMirrorTest (including all six lifecycle events and quoted prompt), AssistantMonitorGrainTest and all five package builds pass. The package compile reports existing managed-result and unreachable-code warnings. The updated APK was installed through ADB. With the phone unlocked, current tool names, downloaded thinking text and live Busy state were visible; scrolling responded. A complete historical transcript and a new turn after the desktop encoder change have not been verified.

Rebuild and restart Lazarus to load the desktop encoder fixes, then reconnect the phone. Pairing data was preserved. Unrelated working-tree changes and untracked Android resources were excluded.
