## 0.9.6+8
- Fix(Android): Add plugin-level consumer ProGuard rules for Speech SDK reactive/logging optional classes in release minification.
- Chore(Android): Keep default Speech SDK at `1.48.2` with 16KB-native alignment and no host-app `jniLibs` excludes.

## 0.9.6+7
- Fix(Android): Set Microsoft Speech SDK default to `1.48.2` to avoid release R8 missing-class errors seen on `1.50.0`.
- Chore(Android): Keep native 16KB alignment baseline (`kws.ort` is 16KB-aligned on `1.44.0+`) without host-app excludes.

## 0.9.6+6
- Chore(Android): Upgrade Microsoft Speech SDK default to `1.50.0` for native 16KB alignment.
- Chore(Android): Remove `kws.ort` exclusion workaround from plugin/example Gradle setup.
- Docs(Android): Update 16KB guidance to recommend SDK upgrade over host-app excludes.

## 0.9.6+5
- Chore(Android): Publish dedicated tag for 16KB rollout in host apps.
- Chore(Android): Keep `kws.ort` exclusion guidance and SDK override (`AZURE_SPEECH_SDK_VERSION`) for Play compatibility checks.

## 0.9.6+4
- Chore(Android): Upgrade Microsoft Speech SDK dependency to `1.43.0` by default.
- Chore(Android): Exclude `kws.ort` native extension for `arm64-v8a`, `armeabi-v7a`, `x86`, `x86_64` to satisfy 16KB page-size alignment checks.
- Chore(Android): Add `AZURE_SPEECH_SDK_VERSION` Gradle property override support.
- Breaking(Android): Raise `minSdkVersion` to `24`.
- Note(Android): Host app should keep `packaging.jniLibs.excludes` for `kws.ort` in app module when enforcing 16KB checks.

## 0.9.6
- Fix: Update gradle for compatibility with Android Studio Ladybug 2024.2.1.

## 0.9.5
- Feat: Added method to stop continuous recognition independently.

## 0.9.4
- Feat: Added NBestPhoneme count parameter to improve assessments.

## 0.9.3
- Feat: Added speech assessment feature for continuous recognition.

## 0.9.2
- Feat: Added speech assessment feature for simple recognition.

## 0.9.0
- Feat: Added task cancellation, which allows cancelling all active Simple Recognition tasks.

## 0.8.9
- Fix: Use asynchronous recognition on iOS to avoid blocking main isolate.

## 0.8.8
- Fix: Added 0.8.7 features to Android.

## 0.8.7
- Feat: Partial results are now transmitted through calls to the appropriate handlers.
- Refactor: Removed poorly documented methods.
- __Important__: If your application depends on any of these methods consider staying on version 0.8.6.

## 0.8.6
- Feat: Added continuous speech recognition in iOS.

## 0.8.5
- Fix: final response now returns the empty string whenever result.getReason() is different from ResultReason.RecognizedSpeech on Android.

## 0.8.4
- Added iOS support for simple microphone recognition.

## 0.8.3
- Added null safety.
- Added (optional) segmentation silence timeout for simple voice recognition.

## 0.8.2
- BugFix
- Support continuous recognition

## 0.8.0
New method to initialize the speech recognition plugin.
See readme to know more about.

- Support for asynchronous recognition for the simple voice.
- Support for microphone streaming for having text while dictating
- New method to initialize the AzureSpeechRecognition

## 0.0.1
- it supports only Android.
- it supports only the voice recognition with the result at the end of the speech.
