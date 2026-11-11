package computing.michell.monitor.connection

/* One captured incident names the posture, and a queue admit is not a write (c) 2026 Michell Computing. */

import computing.michell.monitor.ui.settingsErrorText
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ConnectionDiagnosticTest {
  @Test
  fun aCaptureNamesEachPosture() {
    assertEquals(PostureIdle, incidentPosture(IncidentSnapshot(stopped = true, paused = true)))
    assertEquals(PostureIdle, incidentPosture(IncidentSnapshot(banner = IdleOfflineBanner, phase = LinkPhase.Disconnected.name)))
    assertEquals(PostureAwaitingUser, incidentPosture(IncidentSnapshot(
      phase = LinkPhase.Paused.name, terminalKind = "auth", banner = "auth", paused = true, armed = true
    )))
    assertEquals(PostureAwaitingUser, incidentPosture(IncidentSnapshot(
      phase = LinkPhase.Disconnected.name, terminalKind = "pin", banner = "TLS pin mismatch.", armed = true
    )))
    assertEquals(PostureAwaitingUser, incidentPosture(IncidentSnapshot(
      phase = LinkPhase.Paused.name, terminalKind = "revoked", banner = "revoked", paused = true, armed = true
    )))
    assertEquals(PostureRetrying, incidentPosture(IncidentSnapshot(
      phase = LinkPhase.Disconnected.name, banner = ReconnectingBanner, armed = true, reconnectable = true, workerExit = "WriteFailed"
    )))
    assertEquals(PostureOpening, incidentPosture(IncidentSnapshot(
      phase = LinkPhase.Connecting.name, opening = true, armed = true, reconnectable = true
    )))
    assertEquals(PostureOpening, incidentPosture(IncidentSnapshot(
      phase = LinkPhase.Live.name, ioBlocked = true, framesArriving = true, armed = true
    )))
    assertEquals(PostureHeartbeats, incidentPosture(IncidentSnapshot(
      phase = LinkPhase.Live.name,
      framesArriving = true,
      lastCommittedProgressAgeMs = HeartbeatWithoutProgressMs,
      lastReceivedFrameAgeMs = 1_000L,
      socketAgeMs = HeartbeatWithoutProgressMs,
      armed = true
    )))
    assertEquals(PostureLive, incidentPosture(IncidentSnapshot(
      phase = LinkPhase.Live.name,
      framesArriving = true,
      lastCommittedProgressAgeMs = 1_000L,
      lastReceivedFrameAgeMs = 1_000L,
      socketAgeMs = 2_000L,
      armed = true
    )))
  }

  @Test
  fun theRetryBannerKeepsTheOriginalFailure() {
    val kept = nextFailureReason("Connection refused.", LinkPhase.Disconnected, ReconnectingBanner, "")
    assertEquals("Connection refused.", kept)
    assertEquals("Connection refused.", settingsErrorText(ReconnectingBanner, kept))
    assertEquals("", nextFailureReason("Connection refused.", LinkPhase.Live, "", ""))
  }

  @Test
  fun aFormattedIncidentHasTheCorrelatedFieldsAndNoSecrets() {
    val snapshot = IncidentSnapshot(
      loopGeneration = 4,
      socketGeneration = 9,
      phase = LinkPhase.Disconnected.name,
      banner = ReconnectingBanner,
      transitionReason = "retry",
      failureReason = "WriteFailed",
      attemptCount = 3,
      nextRetryAtMs = 30_000L,
      nowMs = 18_000L,
      monitoringDemand = true,
      networkIdentity = "wifi:12",
      lastReceivedFrameAgeMs = 4_000L,
      lastCommittedProgressAgeMs = 20_000L,
      queueBytes = 128L,
      outboundBytes = 80L,
      inboundBytes = 48L,
      workerExit = "WriteFailed",
      terminalKind = "",
      armed = true,
      reconnectable = true
    )
    val text = redactDiagnostic(formatIncident(snapshot), listOf("session-token-value", "pairing-code", "auth-mac-value", "prompt body"))
    assertTrue(text.contains("posture=$PostureRetrying"))
    assertTrue(text.contains("loop=4"))
    assertTrue(text.contains("socket=9"))
    assertTrue(text.contains("reason=retry"))
    assertTrue(text.contains("attempts=3"))
    assertTrue(text.contains("retryMs=12000"))
    assertTrue(text.contains("demand=true"))
    assertTrue(text.contains("network=wifi:12"))
    assertTrue(text.contains("frameAge=4000"))
    assertTrue(text.contains("progressAge=20000"))
    assertTrue(text.contains("queue=128"))
    assertTrue(text.contains("exit=WriteFailed"))
    val leaked = redactDiagnostic(
      "failure=session-token-value hmac=abcdef0123456789 prompt=send the secret pairing code pairing-code",
      listOf("session-token-value", "pairing-code", "abcdef0123456789")
    )
    assertFalse(leaked.contains("session-token-value"))
    assertFalse(leaked.contains("pairing-code"))
    assertFalse(leaked.contains("abcdef0123456789"))
    assertFalse(leaked.contains("send the secret"))
    assertTrue(formatIncident(snapshot).contains("terminal=none"))
    assertFalse(formatIncident(snapshot).contains("prompt"))
  }

  @Test
  fun queueAdmissionIsNotASocketWriteOrAHostAcknowledgement() {
    val accepted = beginCatalogue("""{"v":3,"id":"m1","type":"stop"}""", 2, Any())
    assertEquals(CatalogueWrite.Queued, catalogueFromAdmission(accepted, true).outcome)
    assertEquals(CatalogueWrite.Failed, catalogueFromAdmission(accepted, false).outcome)
    assertEquals(CatalogueWrite.Written, catalogueFromSocketWrite(accepted, true).outcome)
    assertEquals(CatalogueWrite.Failed, catalogueFromSocketWrite(accepted, false).outcome)
    assertEquals(CatalogueWrite.Acknowledged, catalogueFromHostState("m1", 2, OutboxAccepted)!!.outcome)
    assertNull(catalogueFromHostState("m1", 2, "unknown"))
    assertFalse(isDurableHostAcknowledgement("open"))
  }

  @Test
  fun terminalFailuresAreNotAnAutomaticOrTransientRestart() {
    assertTrue(blocksAutomaticRecovery(true, "pin"))
    assertTrue(blocksAutomaticRecovery(false, "auth"))
    assertTrue(blocksAutomaticRecovery(false, "revoked"))
    assertTrue(blocksAutomaticRecovery(false, "disabled"))
    assertFalse(blocksAutomaticRecovery(false, ""))
    assertFalse(transientRestartAllowed(false, true, false, true, "10.0.0.8", LinkPhase.Disconnected))
    assertFalse(transientRestartAllowed(false, false, true, true, "10.0.0.8", LinkPhase.Paused))
    assertFalse(transientRestartAllowed(false, false, false, true, "10.0.0.8", LinkPhase.Live))
    assertTrue(transientRestartAllowed(false, false, false, true, "10.0.0.8", LinkPhase.Disconnected))
  }
}
