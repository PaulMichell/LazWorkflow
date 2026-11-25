package computing.michell.monitor.ui

/* Dictation, draft and display preferences for the shell (c) 2026 Michell Computing.

   Catalogue 3 is gone. This still starts on-device dictation and remembers the
   Settings toggles. It does not open a socket. */

import android.Manifest
import android.content.Context
import android.content.SharedPreferences
import android.content.pm.PackageManager
import android.speech.SpeechRecognizer
import computing.michell.monitor.dictation.DictationAudioMessage
import computing.michell.monitor.dictation.DictationBusyMessage
import computing.michell.monitor.dictation.DictationEvent
import computing.michell.monitor.dictation.DictationFailedMessage
import computing.michell.monitor.dictation.DictationFinalWatch
import computing.michell.monitor.dictation.DictationLanguageMissingMessage
import computing.michell.monitor.dictation.DictationLanguageUnsupportedMessage
import computing.michell.monitor.dictation.DictationModelDownloadMessage
import computing.michell.monitor.dictation.DictationModelDownloadingMessage
import computing.michell.monitor.dictation.DictationNoSpeechDetectedMessage
import computing.michell.monitor.dictation.DictationNoSpeechMessage
import computing.michell.monitor.dictation.DictationOnDeviceFailedMessage
import computing.michell.monitor.dictation.DictationPhase
import computing.michell.monitor.dictation.DictationState
import computing.michell.monitor.dictation.DictationStep
import computing.michell.monitor.dictation.DictationStopFollowUp
import computing.michell.monitor.dictation.DictationStoppedMessage
import computing.michell.monitor.dictation.DictationUnavailableMessage
import computing.michell.monitor.dictation.OnDeviceLanguage
import computing.michell.monitor.dictation.OnDeviceSpeechEngine
import computing.michell.monitor.dictation.SpeechEngine
import computing.michell.monitor.dictation.SpeechEngineListener
import computing.michell.monitor.dictation.acceptSpeechCallback
import computing.michell.monitor.dictation.dictationStopFollowUp
import computing.michell.monitor.dictation.reduceDictation
import computing.michell.monitor.ui.model.MonitorUi
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

const val MicrophoneRequiredMessage = "Microphone permission is required."
const val MicrophoneSettingsMessage = "Microphone permission is off. System settings can enable it."

enum class MicrophoneAsk {
  Start,
  RequestPermission,
  ExplainSettings
}

fun microphoneAsk(granted: Boolean, asked: Boolean, showRationale: Boolean): MicrophoneAsk {
  if (granted) return MicrophoneAsk.Start
  if (asked && !showRationale) return MicrophoneAsk.ExplainSettings
  return MicrophoneAsk.RequestPermission
}

