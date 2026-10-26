import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import '../settings.dart';

/// Recognises the owner's voice, fully on the phone.
///
/// A small speaker-recognition model turns a few seconds of speech into a
/// "voiceprint" (a list of numbers). The owner's voiceprint is saved once;
/// later, a new recording is compared with it.
class VoiceId {
  VoiceId._();
  static final instance = VoiceId._();

  static const _modelName = '3dspeaker_speech_eres2net_base_sv_zh-cn_3dspeaker_16k.onnx';
  static const _modelUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/speaker-recongition-models/$_modelName';
  static const sampleRate = 16000;

  static const _printKey = 'voiceprint';
  static const _lockKey = 'voice_lock';
  static const _strictKey = 'voice_strictness';

  final _settings = Settings.instance;
  sherpa.SpeakerEmbeddingExtractor? _extractor;
  bool _bindingsReady = false;

  /// Loudness while recording, on the same scale as the speech service
  /// (about -2 quiet … 10 loud), so the orb can react to it.
  final level = ValueNotifier<double>(-2);

  // ---- saved state ----

  bool get enrolled => _settings.prefs.getString(_printKey) != null;
  bool get lockOn => _settings.prefs.getBool(_lockKey) ?? false;

  /// Voice Lock is on and everything it needs is in place.
  Future<bool> get active async => lockOn && enrolled && await modelReady();

  Future<void> setLock(bool on) => _settings.prefs.setBool(_lockKey, on);

  /// How similar a voice must be to count as the owner (0.30 relaxed … 0.70 strict).
  double get strictness => _settings.prefs.getDouble(_strictKey) ?? 0.45;
  Future<void> setStrictness(double v) => _settings.prefs.setDouble(_strictKey, v);

  Future<void> forget() async {
    await _settings.prefs.remove(_printKey);
    await _settings.prefs.setBool(_lockKey, false);
  }

  Float32List? get _ownerPrint {
    final raw = _settings.prefs.getString(_printKey);
    if (raw == null) {
      return null;
    }
    try {
      return Float32List.view(Uint8List.fromList(base64Decode(raw)).buffer);
    } catch (_) {
      return null;
    }
  }

  // ---- the model ----

  Future<File> _modelFile() async {
    final dir = await getApplicationSupportDirectory();
    return File('${dir.path}/$_modelName');
  }

  Future<bool> modelReady() async {
    final f = await _modelFile();
    return await f.exists() && await f.length() > 1000000;
  }

