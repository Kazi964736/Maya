import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../settings.dart';
import 'voice_id.dart';

// ---------------------------------------------------------------------------
// "Hey Maya": a small offline keyword spotter runs in a foreground service
// (with a notification), so Maya can be woken from anywhere on the phone.
// ---------------------------------------------------------------------------

/// Messages between the app screen and the listening service.
class WakeMsg {
  static const pause = 'pause'; // the app is about to use the microphone
  static const resume = 'resume'; // the app is done with the microphone
  static const wake = 'wake'; // "Hey Maya" was heard (service -> app)
  static const paused = 'paused'; // the service has let go of the microphone (service -> app)
}

/// Keys shared through SharedPreferences.
class WakeKeys {
  static const enabled = 'wake_enabled';
  static const sensitivity = 'wake_sensitivity'; // 0..1, higher hears more easily
  static const verified = 'wake_verified'; // the wake word was already checked by Voice Lock
  static const status = 'wake_status'; // what the service is doing, for the settings screen
}

/// The app side: switching hands-free on and off and talking to the service.
class WakeWord {
  WakeWord._();
  static final instance = WakeWord._();

  final _settings = Settings.instance;
  bool _initialised = false;

  bool get enabled => _settings.prefs.getBool(WakeKeys.enabled) ?? false;
  double get sensitivity => _settings.prefs.getDouble(WakeKeys.sensitivity) ?? 0.6;

  /// What the listening service last reported ("listening", "paused", an error…).
  Future<String> status() async {
    if (!await isRunning) {
      return enabled ? 'not running — open Maya to start it' : 'off';
    }
    return await FlutterForegroundTask.getData<String>(key: WakeKeys.status) ?? 'starting…';
  }

  Future<void> setSensitivity(double v) async {
    await _settings.prefs.setDouble(WakeKeys.sensitivity, v);
    if (await isRunning) {
      await FlutterForegroundTask.restartService();
    }
  }

  Future<bool> get isRunning => FlutterForegroundTask.isRunningService;

  Completer<void>? _pauseAck;

  void _onTaskData(Object data) {
    if (data == WakeMsg.paused) {
      final ack = _pauseAck;
      if (ack != null && !ack.isCompleted) {
        ack.complete();
      }
    }
  }

  void _init() {
    if (_initialised) {
      return;
    }
    _initialised = true;
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'maya_wake_word',
        channelName: 'Hey Maya listening',
        channelDescription: 'Shown while Maya listens for "Hey Maya".',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
      ),
      iosNotificationOptions: const IOSNotificationOptions(showNotification: false, playSound: false),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30000),
        autoRunOnBoot: false,
        autoRunOnMyPackageReplaced: false,
        allowWakeLock: true,
        allowWifiLock: false,
        // A microphone service may not be restarted from the background on new Android versions.
        allowAutoRestart: false,
        stopWithTask: false,
      ),
    );
  }

  /// Copies the bundled model out of the app so the engine can read it.
  static Future<String> _prepareModel() async {
    final dir = Directory('${(await getApplicationSupportDirectory()).path}/kws');
    await dir.create(recursive: true);
    for (final name in ['encoder.onnx', 'decoder.onnx', 'joiner.onnx', 'tokens.txt']) {
      final file = File('${dir.path}/$name');
      final data = await rootBundle.load('assets/kws/$name');
      if (!await file.exists() || await file.length() != data.lengthInBytes) {
        await file.writeAsBytes(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes), flush: true);
      }
    }
    return dir.path;
  }

  /// Turns hands-free on (true) or off. Returns a problem to show, or null.
  Future<String?> setEnabled(bool on) async {
    _init();
    await _settings.prefs.setBool(WakeKeys.enabled, on);
    if (!on) {
      await FlutterForegroundTask.stopService();
      return null;
    }
    return start();
  }

  /// Starts listening if hands-free is on. Must be called while the app is open.
  Future<String?> start() async {
    if (!enabled) {
      return null;
    }
    _init();
    try {
      final dir = await _prepareModel();
      await FlutterForegroundTask.saveData(key: 'kws_dir', value: dir);
      if (await isRunning) {
        return null;
      }
      final result = await FlutterForegroundTask.startService(
        serviceId: 701,
        serviceTypes: [ForegroundServiceTypes.microphone],
        notificationTitle: 'Maya is listening',
        notificationText: 'Say "Hey Maya" any time',
        callback: wakeWordCallback,
      );
      if (result is ServiceRequestFailure) {
        return 'Could not start hands-free: ${result.error}';
      }
      return null;
    } catch (e) {
      return 'Could not start hands-free: $e';
    }
  }

  bool _stoppedForApp = false;

  /// The app wants the microphone (it can't be shared). Waits until the
  /// service has really let go of it; if it doesn't answer, the service is
  /// stopped and started again later by [resume].
  Future<void> pause() async {
    if (!enabled || !await isRunning) {
      return;
    }
    _init();
    final ack = _pauseAck = Completer<void>();
    FlutterForegroundTask.sendDataToTask(WakeMsg.pause);
    try {
      await ack.future.timeout(const Duration(milliseconds: 1500));
    } catch (_) {
      await FlutterForegroundTask.stopService();
      _stoppedForApp = true;
    }
    // A short gap so Android hands the microphone over cleanly.
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }

  void resume() {
    if (!enabled) {
      return;
    }
    if (_stoppedForApp) {
      _stoppedForApp = false;
      unawaited(start());
      return;
    }
    FlutterForegroundTask.sendDataToTask(WakeMsg.resume);
  }
}