class PromptController(
  private val context: Context,
  private val scope: CoroutineScope,
  private val preferences: SharedPreferences,
  private val draftOf: () -> String,
  private val storeDraft: (String) -> Unit
) {
  private val permissionRequestState = MutableStateFlow(false)
  val dictationPermissionRequest: StateFlow<Boolean> = permissionRequestState.asStateFlow()
  val dictationState = MutableStateFlow(DictationState())
  val dictation: StateFlow<DictationState> = dictationState.asStateFlow()
  private var pendingSelectionStart = 0
  private var pendingSelectionEnd = 0
  private var callbackSession = 0
  private var supportGeneration = 0
  private var recognitionSupported = true
  private var supportPending = false
  private val engineListener = object : SpeechEngineListener {
    override fun onReady(generation: Int) {}
    override fun onBeginningOfSpeech(generation: Int) {}
    override fun onEndOfSpeech(generation: Int) {}
    override fun onPartial(generation: Int, text: String) { onDictationPartial(generation, text) }
    override fun onFinal(generation: Int, text: String) { onDictationFinal(generation, text) }
    override fun onError(generation: Int, code: Int) { onDictationError(generation, code) }
    override fun onReadyToListen(generation: Int) { onSupportReady(generation) }
    override fun onLanguageBlocked(generation: Int, language: OnDeviceLanguage) { onSupportBlocked(generation, language) }
    override fun onSupportFailed(generation: Int, code: Int) { onSupportError(generation, code) }
  }
  private val engine: SpeechEngine = OnDeviceSpeechEngine(context, engineListener)
  private val finalWatch = DictationFinalWatch(scope, onExpired = ::abandonAwaitingFinal)

  fun thinking(): Boolean = preferences.getBoolean(DisplayThinkingKey, true)

  fun tools(): Boolean = preferences.getBoolean(DisplayToolsKey, true)

  fun setThinking(value: Boolean) {
    preferences.edit().putBoolean(DisplayThinkingKey, value).apply()
  }

  fun setTools(value: Boolean) {
    preferences.edit().putBoolean(DisplayToolsKey, value).apply()
  }

  fun conversationCapText(): String = preferences.getInt(ConversationCapKey, 50).toString()

  fun imageBudgetText(): String = preferences.getInt(ImageBudgetKey, 128).toString()

  fun setConversationCapText(text: String) {
    val value = text.toIntOrNull() ?: return
    preferences.edit().putInt(ConversationCapKey, value).apply()
  }

  fun setImageBudgetText(text: String) {
    val value = text.toIntOrNull() ?: return
    preferences.edit().putInt(ImageBudgetKey, value).apply()
  }

  fun changePrompt(text: String, selectionStart: Int, selectionEnd: Int, pendingPrompt: String) {
    if (dictationState.value.phase != DictationPhase.Idle) {
      editPrompt(text, selectionStart, selectionEnd)
      return
    }
    if (pendingPrompt.isNotEmpty() && draftOf().isEmpty() && text.trim() == pendingPrompt) {
      dictationState.value = dictationState.value.copy(selectionStart = 0, selectionEnd = 0)
      return
    }
    if (text != draftOf()) storeDraft(text)
    val length = text.length
    dictationState.value = dictationState.value.copy(
      selectionStart = selectionStart.coerceIn(0, length),
      selectionEnd = selectionEnd.coerceIn(0, length)
    )
  }

  fun toggleDictationOn(selectionStart: Int, selectionEnd: Int, showRationale: Boolean) {
    if (dictationState.value.phase != DictationPhase.Idle || supportPending) return
    if (!recognitionSupported || !engine.available()) {
      dictationState.value = dictationState.value.copy(statusMessage = DictationUnavailableMessage, available = false)
      return
    }
    if (!microphoneGranted()) {
      when (microphoneAsk(false, microphoneAsked(), showRationale)) {
        MicrophoneAsk.ExplainSettings -> {
          permissionRequestState.value = false
          dictationState.value = dictationState.value.copy(statusMessage = MicrophoneSettingsMessage)
        }
        MicrophoneAsk.RequestPermission -> {
          pendingSelectionStart = selectionStart
          pendingSelectionEnd = selectionEnd
          permissionRequestState.value = true
        }
        MicrophoneAsk.Start -> beginDictation(selectionStart, selectionEnd)
      }
      return
    }
    beginDictation(selectionStart, selectionEnd)
  }

  fun consumeDictationPermissionRequest() {
    permissionRequestState.value = false
  }

  fun toggleDictationOff() {
    val state = dictationState.value
    if (state.phase != DictationPhase.Listening) return
    val sessionId = state.sessionId
    val step = applyDictation(DictationEvent.ToggleOff(sessionId))
    if (step.state.phase != DictationPhase.AwaitingFinal) return
    var thrown = false
    val accepted = try {
      engine.stopListening()
    } catch (error: Exception) {
      thrown = true
      false
    }
    when (dictationStopFollowUp(step.state.phase, accepted, thrown)) {
      DictationStopFollowUp.ArmDeadline -> finalWatch.arm(sessionId)
      DictationStopFollowUp.ReportFailure -> abandonAwaitingFinal(sessionId)
      DictationStopFollowUp.Idle -> {}
    }
  }

  fun dictationPermission(granted: Boolean) {
    permissionRequestState.value = false
    rememberMicrophoneAsked()
    if (!granted) {
      dictationState.value = dictationState.value.copy(statusMessage = MicrophoneRequiredMessage)
      return
    }
    beginDictation(pendingSelectionStart, pendingSelectionEnd)
  }

  fun leave() {
    supportPending = false
    supportGeneration = 0
    finalWatch.cancel()
    applyDictation(DictationEvent.LeaveScreen)
    callbackSession = 0
    engine.cancel()
  }

  private fun editPrompt(text: String, selectionStart: Int, selectionEnd: Int) {
    val before = dictationState.value
    val step = reduceDictation(before, text, DictationEvent.Edited(selectionStart, selectionEnd))
    dictationState.value = step.state
    storeDraft(step.draft)
    if (before.phase != DictationPhase.Idle && step.state.phase == DictationPhase.Idle) {
      callbackSession = 0
      supportGeneration = 0
      finalWatch.cancel()
      engine.cancel()
    }
  }

  private fun onDictationPartial(generation: Int, text: String) {
    if (!acceptSpeechCallback(callbackSession, generation)) return
    val before = dictationState.value
    releaseIfClosed(before, applyDictation(DictationEvent.Partial(generation, text)))
  }

  private fun onDictationFinal(generation: Int, text: String) {
    if (!acceptSpeechCallback(callbackSession, generation)) return
    val before = dictationState.value
    val step = applyDictation(DictationEvent.Final(generation, text))
    if (step.state.phase == DictationPhase.Idle) finalWatch.cancel()
    releaseIfClosed(before, step)
  }

  private fun onDictationError(generation: Int, code: Int) {
    if (!acceptSpeechCallback(callbackSession, generation)) return
    finalWatch.cancel()
    if (code == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED) {
      recognitionSupported = false
      dictationState.value = dictationState.value.copy(available = false)
    }
    val before = dictationState.value
    val step = applyDictation(DictationEvent.Failure(generation, speechFailureMessage(code)))
    callbackSession = 0
    if (code == SpeechRecognizer.ERROR_CLIENT) engine.destroy()
    else releaseIfClosed(before, step)
  }

  private fun onSupportReady(generation: Int) {
    if (!acceptSpeechCallback(supportGeneration, generation) || !supportPending) return
    supportPending = false
    supportGeneration = 0
    startListeningSession(pendingSelectionStart, pendingSelectionEnd)
  }

  private fun onSupportBlocked(generation: Int, language: OnDeviceLanguage) {
    if (!acceptSpeechCallback(supportGeneration, generation) || !supportPending) return
    supportPending = false
    supportGeneration = 0
    when (language) {
      OnDeviceLanguage.Downloading -> showSpeechStatus(DictationModelDownloadingMessage, false)
      OnDeviceLanguage.NeedsDownload -> showSpeechStatus(DictationModelDownloadMessage, false)
      OnDeviceLanguage.OnlineOnly, OnDeviceLanguage.Missing -> {
        recognitionSupported = false
        showSpeechStatus(DictationLanguageUnsupportedMessage, true)
      }
      OnDeviceLanguage.Installed -> startListeningSession(pendingSelectionStart, pendingSelectionEnd)
    }
  }

  private fun onSupportError(generation: Int, code: Int) {
    if (!acceptSpeechCallback(supportGeneration, generation) || !supportPending) return
    supportPending = false
    supportGeneration = 0
    if (code == SpeechRecognizer.ERROR_CLIENT) engine.destroy()
    val unavailable = code == SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED
    if (unavailable) recognitionSupported = false
    showSpeechStatus(speechFailureMessage(code), unavailable)
  }

  private fun showSpeechStatus(message: String, unavailable: Boolean) {
    dictationState.value = dictationState.value.copy(
      statusMessage = message,
      available = if (unavailable) false else dictationState.value.available
    )
  }

  private fun applyDictation(event: DictationEvent): DictationStep {
    val step = reduceDictation(dictationState.value, draftOf(), event)
    dictationState.value = step.state
    storeDraft(step.draft)
    return step
  }

  private fun releaseIfClosed(before: computing.michell.monitor.dictation.DictationState, step: DictationStep) {
    if (before.phase == DictationPhase.Idle || step.state.phase != DictationPhase.Idle) return
    callbackSession = 0
    supportGeneration = 0
    finalWatch.cancel()
    engine.cancel()
  }

  private fun abandonAwaitingFinal(sessionId: Int) {
    val state = dictationState.value
    if (state.phase != DictationPhase.AwaitingFinal || state.sessionId != sessionId) return
    finalWatch.cancel()
    callbackSession = 0
    supportGeneration = 0
    engine.cancel()
    applyDictation(DictationEvent.Expired(sessionId))
  }

  private fun beginDictation(selectionStart: Int, selectionEnd: Int) {
    if (supportPending || dictationState.value.phase != DictationPhase.Idle) return
    permissionRequestState.value = false
    pendingSelectionStart = selectionStart
    pendingSelectionEnd = selectionEnd
    supportGeneration = dictationState.value.sessionId + 1
    supportPending = true
    if (engine.checkSupport(supportGeneration)) return
    supportGeneration = 0
    supportPending = false
    showSpeechStatus(DictationUnavailableMessage, true)
  }

  private fun startListeningSession(selectionStart: Int, selectionEnd: Int) {
    finalWatch.cancel()
    val step = applyDictation(DictationEvent.Start(selectionStart, selectionEnd))
    if (!step.state.listening) return
    callbackSession = step.state.sessionId
    if (engine.start(callbackSession)) return
    callbackSession = 0
    dictationState.value = dictationState.value.copy(available = false)
    applyDictation(DictationEvent.Failure(step.state.sessionId, DictationUnavailableMessage))
    engine.cancel()
  }

  private fun microphoneGranted(): Boolean {
    return context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED
  }

  private fun microphoneAsked(): Boolean = preferences.getBoolean(DictationPermissionAskedKey, false)

  private fun rememberMicrophoneAsked() {
    if (microphoneAsked()) return
    preferences.edit().putBoolean(DictationPermissionAskedKey, true).commit()
  }
}

