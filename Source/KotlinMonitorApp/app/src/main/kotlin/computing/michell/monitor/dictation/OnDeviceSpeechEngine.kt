package computing.michell.monitor.dictation

/* On-device speech engine for the monitor prompt (c) 2026 Michell Computing. */

import android.annotation.SuppressLint
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognitionSupport
import android.speech.RecognitionSupportCallback
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

interface SpeechEngine {
  fun available(): Boolean
  fun checkSupport(): Boolean
  fun start(): Boolean
  fun stopListening()
  fun cancel()
  fun destroy()
}

interface SpeechEngineListener {
  fun onReady()
  fun onBeginningOfSpeech()
  fun onEndOfSpeech()
  fun onPartial(text: String)
  fun onFinal(text: String)
  fun onError(code: Int)
  fun onReadyToListen()
  fun onLanguageBlocked(language: OnDeviceLanguage)
  fun onSupportFailed(code: Int)
}

class OnDeviceSpeechEngine(
  context: Context,
  private val listener: SpeechEngineListener
) : SpeechEngine {
  private val application = context.applicationContext
  private var recognizer: SpeechRecognizer? = null
  private var accepting = false
  private var supportOpen = false
  private var unavailable = false

  override fun available(): Boolean {
    if (unavailable) return false
    if (Build.VERSION.SDK_INT < 31) return false
    return try {
      SpeechRecognizer.isOnDeviceRecognitionAvailable(application)
    } catch (error: Exception) {
      false
    }
  }

  override fun checkSupport(): Boolean {
    if (!available()) return false
    val current = recognizer ?: createRecognizer() ?: return false
    supportOpen = true
    return try {
      current.setRecognitionListener(callbacks)
      if (Build.VERSION.SDK_INT < 33) {
        supportOpen = false
        listener.onReadyToListen()
        return true
      }
      Api33Support(current, recognitionIntent(), application.mainExecutor, listener) { supportOpen }.start()
      true
    } catch (error: Exception) {
      supportOpen = false
      false
    }
  }

  override fun start(): Boolean {
    if (!available()) return false
    val current = recognizer ?: createRecognizer() ?: return false
    accepting = true
    return try {
      current.setRecognitionListener(callbacks)
      current.startListening(recognitionIntent())
      true
    } catch (error: Exception) {
      accepting = false
      try {
        current.cancel()
      } catch (cancelError: Exception) {
        // The service may already have ended.
      }
      false
    }
  }

  override fun stopListening() {
    val current = recognizer ?: return
    try {
      current.stopListening()
    } catch (error: Exception) {
      // The service may already have ended.
    }
  }

  override fun cancel() {
    accepting = false
    supportOpen = false
    val current = recognizer ?: return
    try {
      current.cancel()
    } catch (error: Exception) {
      // The service may already have ended.
    }
  }

  override fun destroy() {
    accepting = false
    supportOpen = false
    val current = recognizer
    recognizer = null
    if (current == null) return
    try {
      current.cancel()
    } catch (error: Exception) {
      // The service may already have ended.
    }
    try {
      current.setRecognitionListener(null)
    } catch (error: Exception) {
      // The service may already have ended.
    }
    try {
      current.destroy()
    } catch (error: Exception) {
      // A second teardown must not throw.
    }
  }

  // On-device factory only. A failure is unavailable. Never call createSpeechRecognizer.
  private fun createRecognizer(): SpeechRecognizer? {
    if (Build.VERSION.SDK_INT < 31) return null
    recognizer?.let { return it }
    return try {
      val created = SpeechRecognizer.createOnDeviceSpeechRecognizer(application)
      recognizer = created
      created
    } catch (error: Exception) {
      unavailable = true
      null
    }
  }

  private fun recognitionIntent(): Intent {
    val intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH)
    intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
    intent.putExtra(RecognizerIntent.EXTRA_LANGUAGE, "en-GB")
    intent.putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
    intent.putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, 1)
    return intent
  }

  private fun forward(report: () -> Unit) {
    if (!accepting) return
    report()
  }

  private val callbacks = object : RecognitionListener {
    override fun onReadyForSpeech(params: Bundle?) {
      forward { listener.onReady() }
    }

    override fun onBeginningOfSpeech() {
      forward { listener.onBeginningOfSpeech() }
    }

    override fun onRmsChanged(rmsdB: Float) {
    }

    override fun onBufferReceived(buffer: ByteArray?) {
    }

    override fun onEndOfSpeech() {
      forward { listener.onEndOfSpeech() }
    }

    override fun onError(error: Int) {
      forward { listener.onError(error) }
    }

    override fun onResults(results: Bundle?) {
      val text = firstHypothesis(results)
      forward { listener.onFinal(text) }
    }

    override fun onPartialResults(partialResults: Bundle?) {
      val text = firstHypothesis(partialResults)
      forward { listener.onPartial(text) }
    }

    override fun onEvent(eventType: Int, params: Bundle?) {
    }
  }
}

// Loaded only on API 33 and later. RecognitionSupportCallback does not exist before that.
@SuppressLint("NewApi")
private class Api33Support(
  private val recognizer: SpeechRecognizer,
  private val intent: Intent,
  private val executor: java.util.concurrent.Executor,
  private val listener: SpeechEngineListener,
  private val open: () -> Boolean
) {
  fun start() {
    recognizer.checkRecognitionSupport(intent, executor, callback)
  }

  private val callback = object : RecognitionSupportCallback {
    override fun onSupportResult(recognitionSupport: RecognitionSupport) {
      if (!open()) return
      when (onDeviceLanguage(
        names(recognitionSupport.installedOnDeviceLanguages),
        names(recognitionSupport.pendingOnDeviceLanguages),
        names(recognitionSupport.supportedOnDeviceLanguages),
        names(recognitionSupport.onlineLanguages)
      )) {
        OnDeviceLanguage.Installed -> listener.onReadyToListen()
        OnDeviceLanguage.Downloading -> listener.onLanguageBlocked(OnDeviceLanguage.Downloading)
        OnDeviceLanguage.NeedsDownload -> {
          try {
            recognizer.triggerModelDownload(intent)
          } catch (error: Exception) {
            // The system may already be asking the user to confirm the download.
          }
          listener.onLanguageBlocked(OnDeviceLanguage.NeedsDownload)
        }
        OnDeviceLanguage.OnlineOnly -> listener.onLanguageBlocked(OnDeviceLanguage.OnlineOnly)
        OnDeviceLanguage.Missing -> listener.onLanguageBlocked(OnDeviceLanguage.Missing)
      }
    }

    override fun onError(error: Int) {
      if (!open()) return
      if (error == SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT) listener.onReadyToListen()
      else listener.onSupportFailed(error)
    }
  }
}

private fun names(languages: List<String>?): List<String> {
  return languages?.filter { it.isNotEmpty() } ?: emptyList()
}

private fun firstHypothesis(results: Bundle?): String {
  val heard = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION) ?: return ""
  if (heard.isEmpty()) return ""
  return heard[0].orEmpty()
}
