package computing.michell.monitor.dictation

/* On-device speech engine for the monitor prompt (c) 2026 Michell Computing. */

import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer

interface SpeechEngine {
  fun available(): Boolean
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
}

class OnDeviceSpeechEngine(
  context: Context,
  private val listener: SpeechEngineListener
) : SpeechEngine {
  private val application = context.applicationContext
  private var recognizer: SpeechRecognizer? = null
  private var accepting = false
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
    val current = recognizer ?: return
    try {
      current.cancel()
    } catch (error: Exception) {
      // The service may already have ended.
    }
  }

  override fun destroy() {
    accepting = false
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

private fun firstHypothesis(results: Bundle?): String {
  val heard = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION) ?: return ""
  if (heard.isEmpty()) return ""
  return heard[0].orEmpty()
}
