import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/voice.dart';
import '../services/voice_id.dart';
import '../services/wake_word.dart';
import '../settings.dart';
import '../ui/orb.dart';
import '../ui/theme.dart';

/// Teach Maya your voice, then turn on Voice Lock.
class VoiceIdScreen extends StatefulWidget {
  const VoiceIdScreen({super.key});

  @override
  State<VoiceIdScreen> createState() => _VoiceIdScreenState();
}

class _VoiceIdScreenState extends State<VoiceIdScreen> {
  final id = VoiceId.instance;
  final settings = Settings.instance;

  bool _loading = true;
  bool _modelReady = false;
  double? _download; // 0..1 while downloading
  String? _error;

  bool _teaching = false;
  final _clips = <Float32List>[];
  bool _recording = false;
  bool _saving = false;
  String? _testResult;

  String _t(String en, String bn, String hi) => switch (settings.language.code) {
        'bn' => bn,
        'hi' => hi,
        _ => en,
      };

  List<String> get _prompts => [
        _t('Maya', 'মায়া', 'माया'),
        _t('Maya, this is my voice.', 'মায়া, এটা আমার গলা।', 'माया, यह मेरी आवाज़ है।'),
        _t('Maya', 'মায়া', 'माया'),
        _t('Maya, call Maa.', 'মায়া, মা কে ফোন করো।', 'माया, माँ को फोन करो।'),
        _t('Maya', 'মায়া', 'माया'),
        _t("Maya, what's the weather today?", 'মায়া, আজ আবহাওয়া কেমন?', 'माया, आज मौसम कैसा है?'),
      ];

  @override
  void initState() {
    super.initState();
    id.modelReady().then((ok) {
      if (mounted) {
        setState(() {
          _modelReady = ok;
          _loading = false;
        });
      }
    });
  }

  Future<void> _getModel() async {
    setState(() {
      _download = 0;
      _error = null;
    });
    try {
      await id.downloadModel((p) {
        if (mounted) {
          setState(() => _download = p);
        }
      });
      if (mounted) {
        setState(() {
          _modelReady = true;
          _download = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _download = null;
          _error = _t(
            'Could not download. Check your internet and try again.',
            'ডাউনলোড হয়নি। ইন্টারনেট দেখে আবার চেষ্টা করুন।',
            'डाउनलोड नहीं हुआ। इंटरनेट देखकर फिर कोशिश करें।',
          );
        });
      }
    }
  }

  /// Records with the microphone to ourselves ("Hey Maya" pauses meanwhile).
  Future<Float32List?> _record(Duration max) async {
    await WakeWord.instance.pause();
    try {
      return await id.recordPhrase(maxLength: max);
    } finally {
      WakeWord.instance.resume();
    }
  }

  Future<void> _recordNext() async {
    await Voice.instance.stopSpeaking();
    setState(() {
      _recording = true;
      _error = null;
    });
    final clip = await _record(const Duration(seconds: 6));
    if (!mounted) {
      return;
    }
    setState(() => _recording = false);
    if (clip == null) {
      setState(() => _error = _t(
            "I didn't hear that clearly. Tap and say it again.",
            'ঠিক শুনতে পাইনি। আবার ট্যাপ করে বলুন।',
            'ठीक से सुनाई नहीं दिया। फिर से टैप करके बोलें।',
          ));
      return;
    }
    _clips.add(clip);
    if (_clips.length < _prompts.length) {
      setState(() {});
      return;
    }
    setState(() => _saving = true);
    try {
      await id.enroll(_clips);
      await id.setLock(true);
      if (mounted) {
        setState(() {
          _teaching = false;
          _saving = false;
          _clips.clear();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _clips.clear();
          _error = _t('Something went wrong. Please try again.', 'কিছু ভুল হয়েছে। আবার চেষ্টা করুন।',
              'कुछ गड़बड़ हुई। फिर से कोशिश करें।');
        });
      }
    }
  }

