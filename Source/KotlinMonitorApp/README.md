# KotlinMonitorApp

The phone client for the Lazarus monitor. The IDE host is `LazAssistantMonitor`. The phone does not call a model provider and does not run tools.

## Protocol

Catalogue 3 is `Documents/MonitorProtocolV3.md`. The golden messages are `Tests/Fixtures/Monitor/`. Desktop and phone require catalogue 3; older experimental protocols and cache imports are unsupported. Rebuild both sides together. A saved TLS pin is 64 hex characters. An empty pin means endpoint-only trust. A nonempty pin that is not 64 hex characters is refused. Connect does not clear a saved pin.

## Pair a phone

After rebuilding and restarting Lazarus and installing the updated phone app:

1. Open Assistant > Remote Monitor, choose the LAN endpoint and select Enable.
2. Select Generate pairing code. The read-only field shows the ten-character code.
3. On the phone, open Settings, enter that host address and port, enter the code in Pairing code, and tap Connect within two minutes.

A code is single-use. Generate another if it expires or is rejected. Saved-token connections do not need a new code. Only loopback connections may pair without an armed code.

## Build and test

Java is the Android Studio JBR. From this directory:

```sh
JAVA_HOME=/home/paul/Projects/AndroidStudio/jbr ./gradlew --offline :protocol:test :app:testDebugUnitTest
```

The protocol module is a JVM library. It must not apply the Android plugin. Unit output for the IDE packages stays under `Lib/`, never under `Source/`.

## What the screen shows

The connection chip is Live, Syncing, Offline, Paired elsewhere, or Busy. Busy comes only from a state-channel status frame. The transcript is a lazy list keyed by turn id and block id. Cached conversations are per host, pinned rows first, then newest. Opening one while the link is down reads Room and does not open a socket. Send, Stop, and New stay off, with the offline-review explanation. Opening one while connected selects it and shows Syncing until the host snapshot arrives. Syncing keeps Send and New on. A tap while the socket is still down waits, and is sent when the link is live again.

## Not measured here

No phone was attached when this note was written. Pairing, airplane mode, killing the app, restarting the IDE, History switching, tool approval during a bulk transfer, and offline review of three conversations still need a device. The host harness numbers are in `Documents/MonitorLinkBaseline.md`.
