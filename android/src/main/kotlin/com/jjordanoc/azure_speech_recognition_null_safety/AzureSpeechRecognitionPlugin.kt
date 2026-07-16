package com.jjordanoc.azure_speech_recognition_null_safety

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.microsoft.cognitiveservices.speech.PronunciationAssessmentConfig
import com.microsoft.cognitiveservices.speech.PronunciationAssessmentGradingSystem
import com.microsoft.cognitiveservices.speech.PronunciationAssessmentGranularity
import com.microsoft.cognitiveservices.speech.PropertyId
import com.microsoft.cognitiveservices.speech.ResultReason
import com.microsoft.cognitiveservices.speech.SpeechConfig
import com.microsoft.cognitiveservices.speech.SpeechRecognitionResult
import com.microsoft.cognitiveservices.speech.SpeechRecognizer
import com.microsoft.cognitiveservices.speech.audio.AudioConfig
import com.microsoft.cognitiveservices.speech.audio.PullAudioInputStream
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors
import java.util.concurrent.Future


/** AzureSpeechRecognitionPlugin */
class AzureSpeechRecognitionPlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var azureChannel: MethodChannel
    private var handler: Handler = Handler(Looper.getMainLooper())
    var continuousListeningStarted: Boolean = false
    private var continuousListeningStarting: Boolean = false
    private var stopRequestedWhileStarting: Boolean = false
    private var pendingStartResult: Result? = null
    private var pendingStopResult: Result? = null
    lateinit var reco: SpeechRecognizer
    lateinit var task_global: Future<SpeechRecognitionResult>
    private var microphoneStream: MicrophoneStream? = null
    private var isDetached = false

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        isDetached = false
        azureChannel = MethodChannel(
            flutterPluginBinding.binaryMessenger, "azure_speech_recognition"
        )
        azureChannel.setMethodCallHandler(this)

    }


    override fun onMethodCall(call: MethodCall, result: Result) {
        val speechSubscriptionKey: String = call.argument("subscriptionKey") ?: ""
        val serviceRegion: String = call.argument("region") ?: ""
        val lang: String = call.argument("language") ?: ""
        val timeoutMs: String = call.argument("timeout") ?: ""
        val referenceText: String = call.argument("referenceText") ?: ""
        val phonemeAlphabet: String = call.argument("phonemeAlphabet") ?: "IPA"
        val granularityString: String = call.argument("granularity") ?: "phoneme"
        val enableMiscue: Boolean = call.argument("enableMiscue") ?: false
        val nBestPhonemeCount: Int? = call.argument("nBestPhonemeCount")
        val granularity: PronunciationAssessmentGranularity
        when (granularityString) {
            "text" -> {
                granularity = PronunciationAssessmentGranularity.FullText
            }

            "word" -> {
                granularity = PronunciationAssessmentGranularity.Word
            }

            else -> {
                granularity = PronunciationAssessmentGranularity.Phoneme
            }
        }
        when (call.method) {
            "simpleVoice" -> {
                simpleSpeechRecognition(speechSubscriptionKey, serviceRegion, lang, timeoutMs)
                result.success(true)
            }

            "simpleVoiceWithAssessment" -> {
                simpleSpeechRecognitionWithAssessment(
                    referenceText,
                    phonemeAlphabet,
                    granularity,
                    enableMiscue,
                    speechSubscriptionKey,
                    serviceRegion,
                    lang,
                    timeoutMs,
                    nBestPhonemeCount,
                )
                result.success(true)
            }

            "isContinuousRecognitionOn" -> {
                result.success(continuousListeningStarted)
            }

            "continuousStream" -> {
                micStreamContinuously(speechSubscriptionKey, serviceRegion, lang)
                result.success(true)
            }

            "startContinuousStream" -> {
                startContinuousMicStream(speechSubscriptionKey, serviceRegion, lang, result)
            }

            "continuousStreamWithAssessment" -> {
                micStreamContinuouslyWithAssessment(
                    referenceText,
                    phonemeAlphabet,
                    granularity,
                    enableMiscue,
                    speechSubscriptionKey,
                    serviceRegion,
                    lang,
                    nBestPhonemeCount,
                )
                result.success(true)
            }

            "stopContinuousStream" -> {
                stopContinuousMicStream(result)
            }

            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        isDetached = true
        cleanupContinuousRecognition()
        s_executorService.shutdownNow()
        azureChannel.setMethodCallHandler(null)
    }

    private fun simpleSpeechRecognition(
        speechSubscriptionKey: String, serviceRegion: String, lang: String, timeoutMs: String
    ) {
        val logTag: String = "simpleVoice"
        try {

            val audioInput: AudioConfig = AudioConfig.fromDefaultMicrophoneInput()

            val config: SpeechConfig =
                SpeechConfig.fromSubscription(speechSubscriptionKey, serviceRegion)

            config.speechRecognitionLanguage = lang
            config.setProperty(PropertyId.Speech_SegmentationSilenceTimeoutMs, timeoutMs)

            val reco: SpeechRecognizer = SpeechRecognizer(config, audioInput)

            val task: Future<SpeechRecognitionResult> = reco.recognizeOnceAsync()

            task_global = task

            invokeMethod("speech.onRecognitionStarted", null)

            reco.recognizing.addEventListener { _, speechRecognitionResultEventArgs ->
                val s = speechRecognitionResultEventArgs.result.text
                Log.i(logTag, "Intermediate result received: " + s)
                if (task_global === task) {
                    invokeMethod("speech.onSpeech", s)
                }
            }

            setOnTaskCompletedListener(task) { result ->
                val s = result.text
                Log.i(logTag, "Recognizer returned: " + s)
                if (task_global === task) {
                    if (result.reason == ResultReason.RecognizedSpeech) {
                        invokeMethod("speech.onFinalResponse", s)
                    } else {
                        invokeMethod("speech.onFinalResponse", "")
                    }
                }
                reco.close()
            }

        } catch (exec: Exception) {
            Log.i(logTag, "ERROR")
            assert(false)
            invokeMethod("speech.onException", "Exception: " + exec.message)

        }
    }

    private fun simpleSpeechRecognitionWithAssessment(
        referenceText: String,
        phonemeAlphabet: String,
        granularity: PronunciationAssessmentGranularity,
        enableMiscue: Boolean,
        speechSubscriptionKey: String,
        serviceRegion: String,
        lang: String,
        timeoutMs: String,
        nBestPhonemeCount: Int?,
    ) {
        val logTag = "simpleVoiceWithAssessment"

        try {

            val audioInput: AudioConfig = AudioConfig.fromDefaultMicrophoneInput()

            val config: SpeechConfig =
                SpeechConfig.fromSubscription(speechSubscriptionKey, serviceRegion)

            config.speechRecognitionLanguage = lang
            config.setProperty(PropertyId.Speech_SegmentationSilenceTimeoutMs, timeoutMs)

            val pronunciationAssessmentConfig =
                PronunciationAssessmentConfig(
                    referenceText,
                    PronunciationAssessmentGradingSystem.HundredMark,
                    granularity,
                    enableMiscue
                )
            pronunciationAssessmentConfig.setPhonemeAlphabet(phonemeAlphabet)

            if (nBestPhonemeCount != null) {
                pronunciationAssessmentConfig.setNBestPhonemeCount(nBestPhonemeCount)
            }

            Log.i(logTag, pronunciationAssessmentConfig.toJson())

            val reco = SpeechRecognizer(config, audioInput)

            pronunciationAssessmentConfig.applyTo(reco)

            val task: Future<SpeechRecognitionResult> = reco.recognizeOnceAsync()

            task_global = task

            invokeMethod("speech.onRecognitionStarted", null)

            reco.recognizing.addEventListener { _, speechRecognitionResultEventArgs ->
                val s = speechRecognitionResultEventArgs.result.text
                Log.i(logTag, "Intermediate result received: " + s)
                if (task_global === task) {
                    invokeMethod("speech.onSpeech", s)
                }
            }

            setOnTaskCompletedListener(task) { result ->
                val s = result.text
                val pronunciationAssessmentResultJson =
                    result.properties.getProperty(PropertyId.SpeechServiceResponse_JsonResult)
                Log.i(logTag, "Final result: $s\nReason: ${result.reason}")
                Log.i(
                    logTag, "pronunciationAssessmentResultJson: $pronunciationAssessmentResultJson"
                )
                if (task_global === task) {
                    if (result.reason == ResultReason.RecognizedSpeech) {
                        invokeMethod("speech.onFinalResponse", s)
                        invokeMethod("speech.onAssessmentResult", pronunciationAssessmentResultJson)
                    } else {
                        invokeMethod("speech.onFinalResponse", "")
                        invokeMethod("speech.onAssessmentResult", "")
                    }
                }
                reco.close()
            }

        } catch (exec: Exception) {
            Log.i(logTag, "ERROR")
            assert(false)
            invokeMethod("speech.onException", "Exception: " + exec.message)

        }
    }

    private fun micStreamContinuously(
        speechSubscriptionKey: String, serviceRegion: String, lang: String
    ) {
        val logTag: String = "micStreamContinuous"

        Log.i(logTag, "Continuous recognition started: $continuousListeningStarted")

        if (continuousListeningStarted) {
            val _task1 = reco.stopContinuousRecognitionAsync()

            setOnTaskCompletedListener(_task1) { result ->
                Log.i(logTag, "Continuous recognition stopped.")
                continuousListeningStarted = false
                invokeMethod("speech.onRecognitionStopped", null)
                reco.close()
                closeMicrophoneStream()
            }
            return
        }

        startContinuousMicStream(speechSubscriptionKey, serviceRegion, lang)
    }

    private fun startContinuousMicStream(
        speechSubscriptionKey: String,
        serviceRegion: String,
        lang: String,
        flutterResult: Result? = null,
    ) {
        val logTag = "micStreamContinuous"
        if (continuousListeningStarted) {
            flutterResult?.success(true)
            return
        }
        if (continuousListeningStarting) {
            flutterResult?.error(
                "azure_start_in_progress",
                "Continuous recognition is already starting",
                null,
            )
            return
        }
        continuousListeningStarting = true
        pendingStartResult = flutterResult
        try {
            val audioConfig = createMicrophoneAudioConfig()

            val config: SpeechConfig =
                SpeechConfig.fromSubscription(speechSubscriptionKey, serviceRegion)

            config.speechRecognitionLanguage = lang

            reco = SpeechRecognizer(config, audioConfig)

            reco.recognizing.addEventListener { _, speechRecognitionResultEventArgs ->
                val s = speechRecognitionResultEventArgs.result.text
                Log.i(logTag, "Intermediate result received: $s")
                invokeMethod("speech.onSpeech", s)
            }

            reco.recognized.addEventListener { _, speechRecognitionResultEventArgs ->
                val s = speechRecognitionResultEventArgs.result.text
                Log.i(logTag, "Final result received: $s")
                invokeMethod("speech.onFinalResponse", s)
            }

            val _task2 = reco.startContinuousRecognitionAsync()

            setOnTaskCompletedListenerWithFailure(
                _task2,
                {
                    continuousListeningStarting = false
                    continuousListeningStarted = true
                    pendingStartResult?.success(true)
                    pendingStartResult = null
                    invokeMethod("speech.onRecognitionStarted", null)
                    if (stopRequestedWhileStarting) {
                        stopRequestedWhileStarting = false
                        val result = pendingStopResult
                        pendingStopResult = null
                        stopContinuousMicStream(result)
                    }
                },
                { error -> handleContinuousStartFailure(error) },
            )
        } catch (exec: Exception) {
            handleContinuousStartFailure(exec)
        }
    }

    private fun stopContinuousMicStream(flutterResult: Result?) {
        val logTag: String = "stopContinuousMicStream"

        Log.i(logTag, "Continuous recognition started: $continuousListeningStarted")

        if (continuousListeningStarting) {
            if (pendingStopResult != null) {
                flutterResult?.success(true)
                return
            }
            stopRequestedWhileStarting = true
            pendingStopResult = flutterResult
            return
        }

        if (continuousListeningStarted) {
            val stopTask = try {
                reco.stopContinuousRecognitionAsync()
            } catch (error: Throwable) {
                handleContinuousStopFailure(error, flutterResult)
                return
            }

            setOnTaskCompletedListenerWithFailure(
                stopTask,
                {
                    Log.i(logTag, "Continuous recognition stopped.")
                    continuousListeningStarted = false
                    invokeMethod("speech.onRecognitionStopped", null)
                    reco.close()
                    closeMicrophoneStream()
                    flutterResult?.success(true)
                },
                { error -> handleContinuousStopFailure(error, flutterResult) },
            )
            return
        }

        closeMicrophoneStream()
        flutterResult?.success(true)
    }

    private fun micStreamContinuouslyWithAssessment(
        referenceText: String,
        phonemeAlphabet: String,
        granularity: PronunciationAssessmentGranularity,
        enableMiscue: Boolean,
        speechSubscriptionKey: String,
        serviceRegion: String,
        lang: String,
        nBestPhonemeCount: Int?,
    ) {
        val logTag: String = "micStreamContinuousWithAssessment"

        Log.i(logTag, "Continuous recognition started: $continuousListeningStarted")

        if (continuousListeningStarted || continuousListeningStarting) {
            if (continuousListeningStarting) {
                stopRequestedWhileStarting = true
                return
            }
            val endingTask = try {
                reco.stopContinuousRecognitionAsync()
            } catch (error: Throwable) {
                handleContinuousStopFailure(error, null)
                return
            }

            setOnTaskCompletedListenerWithFailure(
                endingTask,
                {
                    Log.i(logTag, "Continuous recognition stopped.")
                    continuousListeningStarted = false
                    invokeMethod("speech.onRecognitionStopped", null)
                    reco.close()
                    closeMicrophoneStream()
                },
                { error -> handleContinuousStopFailure(error, null) },
            )
            return
        }

        continuousListeningStarting = true
        try {
            val audioConfig = createMicrophoneAudioConfig()

            val config: SpeechConfig =
                SpeechConfig.fromSubscription(speechSubscriptionKey, serviceRegion)

            config.speechRecognitionLanguage = lang

            var pronunciationAssessmentConfig: PronunciationAssessmentConfig =
                PronunciationAssessmentConfig(
                    referenceText,
                    PronunciationAssessmentGradingSystem.HundredMark,
                    granularity,
                    enableMiscue
                )
            pronunciationAssessmentConfig.setPhonemeAlphabet(phonemeAlphabet)

            if (nBestPhonemeCount != null) {
                pronunciationAssessmentConfig.setNBestPhonemeCount(nBestPhonemeCount)
            }

            Log.i(logTag, pronunciationAssessmentConfig.toJson())

            reco = SpeechRecognizer(config, audioConfig)

            pronunciationAssessmentConfig.applyTo(reco)

            reco.recognizing.addEventListener { _, speechRecognitionResultEventArgs ->
                val s = speechRecognitionResultEventArgs.result.text
                Log.i(logTag, "Intermediate result received: $s")
                invokeMethod("speech.onSpeech", s)
            }

            reco.recognized.addEventListener { _, speechRecognitionResultEventArgs ->
                val result = speechRecognitionResultEventArgs.result;
                val s = result.text
                val pronunciationAssessmentResultJson =
                    result.properties.getProperty(PropertyId.SpeechServiceResponse_JsonResult)
                Log.i(logTag, "Final result received: $s")
                Log.i(
                    logTag, "pronunciationAssessmentResultJson: $pronunciationAssessmentResultJson"
                )
                invokeMethod("speech.onFinalResponse", s)
                invokeMethod("speech.onAssessmentResult", pronunciationAssessmentResultJson)
            }

            val startingTask = reco.startContinuousRecognitionAsync()

            setOnTaskCompletedListenerWithFailure(
                startingTask,
                {
                    continuousListeningStarting = false
                    continuousListeningStarted = true
                    invokeMethod("speech.onRecognitionStarted", null)
                    if (stopRequestedWhileStarting) {
                        stopRequestedWhileStarting = false
                        val result = pendingStopResult
                        pendingStopResult = null
                        stopContinuousMicStream(result)
                    }
                },
                { error -> handleContinuousStartFailure(error) },
            )
        } catch (exec: Exception) {
            handleContinuousStartFailure(exec)
        }
    }

    private val s_executorService: ExecutorService = Executors.newCachedThreadPool()

    private fun createMicrophoneAudioConfig(): AudioConfig {
        closeMicrophoneStream()
        val stream = MicrophoneStream { level ->
            invokeMethod("speech.onSoundLevel", level)
        }
        microphoneStream = stream
        val pullStream = PullAudioInputStream.createPullStream(stream)
        return AudioConfig.fromStreamInput(pullStream)
    }

    private fun closeMicrophoneStream() {
        microphoneStream?.close()
        microphoneStream = null
    }

    private fun cleanupContinuousRecognition() {
        continuousListeningStarted = false
        continuousListeningStarting = false
        stopRequestedWhileStarting = false
        pendingStartResult = null
        pendingStopResult = null
        if (this::reco.isInitialized) {
            runCatching {
                reco.stopContinuousRecognitionAsync()
            }
            runCatching {
                reco.close()
            }
        }
        closeMicrophoneStream()
    }


    private fun handleContinuousStartFailure(error: Throwable) {
        continuousListeningStarting = false
        continuousListeningStarted = false
        stopRequestedWhileStarting = false
        if (this::reco.isInitialized) {
            runCatching { reco.close() }
        }
        closeMicrophoneStream()
        pendingStartResult?.error(
            "azure_start_failed",
            error.message,
            null,
        )
        pendingStartResult = null
        pendingStopResult?.error(
            "azure_start_failed",
            error.message,
            null,
        )
        pendingStopResult = null
        invokeMethod("speech.onException", "Exception: ${error.message}")
    }

    private fun handleContinuousStopFailure(error: Throwable, flutterResult: Result?) {
        continuousListeningStarted = false
        continuousListeningStarting = false
        if (this::reco.isInitialized) {
            runCatching { reco.close() }
        }
        closeMicrophoneStream()
        flutterResult?.error(
            "azure_stop_failed",
            error.message,
            null,
        )
        invokeMethod("speech.onException", "Exception: ${error.message}")
    }

    private fun <T> setOnTaskCompletedListener(task: Future<T>, listener: (T) -> Unit) {
        setOnTaskCompletedListenerWithFailure(task, listener)
    }

    private fun <T> setOnTaskCompletedListenerWithFailure(
        task: Future<T>,
        listener: (T) -> Unit,
        onFailure: ((Throwable) -> Unit)? = null,
    ) {
        s_executorService.submit {
            try {
                val result = task.get()
                handler.post {
                    if (!isDetached) {
                        listener(result)
                    }
                }
            } catch (error: Throwable) {
                handler.post {
                    if (!isDetached) {
                        onFailure?.invoke(error)
                            ?: invokeMethod("speech.onException", "Exception: ${error.message}")
                    }
                }
            }
        }
    }

    private fun invokeMethod(method: String, arguments: Any?) {
        if (isDetached) return
        handler.post {
            if (!isDetached) {
                azureChannel.invokeMethod(method, arguments)
            }
        }
    }
}