  Future<void> _test() async {
    setState(() {
      _recording = true;
      _testResult = null;
    });
    final clip = await _record(const Duration(seconds: 5));
    if (!mounted) {
      return;
    }
    if (clip == null) {
      setState(() {
        _recording = false;
        _testResult = _t("I didn't hear anything.", 'কিছু শুনতে পাইনি।', 'कुछ सुनाई नहीं दिया।');
      });
      return;
    }
    final score = await id.similarity(clip);
    final ok = score >= id.strictness;
    if (mounted) {
      setState(() {
        _recording = false;
        final pct = (score * 100).clamp(0, 100).round();
        _testResult = ok
            ? _t('✅ That\'s you ($pct% match)', '✅ এটা আপনি ($pct% মিল)', '✅ यह आप हैं ($pct% मेल)')
            : _t('❌ Not matched ($pct% match)', '❌ মেলেনি ($pct% মিল)', '❌ मेल नहीं खाया ($pct% मेल)');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_t('My voice', 'আমার গলা', 'मेरी आवाज़'))),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: _teaching ? _teachView() : _overview(),
            ),
    );
  }

  List<Widget> _overview() {
    return [
      Center(child: MayaOrb(size: 140, mood: _recording ? OrbMood.listening : OrbMood.idle, level: id.level)),
      const SizedBox(height: 8),
      Text(
        _t('Voice Lock', 'ভয়েস লক', 'वॉइस लॉक'),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700, color: MayaColors.text),
      ),
      const SizedBox(height: 6),
      Text(
        _t(
          'Maya learns your voice, so "Hey Maya" only wakes her for you, not for others nearby. '
              'Tapping the mic always works. Your voiceprint stays on this phone.',
          'মায়া আপনার গলা চিনে নেবে, তাই "Hey Maya" বললে শুধু আপনার গলাতেই জাগবে। '
              'মাইকে ট্যাপ করলে সবসময় চলবে। আপনার ভয়েসপ্রিন্ট শুধু এই ফোনেই থাকে।',
          'माया आपकी आवाज़ पहचानेगी, इसलिए "Hey Maya" सिर्फ़ आपकी आवाज़ पर जागेगी। '
              'माइक टैप करने पर हमेशा चलेगी। आपका वॉइसप्रिंट सिर्फ़ इसी फोन में रहता है।',
        ),
        textAlign: TextAlign.center,
        style: const TextStyle(color: MayaColors.textDim, height: 1.45),
      ),
      const SizedBox(height: 24),
      if (!_modelReady) ...[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _t('Step 1: get the voice model', 'ধাপ ১: ভয়েস মডেল নামান', 'चरण 1: वॉइस मॉडल डाउनलोड करें'),
                  style: const TextStyle(fontWeight: FontWeight.w600, color: MayaColors.text),
                ),
                const SizedBox(height: 6),
                Text(
                  _t('One-time download, about 40 MB. Use Wi-Fi if you can.',
                      'একবারই নামাতে হবে, প্রায় ৪০ MB। পারলে Wi-Fi ব্যবহার করুন।',
                      'सिर्फ़ एक बार, लगभग 40 MB। हो सके तो Wi-Fi इस्तेमाल करें।'),
                  style: const TextStyle(color: MayaColors.textDim),
                ),
                const SizedBox(height: 14),
                if (_download != null) ...[
                  LinearProgressIndicator(value: _download! > 0 ? _download : null, color: MayaColors.violet),
                  const SizedBox(height: 6),
                  Text('${((_download ?? 0) * 100).round()}%', style: const TextStyle(color: MayaColors.textDim)),
                ] else
                  FilledButton.icon(
                    onPressed: _getModel,
                    icon: const Icon(Icons.download_rounded),
                    label: Text(_t('Download', 'ডাউনলোড', 'डाउनलोड')),
                  ),
              ],
            ),
          ),
        ),
      ] else if (!id.enrolled) ...[
        FilledButton.icon(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          onPressed: () => setState(() {
            _teaching = true;
            _clips.clear();
            _error = null;
          }),
          icon: const Icon(Icons.record_voice_over_rounded),
          label: Text(_t('Teach Maya my voice', 'মায়াকে আমার গলা চেনাও', 'माया को मेरी आवाज़ सिखाओ')),
        ),
      ] else ...[
        Card(
          child: SwitchListTile(
            value: id.lockOn,
            onChanged: (v) async {
              await id.setLock(v);
              setState(() {});
            },
            title: Text(_t('Voice Lock', 'ভয়েস লক', 'वॉइस लॉक'),
                style: const TextStyle(color: MayaColors.text, fontWeight: FontWeight.w600)),
            subtitle: Text(
              _t('Only obey my voice', 'শুধু আমার গলা শুনবে', 'सिर्फ़ मेरी आवाज़ मानेगी'),
              style: const TextStyle(color: MayaColors.textDim),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_t('Strictness', 'কতটা কড়া', 'कितनी सख़्ती'),
                    style: const TextStyle(color: MayaColors.text, fontWeight: FontWeight.w600)),
                Text(
                  _t(
                    'If Maya refuses you, move left. If she obeys others, move right.',
                    'মায়া আপনাকেই না চিনলে বাঁয়ে সরান। অন্যদের কথা শুনলে ডানে সরান।',
                    'माया आपको न पहचाने तो बाएँ करें। दूसरों की बात माने तो दाएँ करें।',
                  ),
                  style: const TextStyle(color: MayaColors.textDim, fontSize: 13),
                ),
                Slider(
                  value: id.strictness,
                  min: 0.30,
                  max: 0.70,
                  divisions: 8,
                  label: '${(id.strictness * 100).round()}%',
                  activeColor: MayaColors.violet,
                  onChanged: (v) async {
                    await id.setStrictness(v);
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          onPressed: _recording ? null : _test,
          icon: const Icon(Icons.mic_rounded),
          label: Text(_recording
              ? _t('Listening… say "Maya"', 'শুনছি… "মায়া" বলুন', 'सुन रही हूँ… "माया" बोलें')
              : _t('Test: say "Maya"', 'পরীক্ষা: "মায়া" বলুন', 'टेस्ट: "माया" बोलें')),
        ),
        if (_testResult != null) ...[
          const SizedBox(height: 10),
          Text(_testResult!, textAlign: TextAlign.center, style: const TextStyle(color: MayaColors.text, fontSize: 16)),
        ],
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => setState(() {
            _teaching = true;
            _clips.clear();
            _error = null;
          }),
          child: Text(_t('Teach again', 'আবার শেখাও', 'फिर से सिखाओ')),
        ),
        TextButton(
          style: TextButton.styleFrom(foregroundColor: MayaColors.danger),
          onPressed: () async {
            await id.forget();
            setState(() {});
          },
          child: Text(_t('Delete my voiceprint', 'আমার ভয়েসপ্রিন্ট মুছে দাও', 'मेरा वॉइसप्रिंट मिटाओ')),
        ),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: MayaColors.amber)),
      ],
    ];
  }

  List<Widget> _teachView() {
    final step = _clips.length;
    final total = _prompts.length;
    return [
      const SizedBox(height: 4),
      LinearProgressIndicator(
        value: step / total,
        color: MayaColors.violet,
        backgroundColor: MayaColors.surfaceHigh,
        borderRadius: BorderRadius.circular(4),
      ),
      const SizedBox(height: 6),
      Text(
        _t('${step + 1 > total ? total : step + 1} of $total', '$total-এর মধ্যে ${step + 1 > total ? total : step + 1}',
            '$total में से ${step + 1 > total ? total : step + 1}'),
        style: const TextStyle(color: MayaColors.textDim),
      ),
      const SizedBox(height: 16),
      Center(
        child: GestureDetector(
          onTap: _recording || _saving ? id.stopRecording : _recordNext,
          child: MayaOrb(size: 190, mood: _recording ? OrbMood.listening : (_saving ? OrbMood.thinking : OrbMood.idle), level: id.level),
        ),
      ),
      const SizedBox(height: 12),
      Text(
        _saving
            ? _t('Learning your voice…', 'আপনার গলা শিখছি…', 'आपकी आवाज़ सीख रही हूँ…')
            : _recording
                ? _t('Listening… speak now', 'শুনছি… এখন বলুন', 'सुन रही हूँ… अब बोलें')
                : _t('Tap the orb and say:', 'অর্বে ট্যাপ করে বলুন:', 'ऑर्ब पर टैप करके बोलें:'),
        textAlign: TextAlign.center,
        style: const TextStyle(color: MayaColors.textDim, fontSize: 15),
      ),
      const SizedBox(height: 10),
      if (!_saving && step < total)
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
          decoration: BoxDecoration(
            color: MayaColors.surface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: MayaColors.violet.withValues(alpha: 0.4)),
          ),
          child: Text(
            '“${_prompts[step]}”',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w600, color: MayaColors.text, height: 1.3),
          ),
        ),
      const SizedBox(height: 16),
      Text(
        _t('Speak normally, in a quiet place, at your usual distance from the phone.',
            'চুপচাপ জায়গায়, স্বাভাবিক গলায়, ফোন যেমন ধরেন তেমন ধরে বলুন।',
            'शांत जगह पर, सामान्य आवाज़ में, फोन जैसे पकड़ते हैं वैसे पकड़कर बोलें।'),
        textAlign: TextAlign.center,
        style: const TextStyle(color: MayaColors.textDim, fontSize: 13),
      ),
      if (_error != null) ...[
        const SizedBox(height: 12),
        Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: MayaColors.amber)),
      ],
      const SizedBox(height: 16),
      TextButton(
        onPressed: _recording || _saving
            ? null
            : () => setState(() {
                  _teaching = false;
                  _clips.clear();
                }),
        child: Text(_t('Cancel', 'বাতিল', 'रद्द करें')),
      ),
    ];
  }
}