private fun speechFailureMessage(code: Int): String {
  return when (code) {
    SpeechRecognizer.ERROR_INSUFFICIENT_PERMISSIONS -> MicrophoneRequiredMessage
    SpeechRecognizer.ERROR_SPEECH_TIMEOUT -> DictationNoSpeechDetectedMessage
    SpeechRecognizer.ERROR_NO_MATCH -> DictationNoSpeechMessage
    SpeechRecognizer.ERROR_RECOGNIZER_BUSY -> DictationBusyMessage
    SpeechRecognizer.ERROR_AUDIO -> DictationAudioMessage
    SpeechRecognizer.ERROR_LANGUAGE_UNAVAILABLE -> DictationLanguageMissingMessage
    SpeechRecognizer.ERROR_LANGUAGE_NOT_SUPPORTED -> DictationLanguageUnsupportedMessage
    SpeechRecognizer.ERROR_NETWORK, SpeechRecognizer.ERROR_NETWORK_TIMEOUT, SpeechRecognizer.ERROR_SERVER ->
      DictationOnDeviceFailedMessage
    SpeechRecognizer.ERROR_CLIENT, SpeechRecognizer.ERROR_SERVER_DISCONNECTED -> DictationStoppedMessage
    else -> DictationFailedMessage
  }
}

private const val DisplayThinkingKey = "thinking"
private const val DisplayToolsKey = "tools"
private const val ConversationCapKey = "conversation-cap"
private const val ImageBudgetKey = "image-budget-mib"
private const val DictationPermissionAskedKey = "dictation-asked"
