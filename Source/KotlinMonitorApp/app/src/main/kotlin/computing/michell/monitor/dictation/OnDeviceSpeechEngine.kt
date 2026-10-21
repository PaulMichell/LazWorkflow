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
  fun checkSupport(generation: Int): Boolean
  fun start(generation: Int): Boolean
  // False, or a thrown failure, must be reported by the caller. Do not treat either as success.
  fun stopListening(): Boolean
  fun cancel()
  fun destroy()
}

interface SpeechEngineListener {
  fun onReady(generation: Int)
  fun onBeginningOfSpeech(generation: Int)
  fun onEndOfSpeech(generation: Int)
  fun onPartial(generation: Int, text: String)
  fun onFinal(generation: Int, text: String)
  fun onError(generation: Int, code: Int)
  fun onReadyToListen(generation: Int)
  fun onLanguageBlocked(generation: Int, language: OnDeviceLanguage)
  fun onSupportFailed(generation: Int, code: Int)
}

class OnDeviceSpeechEngine(
  context: Context,
  private val listener: SpeechEngineListener
) : SpeechEngine {
  private val application = context.applicationContext
  private var recognizer: SpeechRecognizer? = null
  private var activeGeneration = 0
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

  override fun checkSupport(generation: Int): Boolean {
    if (!available() || generation <= 0) return false
    val current = recognizer ?: createRecognizer() ?: return false
    activeGeneration = generation
    return try {
      current.setRecognitionListener(listeningCallbacks(generation))
      if (Build.VERSION.SDK_INT < 33) {
        if (acceptSpeechCallback(activeGeneration, generation)) listener.onReadyToListen(generation)
        return true
      }
      Api33Support(
        current,
        recognitionIntent(),
        application.mainExecutor,
        listener,
        generation
      ) { activeGeneration }.start()
      true
    } catch (error: Exception) {
      if (activeGeneration == generation) activeGeneration = 0
      false
    }
  }

  override fun start(generation: Int): Boolean {
    if (!available() || generation <= 0) return false
    val current = recognizer ?: createRecognizer() ?: return false
    activeGeneration = generation
    return try {
      // A new listener closes over this generation. The previous listener cannot adopt it.
      current.setRecognitionListener(listeningCallbacks(generation))
      current.startListening(recognitionIntent())
      true
    } catch (error: Exception) {
      if (activeGeneration == generation) activeGeneration = 0
      try {
        current.cancel()
      } catch (cancelError: Exception) {
        // The service may already have ended.
      }
      false
    }
  }

  override fun stopListening(): Boolean {
    val current = recognizer ?: return stopListeningAccepted(false, false)
    return try {
      current.stopListening()
      stopListeningAccepted(true, false)
    } catch (error: Exception) {
      // A throw is not an accepted stop. The caller reports the false result.
      stopListeningAccepted(true, true)
    }
  }

  override fun cancel() {
    activeGeneration = 0
    val current = recognizer ?: return
    try {
      current.cancel()
    } catch (error: Exception) {
      // The service may already have ended.
    }
  }

  override fun destroy() {
    activeGeneration = 0
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

  private fun listeningCallbacks(generation: Int): RecognitionListener {
    return object : RecognitionListener {
      private fun forward(report: () -> Unit) {
        if (!acceptSpeechCallback(activeGeneration, generation)) return
        report()
      }

      override fun onReadyForSpeech(params: Bundle?) {
        forward { listener.onReady(generation) }
      }

      override fun onBeginningOfSpeech() {
        forward { listener.onBeginningOfSpeech(generation) }
      }

      override fun onRmsChanged(rmsdB: Float) {
      }

      override fun onBufferReceived(buffer: ByteArray?) {
      }

      override fun onEndOfSpeech() {
        forward { listener.onEndOfSpeech(generation) }
      }

      override fun onError(error: Int) {
        forward { listener.onError(generation, error) }
      }

      override fun onResults(results: Bundle?) {
        val text = firstHypothesis(results)
        forward { listener.onFinal(generation, text) }
      }

      override fun onPartialResults(partialResults: Bundle?) {
        val text = firstHypothesis(partialResults)
        forward { listener.onPartial(generation, text) }
      }

      override fun onEvent(eventType: Int, params: Bundle?) {
      }
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
  private val generation: Int,
  private val activeGeneration: () -> Int
) {
  fun start() {
    recognizer.checkRecognitionSupport(intent, executor, callback)
  }

  private fun open(): Boolean = acceptSpeechCallback(activeGeneration(), generation)

  private val callback = object : RecognitionSupportCallback {
    override fun onSupportResult(recognitionSupport: RecognitionSupport) {
      if (!open()) return
      when (onDeviceLanguage(
        names(recognitionSupport.installedOnDeviceLanguages),
        names(recognitionSupport.pendingOnDeviceLanguages),
        names(recognitionSupport.supportedOnDeviceLanguages),
        names(recognitionSupport.onlineLanguages)
      )) {
        OnDeviceLanguage.Installed -> listener.onReadyToListen(generation)
        OnDeviceLanguage.Downloading -> listener.onLanguageBlocked(generation, OnDeviceLanguage.Downloading)
        OnDeviceLanguage.NeedsDownload -> {
          try {
            recognizer.triggerModelDownload(intent)
          } catch (error: Exception) {
            // The system may already be asking the user to confirm the download.
          }
          listener.onLanguageBlocked(generation, OnDeviceLanguage.NeedsDownload)
        }
        OnDeviceLanguage.OnlineOnly -> listener.onLanguageBlocked(generation, OnDeviceLanguage.OnlineOnly)
        OnDeviceLanguage.Missing -> listener.onLanguageBlocked(generation, OnDeviceLanguage.Missing)
      }
    }

    override fun onError(error: Int) {
      if (!open()) return
      if (error == SpeechRecognizer.ERROR_CANNOT_CHECK_SUPPORT) listener.onReadyToListen(generation)
      else listener.onSupportFailed(generation, error)
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
