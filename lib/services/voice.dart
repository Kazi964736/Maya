import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../settings.dart';

/// Something about the phone that makes a language work badly.
class LanguageProblem {
  const LanguageProblem({required this.kind, required this.language});

  /// 'voice' = no text-to-speech voice for it; 'speech' = the speech service can't recognise it.
  final String kind;
  final AppLanguage language;

  String get key => '${kind}_${language.code}';
}

/// Speech in (recognition) and speech out (text-to-speech).
class Voice {
  Voice._();
  static final instance = Voice._();

  final _stt = SpeechToText();
  final _tts = FlutterTts();
  bool _sttReady = false;
  bool _ttsReady = false;

  /// One shared set-up, so the app start and the first mic tap can't both
  /// initialise the recogniser at once (which fails on first launch).
  Future<bool>? _initFuture;

  final _checkedSpeech = <String>{};
  final _checkedVoice = <String>{};

  /// Words heard so far while listening.
  final heard = ValueNotifier<String>('');
  final listening = ValueNotifier<bool>(false);
  final speaking = ValueNotifier<bool>(false);
  final soundLevel = ValueNotifier<double>(0);

  /// Set when the current language is missing a voice or recognition support.
  final languageProblem = ValueNotifier<LanguageProblem?>(null);

  Future<bool> init() {
    final pending = _initFuture;
    if (pending != null) {
      return pending;
    }
    final future = _doInit();
    _initFuture = future;
    future.then((ok) {
      // If it failed (e.g. microphone refused), allow a fresh try on the next tap.
      if (!ok) {
        _initFuture = null;
      }
    });
    return future;
  }

  Future<bool> _doInit() async {
    if (!_ttsReady) {
      try {
        await _tts.awaitSpeakCompletion(true);
        _tts.setStartHandler(() => speaking.value = true);
        _tts.setCompletionHandler(() => speaking.value = false);
        _tts.setCancelHandler(() => speaking.value = false);
        _tts.setErrorHandler((_) => speaking.value = false);
        _ttsReady = true;
      } catch (e) {
        debugPrint('TTS init failed: $e');
      }
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

  /// Warns (once per language) if the phone's speech service doesn't list this language.
  Future<void> _checkSpeechSupport(AppLanguage lang) async {
    if (lang.code == 'en' || !_checkedSpeech.add(lang.code)) {
      return;
    }
    try {
      final locales = await _stt.locales();
      // Some phones return an empty list; only warn when we actually know.
      if (locales.isEmpty) {
        return;
      }
      final supported = locales.any((l) => l.localeId.toLowerCase().replaceAll('-', '_').startsWith(lang.code));
      if (!supported) {
        languageProblem.value = LanguageProblem(kind: 'speech', language: lang);
      }
    } catch (e) {
      debugPrint('Locale check failed: $e');
    }
  }

  /// Listens once and returns the final words (empty if nothing was heard).
  Future<String> listen(AppLanguage lang) async {
    if (!_sttReady && !await init()) {
      return '';
    }
    await stopSpeaking();
    unawaited(_checkSpeechSupport(lang));
    final done = Completer<String>();
    heard.value = '';
    listening.value = true;
    try {
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
    } catch (e) {
      debugPrint('Listen failed: $e');
      listening.value = false;
      return '';
    }
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
    if (!_ttsReady) {
      await init();
    }
    try {
      final available = await _tts.isLanguageAvailable(lang.ttsLocale);
      if (available != true && lang.code != 'en' && _checkedVoice.add(lang.code)) {
        languageProblem.value = LanguageProblem(kind: 'voice', language: lang);
      }
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
