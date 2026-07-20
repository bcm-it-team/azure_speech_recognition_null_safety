import Flutter
import UIKit
import MicrosoftCognitiveServicesSpeech
import AVFoundation

@available(iOS 13.0, *)
struct SimpleRecognitionTask {
    var task: Task<Void, Never>
    var isCanceled: Bool
}

@available(iOS 13.0, *)
public class SwiftAzureSpeechRecognitionPlugin: NSObject, FlutterPlugin {
    var azureChannel: FlutterMethodChannel
    var continousListeningStarted: Bool = false
    private var continousListeningStarting: Bool = false
    private var stopRequestedWhileStarting: Bool = false
    private var pendingStartResult: FlutterResult?
    private var pendingStopResult: FlutterResult?
    var continousSpeechRecognizer: SPXSpeechRecognizer? = nil
    var simpleRecognitionTasks: Dictionary<String, SimpleRecognitionTask> = [:]
    private let audioEngine = AVAudioEngine()
    private var pushAudioStream: SPXPushAudioInputStream?
    private var audioConverter: AVAudioConverter?
    private var lastSoundLevelReportedAt = Date.distantPast
    
    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "azure_speech_recognition", binaryMessenger: registrar.messenger())
        let instance: SwiftAzureSpeechRecognitionPlugin = SwiftAzureSpeechRecognitionPlugin(azureChannel: channel)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    init(azureChannel: FlutterMethodChannel) {
        self.azureChannel = azureChannel
    }

    deinit {
        if let recognizer = continousSpeechRecognizer {
            try? recognizer.stopContinuousRecognition()
        }
        stopMicrophoneStream()
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let args = call.arguments as? Dictionary<String, Any>
        let speechSubscriptionKey = args?["subscriptionKey"] as? String ?? ""
        let serviceRegion = args?["region"] as? String ?? ""
        let lang = args?["language"] as? String ?? ""
        let timeoutMs = args?["timeout"] as? String ?? ""
        let referenceText = args?["referenceText"] as? String ?? ""
        let phonemeAlphabet = args?["phonemeAlphabet"] as? String ?? "IPA"
        let granularityString = args?["granularity"] as? String ?? "phoneme"
        let enableMiscue = args?["enableMiscue"] as? Bool ?? false
        let nBestPhonemeCount = args?["nBestPhonemeCount"] as? Int
        var granularity: SPXPronunciationAssessmentGranularity
        if (granularityString == "text") {
            granularity = SPXPronunciationAssessmentGranularity.fullText
        }
        else if (granularityString == "word") {
            granularity = SPXPronunciationAssessmentGranularity.word
        }
        else {
            granularity = SPXPronunciationAssessmentGranularity.phoneme
        }
        if (call.method == "simpleVoice") {
            print("Called simpleVoice")
            simpleSpeechRecognition(speechSubscriptionKey: speechSubscriptionKey, serviceRegion: serviceRegion, lang: lang, timeoutMs: timeoutMs)
            result(true)
        }
        else if (call.method == "simpleVoiceWithAssessment") {
            print("Called simpleVoiceWithAssessment")
            simpleSpeechRecognitionWithAssessment(referenceText: referenceText, phonemeAlphabet: phonemeAlphabet,  granularity: granularity, enableMiscue: enableMiscue, speechSubscriptionKey: speechSubscriptionKey, serviceRegion: serviceRegion, lang: lang, timeoutMs: timeoutMs, nBestPhonemeCount: nBestPhonemeCount)
            result(true)
        }
        else if (call.method == "isContinuousRecognitionOn") {
            print("Called isContinuousRecognitionOn: \(continousListeningStarted)")
            result(continousListeningStarted)
        }
        else if (call.method == "continuousStream") {
            print("Called continuousStream")
            continuousStream(speechSubscriptionKey: speechSubscriptionKey, serviceRegion: serviceRegion, lang: lang)
            result(true)
        }
        else if (call.method == "startContinuousStream") {
            continuousStream(
                speechSubscriptionKey: speechSubscriptionKey,
                serviceRegion: serviceRegion,
                lang: lang,
                shouldToggle: false,
                flutterResult: result
            )
        }
        else if (call.method == "continuousStreamWithAssessment") {
            print("Called continuousStreamWithAssessment")
            continuousStreamWithAssessment(referenceText: referenceText, phonemeAlphabet: phonemeAlphabet,  granularity: granularity, enableMiscue: enableMiscue, speechSubscriptionKey: speechSubscriptionKey, serviceRegion: serviceRegion, lang: lang, nBestPhonemeCount: nBestPhonemeCount)
            result(true)
        }
        else if (call.method == "stopContinuousStream") {
            stopContinuousStream(flutterResult: result)
        }
        else {
            result(FlutterMethodNotImplemented)
        }
    }
    
    
    
    private func cancelActiveSimpleRecognitionTasks() {
        print("Cancelling any active tasks")
        for taskId in simpleRecognitionTasks.keys {
            print("Cancelling task \(taskId)")
            simpleRecognitionTasks[taskId]?.task.cancel()
            simpleRecognitionTasks[taskId]?.isCanceled = true
        }
    }
    
    private func simpleSpeechRecognition(speechSubscriptionKey : String, serviceRegion : String, lang: String, timeoutMs: String) {
        print("Created new recognition task")
        cancelActiveSimpleRecognitionTasks()
        let taskId = UUID().uuidString;
        let task = Task {
            print("Started recognition with task ID \(taskId)")
            var speechConfig: SPXSpeechConfiguration?
            do {
                setupAudioSession()
                // Initialize speech recognizer and specify correct subscription key and service region
                try speechConfig = SPXSpeechConfiguration(subscription: speechSubscriptionKey, region: serviceRegion)
            } catch {
                print("error \(error) happened")
                speechConfig = nil
            }
            speechConfig?.speechRecognitionLanguage = lang
            speechConfig?.setPropertyTo(timeoutMs, by: SPXPropertyId.speechSegmentationSilenceTimeoutMs)
            
            let audioConfig = SPXAudioConfiguration()
            let reco = try! SPXSpeechRecognizer(speechConfiguration: speechConfig!, audioConfiguration: audioConfig)
            
            reco.addRecognizingEventHandler() {reco, evt in
                if (self.simpleRecognitionTasks[taskId]?.isCanceled ?? false) { // Discard intermediate results if the task was cancelled
                    print("Ignoring partial result. TaskID: \(taskId)")
                }
                else {
                    print("Intermediate result: \(evt.result.text ?? "(no result)")\nTaskID: \(taskId)")
                    self.azureChannel.invokeMethod("speech.onSpeech", arguments: evt.result.text)
                }
            }
            
            let result = try! reco.recognizeOnce()
            if (Task.isCancelled) {
                print("Ignoring final result. TaskID: \(taskId)")
            } else {
                print("Final result: \(result.text ?? "(no result)")\nReason: \(result.reason.rawValue)\nTaskID: \(taskId)")
                if result.reason != SPXResultReason.recognizedSpeech {
                    let cancellationDetails = try! SPXCancellationDetails(fromCanceledRecognitionResult: result)
                    print("Cancelled: \(cancellationDetails.description), \(cancellationDetails.errorDetails)\nTaskID: \(taskId)")
                    print("Did you set the speech resource key and region values?")
                    self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: "")
                }
                else {
                    self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: result.text)
                }
                
            }
            self.simpleRecognitionTasks.removeValue(forKey: taskId)
        }
        simpleRecognitionTasks[taskId] = SimpleRecognitionTask(task: task, isCanceled: false)
    }
    
    private func simpleSpeechRecognitionWithAssessment(referenceText: String, phonemeAlphabet: String, granularity: SPXPronunciationAssessmentGranularity, enableMiscue: Bool, speechSubscriptionKey : String, serviceRegion : String, lang: String, timeoutMs: String, nBestPhonemeCount: Int?) {
        print("Created new recognition task")
        cancelActiveSimpleRecognitionTasks()
        let taskId = UUID().uuidString;
        let task = Task {
            print("Started recognition with task ID \(taskId)")
            var speechConfig: SPXSpeechConfiguration?
            var pronunciationAssessmentConfig: SPXPronunciationAssessmentConfiguration?
            do {
                setupAudioSession()
                // Initialize speech recognizer and specify correct subscription key and service region
                try speechConfig = SPXSpeechConfiguration(subscription: speechSubscriptionKey, region: serviceRegion)
                try pronunciationAssessmentConfig = SPXPronunciationAssessmentConfiguration.init(
                    referenceText,
                    gradingSystem: SPXPronunciationAssessmentGradingSystem.hundredMark,
                    granularity: granularity,
                    enableMiscue: enableMiscue)
            } catch {
                print("error \(error) happened")
                speechConfig = nil
            }
            pronunciationAssessmentConfig?.phonemeAlphabet = phonemeAlphabet
            
            if nBestPhonemeCount != nil {
                pronunciationAssessmentConfig?.nbestPhonemeCount = nBestPhonemeCount!
            }
            
            speechConfig?.speechRecognitionLanguage = lang
            speechConfig?.setPropertyTo(timeoutMs, by: SPXPropertyId.speechSegmentationSilenceTimeoutMs)
            
            let audioConfig = SPXAudioConfiguration()
            let reco = try! SPXSpeechRecognizer(speechConfiguration: speechConfig!, audioConfiguration: audioConfig)
            try! pronunciationAssessmentConfig?.apply(to: reco)
            
            reco.addRecognizingEventHandler() {reco, evt in
                if (self.simpleRecognitionTasks[taskId]?.isCanceled ?? false) { // Discard intermediate results if the task was cancelled
                    print("Ignoring partial result. TaskID: \(taskId)")
                }
                else {
                    print("Intermediate result: \(evt.result.text ?? "(no result)")\nTaskID: \(taskId)")
                    self.azureChannel.invokeMethod("speech.onSpeech", arguments: evt.result.text)
                }
            }
            
            let result = try! reco.recognizeOnce()
            if (Task.isCancelled) {
                print("Ignoring final result. TaskID: \(taskId)")
            } else {
                print("Final result: \(result.text ?? "(no result)")\nReason: \(result.reason.rawValue)\nTaskID: \(taskId)")
                let pronunciationAssessmentResultJson = result.properties?.getPropertyBy(SPXPropertyId.speechServiceResponseJsonResult)
                print("pronunciationAssessmentResultJson: \(pronunciationAssessmentResultJson ?? "(no result)")")
                if result.reason != SPXResultReason.recognizedSpeech {
                    let cancellationDetails = try! SPXCancellationDetails(fromCanceledRecognitionResult: result)
                    print("Cancelled: \(cancellationDetails.description), \(cancellationDetails.errorDetails)\nTaskID: \(taskId)")
                    print("Did you set the speech resource key and region values?")
                    self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: "")
                    self.azureChannel.invokeMethod("speech.onAssessmentResult", arguments: "")
                }
                else {
                    self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: result.text)
                    self.azureChannel.invokeMethod("speech.onAssessmentResult", arguments: pronunciationAssessmentResultJson)
                }
                
            }
            self.simpleRecognitionTasks.removeValue(forKey: taskId)
        }
        simpleRecognitionTasks[taskId] = SimpleRecognitionTask(task: task, isCanceled: false)
    }
    
    private func stopContinuousStream(flutterResult: @escaping FlutterResult) {
        if continousListeningStarting {
            if pendingStopResult != nil {
                flutterResult(true)
                return
            }
            stopRequestedWhileStarting = true
            pendingStopResult = flutterResult
            return
        }
        guard continousListeningStarted, let recognizer = continousSpeechRecognizer else {
            stopMicrophoneStream()
            flutterResult(true)
            return
        }

        do {
            try recognizer.stopContinuousRecognition()
            finishContinuousRecognition()
            flutterResult(true)
        } catch {
            stopMicrophoneStream()
            continousSpeechRecognizer = nil
            continousListeningStarted = false
            flutterResult(FlutterError(code: "azure_stop_failed", message: error.localizedDescription, details: nil))
        }
    }
    
    private func continuousStream(
        speechSubscriptionKey : String,
        serviceRegion : String,
        lang: String,
        shouldToggle: Bool = true,
        flutterResult: FlutterResult? = nil
    ) {
        if continousListeningStarting {
            flutterResult?(FlutterError(
                code: "azure_start_in_progress",
                message: "Continuous recognition is already starting",
                details: nil
            ))
            return
        }
        if !shouldToggle && continousListeningStarted {
            flutterResult?(true)
            return
        }
        if (continousListeningStarted) {
            print("Stopping continous recognition")
            guard let recognizer = continousSpeechRecognizer else {
                finishContinuousRecognition()
                flutterResult?(true)
                return
            }
            do {
                try recognizer.stopContinuousRecognition()
                self.azureChannel.invokeMethod("speech.onRecognitionStopped", arguments: nil)
                continousSpeechRecognizer = nil
                continousListeningStarted = false
                stopMicrophoneStream()
                flutterResult?(true)
            }
            catch {
                print("Error occurred stopping continous recognition")
                flutterResult?(FlutterError(
                    code: "azure_stop_failed",
                    message: error.localizedDescription,
                    details: nil
                ))
            }
        }
        else {
            print("Starting continous recognition")
            continousListeningStarting = true
            pendingStartResult = flutterResult
            do {
                setupAudioSession()
                let speechConfig = try SPXSpeechConfiguration(
                    subscription: speechSubscriptionKey,
                    region: serviceRegion
                )
                speechConfig.speechRecognitionLanguage = lang
                let audioConfig = try createStreamAudioConfiguration()
                let recognizer = try SPXSpeechRecognizer(
                    speechConfiguration: speechConfig,
                    audioConfiguration: audioConfig
                )
                continousSpeechRecognizer = recognizer
                recognizer.addRecognizingEventHandler() {reco, evt in
                print("intermediate recognition result: \(evt.result.text ?? "(no result)")")
                self.azureChannel.invokeMethod("speech.onSpeech", arguments: evt.result.text)
                }
                recognizer.addRecognizedEventHandler({reco, evt in
                    let resultText = evt.result.text ?? ""
                    print("final result \(resultText)")
                    self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: resultText)
                })
                print("Listening...")
                try recognizer.startContinuousRecognition()
                self.azureChannel.invokeMethod("speech.onRecognitionStarted", arguments: nil)
                continousListeningStarted = true
                continousListeningStarting = false
                pendingStartResult?(true)
                pendingStartResult = nil
                if stopRequestedWhileStarting {
                    stopRequestedWhileStarting = false
                    let result = pendingStopResult
                    pendingStopResult = nil
                    stopContinuousStream(flutterResult: result ?? { _ in })
                }
            } catch {
                print("Continuous recognition start failed: \(error)")
                failContinuousStart(message: error.localizedDescription)
            }
        }
    }
    
    private func continuousStreamWithAssessment(referenceText: String, phonemeAlphabet: String, granularity: SPXPronunciationAssessmentGranularity, enableMiscue: Bool, speechSubscriptionKey : String, serviceRegion : String, lang: String, nBestPhonemeCount: Int?) {
        print("Continuous recognition started: \(continousListeningStarted)")
        if continousListeningStarting {
            stopRequestedWhileStarting = true
            return
        }
        if (continousListeningStarted) {
            print("Stopping continous recognition")
            guard let recognizer = continousSpeechRecognizer else {
                finishContinuousRecognition()
                return
            }
            do {
                try recognizer.stopContinuousRecognition()
                finishContinuousRecognition()
            }
            catch {
                print("Error occurred stopping continous recognition")
            }
        }
        else {
            print("Starting continous recognition")
            continousListeningStarting = true
            do {
                setupAudioSession()
                let speechConfig = try SPXSpeechConfiguration(subscription: speechSubscriptionKey, region: serviceRegion)
                speechConfig.speechRecognitionLanguage = lang
                let pronunciationAssessmentConfig = try SPXPronunciationAssessmentConfiguration.init(
                    referenceText,
                    gradingSystem: SPXPronunciationAssessmentGradingSystem.hundredMark,
                    granularity: granularity,
                    enableMiscue: enableMiscue)
                pronunciationAssessmentConfig.phonemeAlphabet = phonemeAlphabet

                if let nBestPhonemeCount {
                    pronunciationAssessmentConfig.nbestPhonemeCount = nBestPhonemeCount
                }

                let audioConfig = try createStreamAudioConfiguration()
                let recognizer = try SPXSpeechRecognizer(
                    speechConfiguration: speechConfig,
                    audioConfiguration: audioConfig
                )
                try pronunciationAssessmentConfig.apply(to: recognizer)
                continousSpeechRecognizer = recognizer

                recognizer.addRecognizingEventHandler() {reco, evt in
                    print("intermediate recognition result: \(evt.result.text ?? "(no result)")")
                    self.azureChannel.invokeMethod("speech.onSpeech", arguments: evt.result.text)
                }
                recognizer.addRecognizedEventHandler({reco, evt in
                    let result = evt.result
                    print("Final result: \(result.text ?? "(no result)")\nReason: \(result.reason.rawValue)")
                    let pronunciationAssessmentResultJson = result.properties?.getPropertyBy(SPXPropertyId.speechServiceResponseJsonResult)
                    print("pronunciationAssessmentResultJson: \(pronunciationAssessmentResultJson ?? "(no result)")")
                    self.azureChannel.invokeMethod("speech.onFinalResponse", arguments: result.text)
                    self.azureChannel.invokeMethod("speech.onAssessmentResult", arguments: pronunciationAssessmentResultJson)
                })
                print("Listening...")
                try recognizer.startContinuousRecognition()
                self.azureChannel.invokeMethod("speech.onRecognitionStarted", arguments: nil)
                continousListeningStarted = true
                continousListeningStarting = false
                if stopRequestedWhileStarting {
                    stopRequestedWhileStarting = false
                    let result = pendingStopResult
                    pendingStopResult = nil
                    stopContinuousStream(flutterResult: result ?? { _ in })
                }
            }
            catch {
                print("An unexpected error occurred: \(error)")
                failContinuousStart(message: error.localizedDescription)
            }
        }
    }

    private func failContinuousStart(message: String) {
        continousSpeechRecognizer = nil
        continousListeningStarted = false
        continousListeningStarting = false
        stopRequestedWhileStarting = false
        stopMicrophoneStream()
        pendingStartResult?(FlutterError(
            code: "azure_start_failed",
            message: message,
            details: nil
        ))
        pendingStartResult = nil
        pendingStopResult?(FlutterError(
            code: "azure_start_failed",
            message: message,
            details: nil
        ))
        pendingStopResult = nil
        azureChannel.invokeMethod("speech.onException", arguments: message)
    }
    
    private func createStreamAudioConfiguration() throws -> SPXAudioConfiguration {
        stopMicrophoneStream()

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        guard
            let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatInt16,
                sampleRate: 16000,
                channels: 1,
                interleaved: true
            ),
            let converter = AVAudioConverter(from: inputFormat, to: targetFormat),
            let speechFormat = SPXAudioStreamFormat(
                usingPCMWithSampleRate: 16000,
                bitsPerSample: 16,
                channels: 1
            ),
            let stream = SPXPushAudioInputStream(audioFormat: speechFormat)
        else {
            throw NSError(
                domain: "azure_speech_recognition",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to configure microphone stream"]
            )
        }

        audioConverter = converter
        pushAudioStream = stream
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            self?.write(buffer: buffer, targetFormat: targetFormat)
        }
        audioEngine.prepare()
        try audioEngine.start()

        guard let audioConfig = SPXAudioConfiguration(streamInput: stream) else {
            stopMicrophoneStream()
            throw NSError(
                domain: "azure_speech_recognition",
                code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Unable to create audio configuration"]
            )
        }
        return audioConfig
    }

    private func write(buffer: AVAudioPCMBuffer, targetFormat: AVAudioFormat) {
        guard
            let converter = audioConverter,
            let stream = pushAudioStream
        else {
            return
        }

        let frameCapacity = AVAudioFrameCount(
            (Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate).rounded(.up)
        )
        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frameCapacity) else {
            return
        }

        var inputProvided = false
        var conversionError: NSError?
        converter.convert(to: convertedBuffer, error: &conversionError) { _, status in
            if inputProvided {
                status.pointee = .noDataNow
                return nil
            }
            inputProvided = true
            status.pointee = .haveData
            return buffer
        }
        guard conversionError == nil else {
            return
        }

        let audioBuffer = convertedBuffer.audioBufferList.pointee.mBuffers
        guard let audioData = audioBuffer.mData, audioBuffer.mDataByteSize > 0 else {
            return
        }
        let data = Data(bytes: audioData, count: Int(audioBuffer.mDataByteSize))
        stream.write(data)
        reportSoundLevel(data)
    }

    private func reportSoundLevel(_ data: Data) {
        guard Date().timeIntervalSince(lastSoundLevelReportedAt) >= 0.1 else {
            return
        }
        lastSoundLevelReportedAt = Date()

        let level = data.withUnsafeBytes { rawBuffer -> Double in
            let samples = rawBuffer.bindMemory(to: Int16.self)
            guard !samples.isEmpty else {
                return 0
            }
            let meanSquare = samples.reduce(0.0) { sum, sample in
                let value = Double(sample)
                return sum + value * value
            } / Double(samples.count)
            let rms = sqrt(meanSquare)
            let decibels = 20 * log10(max(rms / Double(Int16.max), 0.000001))
            return min(max((decibels + 60) * (100 / 60), 0), 100)
        }
        DispatchQueue.main.async {
            self.azureChannel.invokeMethod("speech.onSoundLevel", arguments: level)
        }
    }

    private func finishContinuousRecognition() {
        azureChannel.invokeMethod("speech.onRecognitionStopped", arguments: nil)
        continousSpeechRecognizer = nil
        continousListeningStarted = false
        continousListeningStarting = false
        stopMicrophoneStream()
    }

    private func stopMicrophoneStream() {
        if audioEngine.isRunning {
            audioEngine.stop()
        }
        audioEngine.inputNode.removeTap(onBus: 0)
        pushAudioStream?.close()
        pushAudioStream = nil
        audioConverter = nil
    }

    private func setupAudioSession() {
        let audioSession = AVAudioSession.sharedInstance()
        
        do {
            if audioSession.category != .playAndRecord {
                print("Setting up AudioSession category to playAndRecord")
                try audioSession.setCategory(.playAndRecord, mode: .default, options: [.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker])
            } else {
                print("AudioSession category already playAndRecord")
            }
            
            if !audioSession.isOtherAudioPlaying || !audioSession.isInputAvailable {
                // 오디오 세션을 활성화
                print("Activating AudioSession")
                try audioSession.setActive(true)
            } else {
                print("Audio already playing or input available, skipping activation")
            }
        } catch {
            print("Failed to setup AudioSession: \(error)")
        }
    }
}