// ---------------------------------------------------------------------------
// The service side (runs in its own isolate).
// ---------------------------------------------------------------------------

@pragma('vm:entry-point')
void wakeWordCallback() {
  FlutterForegroundTask.setTaskHandler(_WakeWordTask());
}

class _WakeWordTask extends TaskHandler {
  static const _rate = 16000;

  sherpa.KeywordSpotter? _spotter;
  sherpa.OnlineStream? _stream;
  final _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _mic;
  bool _paused = false;
  Timer? _autoResume;
  var _carry = <int>[];

  /// The last 2.5 seconds of sound, used to check the speaker with Voice Lock.
  final _ring = Float32List(_rate * 5 ~/ 2);
  var _ringPos = 0;
  var _ringFilled = false;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    try {
      await Settings.instance.load();
      sherpa.initBindings();
      final dir = await FlutterForegroundTask.getData<String>(key: 'kws_dir');
      if (dir == null) {
        throw Exception('model folder not set');
      }
      final sensitivity = Settings.instance.prefs.getDouble(WakeKeys.sensitivity) ?? 0.5;
      // Higher sensitivity = lower threshold (tested: 0.10–0.20 works well).
      final threshold = (0.30 - sensitivity * 0.22).clamp(0.05, 0.30);
      final keywords = File('$dir/keywords.txt');
      await keywords.writeAsString([
        '▁HE Y ▁MA Y A :2.0 #${threshold.toStringAsFixed(3)} @hey_maya',
        '▁HI ▁MA Y A :2.0 #${threshold.toStringAsFixed(3)} @hi_maya',
        '▁O K ▁MA Y A :2.0 #${threshold.toStringAsFixed(3)} @ok_maya',
      ].join('\n'));
      final spotter = sherpa.KeywordSpotter(
        sherpa.KeywordSpotterConfig(
          model: sherpa.OnlineModelConfig(
            transducer: sherpa.OnlineTransducerModelConfig(
              encoder: '$dir/encoder.onnx',
              decoder: '$dir/decoder.onnx',
              joiner: '$dir/joiner.onnx',
            ),
            tokens: '$dir/tokens.txt',
            numThreads: 1,
            debug: false,
          ),
          keywordsFile: keywords.path,
          keywordsScore: 2.0,
          keywordsThreshold: threshold,
        ),
      );
      _spotter = spotter;
      _stream = spotter.createStream();
      await _startMic();
    } catch (e) {
      debugPrint('Wake word start failed: $e');
      await _status('error: $e');
      FlutterForegroundTask.updateService(
        notificationTitle: 'Maya hands-free stopped',
        notificationText: 'Open Maya to turn it on again',
      );
    }
  }

  Future<void> _startMic() async {
    if (_mic != null || _paused) {
      return;
    }
    try {
      final audio = await _recorder.startStream(
        const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: _rate, numChannels: 1),
      );
      _mic = audio.listen(_onAudio);
      FlutterForegroundTask.updateService(
        notificationTitle: 'Maya is listening',
        notificationText: 'Say "Hey Maya" any time',
      );
      await _status('listening');
    } catch (e) {
      debugPrint('Wake word mic failed: $e');
      await _status('microphone error: $e');
    }
  }

  Future<void> _status(String text) async {
    final t = DateTime.now();
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    try {
      await FlutterForegroundTask.saveData(key: WakeKeys.status, value: '$text ($hm)');
    } catch (_) {}
  }

  /// Keeps only the part of [clip] where someone is speaking.
  static Float32List _voiced(Float32List clip) {
    const frame = _rate ~/ 50; // 20 ms
    final frames = clip.length ~/ frame;
    if (frames < 5) {
      return clip;
    }
    final energy = List<double>.generate(frames, (f) {
      var sum = 0.0;
      for (var i = f * frame; i < (f + 1) * frame; i++) {
        sum += clip[i] * clip[i];
      }
      return sum / frame;
    });
    final sorted = [...energy]..sort();
    final floor = sorted[frames ~/ 5];
    final loud = floor * 6 + 1e-6;
    var first = energy.indexWhere((e) => e > loud);
    var last = energy.lastIndexWhere((e) => e > loud);
    if (first < 0 || last - first < 20) {
      return clip; // under 0.4 s of speech: use everything
    }
    first = (first - 5).clamp(0, frames - 1);
    last = (last + 5).clamp(0, frames - 1);
    return Float32List.sublistView(clip, first * frame, (last + 1) * frame);
  }

  Future<void> _stopMic() async {
    final sub = _mic;
    _mic = null;
    await sub?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  void _onAudio(Uint8List bytes) {
    final spotter = _spotter;
    final stream = _stream;
    if (spotter == null || stream == null || _paused) {
      return;
    }
    final data = _carry.isEmpty ? bytes : Uint8List.fromList([..._carry, ...bytes]);
    final usable = data.length - data.length % 2;
    _carry = data.sublist(usable).toList();
    final n = usable ~/ 2;
    if (n == 0) {
      return;
    }
    final view = ByteData.sublistView(data, 0, usable);
    final samples = Float32List(n);
    for (var i = 0; i < n; i++) {
      final v = view.getInt16(i * 2, Endian.little) / 32768.0;
      samples[i] = v;
      _ring[_ringPos] = v;
      _ringPos = (_ringPos + 1) % _ring.length;
      if (_ringPos == 0) {
        _ringFilled = true;
      }
    }
    stream.acceptWaveform(samples: samples, sampleRate: _rate);
    while (spotter.isReady(stream)) {
      spotter.decode(stream);
      final hit = spotter.getResult(stream).keyword;
      if (hit.isNotEmpty) {
        spotter.reset(stream);
        unawaited(_onWake());
        return;
      }
    }
  }

  Float32List _recentAudio() {
    if (!_ringFilled) {
      return Float32List.fromList(_ring.sublist(0, _ringPos));
    }
    return Float32List.fromList([..._ring.sublist(_ringPos), ..._ring.sublist(0, _ringPos)]);
  }

  Future<void> _onWake() async {
    _paused = true;
    final clip = _recentAudio();
    await _stopMic();

    final prefs = Settings.instance.prefs;
    await prefs.reload();
    var verified = false;
    final voiceId = VoiceId.instance;
    if (await voiceId.active) {
      var score = 0.0;
      try {
        final speech = _voiced(clip);
        score = speech.length > _rate ~/ 2 ? await voiceId.similarity(speech) : 0;
        // A short wake phrase scores lower than the long teaching sentences: be a bit lenient.
        verified = score >= voiceId.strictness - 0.08;
      } catch (e) {
        debugPrint('Wake voice check failed: $e');
        verified = true; // never lock the owner out because the check broke
      }
      if (!verified) {
        // Someone else said "Hey Maya": stay quiet and keep listening.
        await _status('heard "Hey Maya" but not your voice (${(score * 100).round()}% match)');
        _paused = false;
        await _startMic();
        return;
      }
    }

    await prefs.setBool(WakeKeys.verified, verified);
    await prefs.setInt('listen_request', DateTime.now().millisecondsSinceEpoch);
    try {
      await HapticFeedback.mediumImpact();
    } catch (_) {}
    await _status('heard "Hey Maya"');
    FlutterForegroundTask.sendDataToMain(WakeMsg.wake);
    if (!await FlutterForegroundTask.isAppOnForeground) {
      FlutterForegroundTask.wakeUpScreen();
      FlutterForegroundTask.launchApp();
    }
    // If the app never hands the microphone back, start listening again anyway.
    _autoResume?.cancel();
    _autoResume = Timer(const Duration(seconds: 45), _resume);
  }

  Future<void> _resume() async {
    _autoResume?.cancel();
    _paused = false;
    final stream = _stream;
    if (stream != null) {
      _spotter?.reset(stream);
    }
    await _startMic();
  }

  @override
  void onReceiveData(Object data) {
    if (data == WakeMsg.pause) {
      _paused = true;
      _autoResume?.cancel();
      _autoResume = Timer(const Duration(seconds: 90), _resume);
      _stopMic().whenComplete(() {
        FlutterForegroundTask.sendDataToMain(WakeMsg.paused);
        unawaited(_status('paused while Maya listens'));
      });
    } else if (data == WakeMsg.resume) {
      // Give the app a moment to release the microphone.
      Timer(const Duration(milliseconds: 400), _resume);
    }
  }

  @override
  void onRepeatEvent(DateTime timestamp) {
    // Recover if the microphone was taken away (e.g. by a phone call).
    if (!_paused && _mic == null) {
      unawaited(_startMic());
    }
  }

  @override
  void onNotificationPressed() {
    FlutterForegroundTask.launchApp();
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _autoResume?.cancel();
    await _stopMic();
    try {
      await _recorder.dispose();
    } catch (_) {}
    _stream?.free();
    _spotter?.free();
  }
}
