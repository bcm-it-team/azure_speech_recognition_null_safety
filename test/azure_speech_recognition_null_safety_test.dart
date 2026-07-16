import 'dart:async';

import 'package:azure_speech_recognition_null_safety/azure_speech_recognition_null_safety.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const MethodChannel channel = MethodChannel('azure_speech_recognition');

  TestWidgetsFlutterBinding.ensureInitialized();

  late MethodCall? lastCall;

  setUp(() {
    lastCall = null;
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      lastCall = methodCall;
      return true;
    });
  });

  tearDown(() {
    channel.setMockMethodCallHandler(null);
  });

  test('rejects continuous recognition before initialization', () {
    expect(
      AzureSpeechRecognition.startContinuousRecognition,
      throwsA(isA<StateError>()),
    );
  });

  test('starts continuous recognition with initialized credentials', () async {
    AzureSpeechRecognition.initialize(
      'subscription-key',
      'koreacentral',
      lang: 'ko-KR',
    );

    await AzureSpeechRecognition.startContinuousRecognition();

    expect(lastCall?.method, 'startContinuousStream');
    expect(lastCall?.arguments, {
      'language': 'ko-KR',
      'subscriptionKey': 'subscription-key',
      'region': 'koreacentral',
    });
  });

  test('stops continuous recognition through the explicit stop method', () async {
    await AzureSpeechRecognition.stopContinuousRecognition();

    expect(lastCall?.method, 'stopContinuousStream');
  });

  test('waits for native stop completion', () async {
    final nativeStop = Completer<void>();
    channel.setMockMethodCallHandler((MethodCall methodCall) async {
      lastCall = methodCall;
      if (methodCall.method == 'stopContinuousStream') {
        await nativeStop.future;
      }
      return true;
    });

    var completed = false;
    final stop = AzureSpeechRecognition.stopContinuousRecognition()
        .whenComplete(() => completed = true);

    expect(completed, isFalse);
    nativeStop.complete();
    await stop;

    expect(completed, isTrue);
    expect(lastCall?.method, 'stopContinuousStream');
  });
}