  /// Downloads the voice model once (about 40 MB). [onProgress] gets 0..1.
  Future<void> downloadModel(void Function(double) onProgress) async {
    final file = await _modelFile();
    final part = File('${file.path}.part');
    final client = http.Client();
    try {
      final res = await client.send(http.Request('GET', Uri.parse(_modelUrl)));
      if (res.statusCode != 200) {
        throw Exception('Download failed (${res.statusCode})');
      }
      final total = res.contentLength ?? 0;
      var got = 0;
      final sink = part.openWrite();
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) {
          onProgress(got / total);
        }
      }
      await sink.close();
      await part.rename(file.path);
    } finally {
      client.close();
    }
  }

  Future<sherpa.SpeakerEmbeddingExtractor> _getExtractor() async {
    final existing = _extractor;
    if (existing != null) {
      return existing;
    }
    if (!_bindingsReady) {
      sherpa.initBindings();
      _bindingsReady = true;
    }
    final path = (await _modelFile()).path;
    final extractor = sherpa.SpeakerEmbeddingExtractor(
      config: sherpa.SpeakerEmbeddingExtractorConfig(model: path, numThreads: 2, debug: false, provider: 'cpu'),
    );
    _extractor = extractor;
    return extractor;
  }

  Future<Float32List> _embed(Float32List samples) async {
    final extractor = await _getExtractor();
    final stream = extractor.createStream();
    try {
      stream.acceptWaveform(samples: samples, sampleRate: sampleRate);
      stream.inputFinished();
      return _normalise(extractor.compute(stream));
    } finally {
      stream.free();
    }
  }

  // ---- recording ----

  AudioRecorder? _recorder;
  Completer<void>? _stopEarly;

  /// Stops a recording in progress (it still returns what was heard).
  void stopRecording() {
    final c = _stopEarly;
    if (c != null && !c.isCompleted) {
      c.complete();
    }
  }

  /// Records one phrase: starts when you speak, ends after a short pause.
  /// Returns null if no speech was heard or the microphone was refused.
  Future<Float32List?> recordPhrase({
    Duration maxLength = const Duration(seconds: 5),
    Duration waitForSpeech = const Duration(seconds: 5),
  }) async {
    final recorder = _recorder ??= AudioRecorder();
    if (!await recorder.hasPermission()) {
      return null;
    }
    final samples = <double>[];
    final stopEarly = _stopEarly = Completer<void>();
    final done = Completer<void>();
    var carry = <int>[];
    var noise = 0.01;
    var chunks = 0;
    var heardSpeech = false;
    var speechStart = 0;
    var lastLoud = 0;

    final stream = await recorder.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: sampleRate, numChannels: 1),
    );
    final started = DateTime.now();
    final sub = stream.listen((bytes) {
      final data = carry.isEmpty ? bytes : Uint8List.fromList([...carry, ...bytes]);
      final usable = data.length - data.length % 2;
      carry = data.sublist(usable).toList();
      final view = ByteData.sublistView(data, 0, usable);
      var sum = 0.0;
      final n = usable ~/ 2;
      for (var i = 0; i < n; i++) {
        final v = view.getInt16(i * 2, Endian.little) / 32768.0;
        samples.add(v);
        sum += v * v;
      }
      if (n == 0) {
        return;
      }
      final rms = math.sqrt(sum / n);
      chunks++;
      level.value = (rms * 8).clamp(0.0, 1.0) * 12 - 2;
      if (chunks <= 3) {
        noise = math.max(noise, rms);
      }
      final loud = rms > math.max(0.02, noise * 2.5);
      final nowMs = samples.length * 1000 ~/ sampleRate;
      if (loud) {
        if (!heardSpeech) {
          heardSpeech = true;
          speechStart = math.max(0, samples.length - sampleRate ~/ 5);
        }
        lastLoud = nowMs;
      }
      final elapsed = DateTime.now().difference(started);
      final pauseAfterSpeech = heardSpeech && nowMs - lastLoud > 800 && nowMs - speechStart * 1000 ~/ sampleRate > 600;
      final tooLong = heardSpeech && elapsed > maxLength + const Duration(milliseconds: 500);
      final nobody = !heardSpeech && elapsed > waitForSpeech;
      if ((pauseAfterSpeech || tooLong || nobody) && !done.isCompleted) {
        done.complete();
      }
    });

    await Future.any([done.future, stopEarly.future, Future<void>.delayed(maxLength + waitForSpeech)]);
    await sub.cancel();
    try {
      await recorder.stop();
    } catch (_) {}
    level.value = -2;
    _stopEarly = null;

    if (!heardSpeech) {
      return null;
    }
    final end = math.min(samples.length, lastLoud * sampleRate ~/ 1000 + sampleRate ~/ 4);
    if (end - speechStart < sampleRate ~/ 2) {
      return null; // under half a second: too short to judge
    }
    return Float32List.fromList(samples.sublist(speechStart, end));
  }

  // ---- enrolling and checking ----

  /// Saves the owner's voiceprint from a few recordings.
  Future<void> enroll(List<Float32List> clips) async {
    final prints = [for (final c in clips) await _embed(c)];
    final avg = Float32List(prints.first.length);
    for (final p in prints) {
      for (var i = 0; i < avg.length; i++) {
        avg[i] += p[i] / prints.length;
      }
    }
    final owner = _normalise(avg);
    await _settings.prefs.setString(_printKey, base64Encode(owner.buffer.asUint8List()));
  }

  /// How much a recording sounds like the owner: about 0 (different) to 1 (same).
  Future<double> similarity(Float32List clip) async {
    final owner = _ownerPrint;
    if (owner == null) {
      return 0;
    }
    final p = await _embed(clip);
    if (p.length != owner.length) {
      return 0;
    }
    var dot = 0.0;
    for (var i = 0; i < p.length; i++) {
      dot += p[i] * owner[i];
    }
    return dot;
  }

  Future<bool> isOwner(Float32List clip) async => await similarity(clip) >= strictness;

  static Float32List _normalise(Float32List v) {
    var sum = 0.0;
    for (final x in v) {
      sum += x * x;
    }
    final len = math.sqrt(sum);
    if (len == 0) {
      return v;
    }
    return Float32List.fromList([for (final x in v) x / len]);
  }
}
