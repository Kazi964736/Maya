import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../settings.dart';

/// Speech in (recognition) and speech out (text-to-speech).
class Voice {
  Voice._();
  static final instance = Voice._();

  final _stt = SpeechToText();
  final _tts = FlutterTts();
  bool _sttReady = false;

  /// Words heard so far while listening.
  final heard = ValueNotifier<String>('');
  final listening = ValueNotifier<bool>(false);
  final speaking = ValueNotifier<bool>(false);
  final soundLevel = ValueNotifier<double>(0);

  Future<bool> init() async {
    try {
      await _tts.awaitSpeakCompletion(true);
      _tts.setStartHandler(() => speaking.value = true);
      _tts.setCompletionHandler(() => speaking.value = false);
      _tts.setCancelHandler(() => speaking.value = false);
      _tts.setErrorHandler((_) => speaking.value = false);
    } catch (e) {
      debugPrint('TTS init failed: $e');
    }
    try {
      _sttReady = await _stt.initialize(
        onStatus: (status) {
          if (status == 'done' || status == 'notListening') {
            listening.value = false;
          }
        },
        onError: (SpeechRecognitionError e) {
          debugPrint('Speech error: ${e.errorMsg}');
          listening.value = false;
        },
      );
    } catch (e) {
      debugPrint('Speech init failed: $e');
      _sttReady = false;
    }
    return _sttReady;
  }

  bool get canListen => _sttReady;

  /// Listens once and returns the final words (empty if nothing was heard).
  Future<String> listen(AppLanguage lang) async {
    if (!_sttReady) {
      _sttReady = await init();
      if (!_sttReady) {
        return '';
      }
    }
    await stopSpeaking();
    final done = Completer<String>();
    heard.value = '';
    listening.value = true;
    await _stt.listen(
      localeId: lang.speechLocale,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      onSoundLevelChange: (level) => soundLevel.value = level,
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.dictation,
      ),
      onResult: (SpeechRecognitionResult r) {
        heard.value = r.recognizedWords;
        if (r.finalResult && !done.isCompleted) {
          done.complete(r.recognizedWords);
        }
      },
    );
    // Finish when the recognizer stops, even without a "final" result.
    void watch() {
      if (!listening.value && !done.isCompleted) {
        done.complete(heard.value);
      }
    }

    listening.addListener(watch);
    final words = await done.future.timeout(const Duration(seconds: 40), onTimeout: () => heard.value);
    listening.removeListener(watch);
    listening.value = false;
    return words.trim();
  }

  Future<void> stopListening() async {
    try {
      await _stt.stop();
    } catch (_) {}
    listening.value = false;
  }

  Future<void> speak(String text, AppLanguage lang) async {
    if (text.trim().isEmpty) {
      return;
    }
    try {
      final available = await _tts.isLanguageAvailable(lang.ttsLocale);
      await _tts.setLanguage(available == true ? lang.ttsLocale : 'en-IN');
      await _tts.setSpeechRate(0.5);
      await _tts.setPitch(1.0);
      speaking.value = true;
      await _tts.speak(text);
    } catch (e) {
      debugPrint('Speak failed: $e');
    } finally {
      speaking.value = false;
    }
  }

  Future<void> stopSpeaking() async {
    try {
      await _tts.stop();
    } catch (_) {}
    speaking.value = false;
  }
}
