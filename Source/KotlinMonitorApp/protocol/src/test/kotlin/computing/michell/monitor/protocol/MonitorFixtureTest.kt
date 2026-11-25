package computing.michell.monitor.protocol

/* The phone accepts the shared fixtures and encodes the command requests.
   (c) 2026 Michell Computing. */

import java.io.File
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class MonitorFixtureTest {
  @Test
  fun everyFixtureIsJsonThePhoneCanRead() {
    val files = fixtureDir().listFiles { file -> file.extension == "json" }?.sortedBy { it.name }.orEmpty()
    assertTrue(files.isNotEmpty())
    for (file in files) {
      val text = file.readText().trim()
      assertTrue(file.name, monitorJsonAccepted(text))
      val root = parseMonitorJson(text)
      assertTrue(file.name, root != null)
      when (file.name) {
        "error-auth.json" -> assertEquals("auth", root!!.text("reason"))
        "error-unsaved-edits.json" -> assertEquals("unsaved_edits", root!!.text("reason"))
        "command-done.json" -> assertEquals("done", root!!.text("state"))
        "command-accepted.json" -> assertEquals("accepted", root!!.text("state"))
        "pulse-live.json" -> assertEquals("epoch-1", root!!.text("epoch"))
        "pulse-idle.json" -> assertEquals("null", text.substringAfter("\"live\":").substringBefore(','))
        "approval.json" -> assertEquals("run_build", root!!.text("tool_name"))
        "hello.json" -> assertEquals("epoch-1", root!!.text("epoch"))
        "request-send.json" -> assertEquals("send", root!!.text("type"))
      }
    }
  }

  @Test
  fun commandEncodersProduceTheRequestFixtures() {
    assertEquals(fixture("request-send.json"), monitorCommandRequest("cmd-send", "send", """{"text":"Hello","save_first":false}"""))
    assertEquals(fixture("request-steer.json"), monitorCommandRequest("cmd-steer", "steer", """{"text":"Stop there"}"""))
    assertEquals(fixture("request-stop.json"), monitorCommandRequest("cmd-stop", "stop", "{}"))
    assertEquals(fixture("request-approval.json"), monitorCommandRequest("cmd-approval", "approval", """{"tool_id":"tool-1","decision":"allow"}"""))
    assertEquals(fixture("request-set-mode.json"), monitorCommandRequest("cmd-mode", "set_mode", """{"mode":"build"}"""))
    assertEquals(fixture("request-new-conversation.json"), monitorCommandRequest("cmd-new", "new_conversation", "{}"))
    assertEquals(fixture("request-select-conversation.json"), monitorCommandRequest("cmd-select", "select_conversation", """{"id":"11111111-1111-1111-1111-111111111111"}"""))
    assertEquals(fixture("request-select-plan.json"), monitorCommandRequest("cmd-plan", "select_plan", """{"path":"Documents/Plan.md"}"""))
    assertEquals(fixture("request-new-plan.json"), monitorCommandRequest("cmd-new-plan", "new_plan", """{"title":"Plan"}"""))
    assertEquals(fixture("request-close-plan.json"), monitorCommandRequest("cmd-close", "close_plan", "{}"))
    assertEquals(fixture("request-run-plan.json"), monitorCommandRequest("cmd-run", "run_plan", """{"save_first":true}"""))
    assertEquals(fixture("request-stop-plan.json"), monitorCommandRequest("cmd-stop-plan", "stop_plan", "{}"))
    assertEquals(fixture("request-work-on-plan.json"), monitorCommandRequest("cmd-work", "work_on_plan", """{"section":2}"""))
    assertEquals(fixture("request-run-task.json"), monitorCommandRequest("cmd-task", "run_task", """{"task_id":"task-1","note":"","save_first":false}"""))
    assertEquals(fixture("request-insert-task.json"), monitorCommandRequest("cmd-insert", "insert_task", """{"task_id":"task-1","note":"Do this"}"""))
  }
}

private fun fixtureDir(): File {
  val start = File(System.getProperty("user.dir"))
  var dir = start
  repeat(8) {
    val found = File(dir, "Tests/Fixtures/Monitor/v4")
    if (found.isDirectory) return found
    dir = dir.parentFile ?: return found
  }
  return File(start, "Tests/Fixtures/Monitor/v4")
}

private fun fixture(name: String): String = File(fixtureDir(), name).readText().trim()
