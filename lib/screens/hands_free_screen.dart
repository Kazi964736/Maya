import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';

import '../services/phone_brand.dart';
import '../services/voice_id.dart';
import '../services/wake_word.dart';
import '../settings.dart';
import '../ui/orb.dart';
import '../ui/theme.dart';

/// "Hey Maya" hands-free settings and the one-time phone setup it needs.
class HandsFreeScreen extends StatefulWidget {
  const HandsFreeScreen({super.key});

  @override
  State<HandsFreeScreen> createState() => _HandsFreeScreenState();
}

class _HandsFreeScreenState extends State<HandsFreeScreen> with WidgetsBindingObserver {
  final wake = WakeWord.instance;
  final settings = Settings.instance;

  bool _mic = false;
  bool _notifications = false;
  bool _overlay = false;
  bool _battery = false;
  bool _aggressive = false;
  bool _busy = false;
  String? _error;
  double? _sens;
  String _status = '';
  Timer? _poll;
  bool _heardNow = false;

  String _t(String en, String bn, String hi) => switch (settings.language.code) {
        'bn' => bn,
        'hi' => hi,
        _ => en,
      };

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FlutterForegroundTask.addTaskDataCallback(_onTask);
    _refresh();
    // Show what the listening service is doing, live.
    _poll = Timer.periodic(const Duration(seconds: 2), (_) async {
      final st = await wake.status();
      if (mounted && st != _status) {
        setState(() => _status = st);
      }
    });
  }

  void _onTask(Object data) {
    if (data == WakeMsg.wake && mounted) {
      setState(() => _heardNow = true);
      Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() => _heardNow = false);
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FlutterForegroundTask.removeTaskDataCallback(_onTask);
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from a settings page: show what changed.
    if (state == AppLifecycleState.resumed) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final mic = await Permission.microphone.isGranted;
    final notes = await FlutterForegroundTask.checkNotificationPermission() == NotificationPermission.granted;
    final overlay = await FlutterForegroundTask.canDrawOverlays;
    final battery = await FlutterForegroundTask.isIgnoringBatteryOptimizations;
    final aggressive = await isAggressiveBatteryBrand();
    if (mounted) {
      setState(() {
        _mic = mic;
        _notifications = notes;
        _overlay = overlay;
        _battery = battery;
        _aggressive = aggressive;
      });
    }
  }

  Future<void> _toggle(bool on) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    if (on) {
      if (!await Permission.microphone.request().isGranted) {
        setState(() {
          _busy = false;
          _error = _t('Maya needs the microphone for this.', 'এর জন্য মাইক্রোফোনের অনুমতি লাগবে।',
              'इसके लिए माइक्रोफ़ोन की अनुमति चाहिए।');
        });
        return;
      }
      if (await FlutterForegroundTask.checkNotificationPermission() != NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
    }
    final problem = await wake.setEnabled(on);
    FlutterForegroundTask.setOnLockScreenVisibility(on && VoiceId.instance.lockOn);
    await _refresh();
    if (mounted) {
      setState(() {
        _busy = false;
        _error = problem;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final on = wake.enabled;
    return Scaffold(
      appBar: AppBar(title: Text(_t('Hey Maya', 'হে মায়া', 'हे माया'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Center(child: MayaOrb(size: 130, mood: on ? OrbMood.listening : OrbMood.idle)),
          const SizedBox(height: 4),
          Text(
            _t('Talk to Maya without touching the phone', 'ফোন না ছুঁয়েই মায়ার সঙ্গে কথা বলুন',
                'फोन छुए बिना माया से बात करें'),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: MayaColors.text),
          ),
          const SizedBox(height: 6),
          Text(
            _t(
              'Say "Hey Maya", "Hi Maya" or "Okay Maya" — from any app, even with the screen off. '
                  'Then give your command. Listening happens on your phone; nothing is sent anywhere until you speak a command.',
              '"Hey Maya", "Hi Maya" বা "Okay Maya" বলুন — যেকোনো অ্যাপ থেকে, স্ক্রিন বন্ধ থাকলেও। '
                  'তারপর আপনার কথা বলুন। শোনার কাজ ফোনেই হয়।',
              '"Hey Maya", "Hi Maya" या "Okay Maya" बोलें — किसी भी ऐप से, स्क्रीन बंद होने पर भी। '
                  'फिर अपनी बात कहें। सुनने का काम फोन पर ही होता है।',
            ),
            textAlign: TextAlign.center,
            style: const TextStyle(color: MayaColors.textDim, height: 1.45),
          ),
          const SizedBox(height: 20),
          Card(
            child: SwitchListTile(
              value: on,
              onChanged: _busy ? null : _toggle,
              title: Text(_t('Listen for "Hey Maya"', '"Hey Maya" শুনবে', '"Hey Maya" सुनेगी'),
                  style: const TextStyle(color: MayaColors.text, fontWeight: FontWeight.w600)),
              subtitle: Text(
                _t('Uses some battery. A small notification shows while it listens.',
                    'কিছুটা ব্যাটারি খরচ হয়। শোনার সময় একটা ছোট নোটিফিকেশন থাকে।',
                    'थोड़ी बैटरी लगती है। सुनते समय एक छोटा नोटिफ़िकेशन दिखता है।'),
                style: const TextStyle(color: MayaColors.textDim),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: MayaColors.amber)),
          ],
          if (on) ...[
            const SizedBox(height: 8),
            AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _heardNow ? const Color(0x3322C55E) : MayaColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _heardNow ? const Color(0xFF22C55E) : MayaColors.border),
              ),
              child: Row(
                children: [
                  Icon(_heardNow ? Icons.check_circle_rounded : Icons.graphic_eq_rounded,
                      color: _heardNow ? const Color(0xFF22C55E) : MayaColors.violet),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _heardNow
                          ? _t('Heard "Hey Maya"! It works.', '"Hey Maya" শুনেছি! কাজ করছে।', '"Hey Maya" सुन लिया! काम कर रहा है।')
                          : '${_t('Test: say "Hey Maya" now', 'পরীক্ষা: এখন "Hey Maya" বলুন', 'टेस्ट: अभी "Hey Maya" बोलें')}\n'
                              '${_t('Status', 'অবস্থা', 'स्थिति')}: ${_status.isEmpty ? '…' : _status}',
                      style: const TextStyle(color: MayaColors.text, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_t('Sensitivity', 'কত সহজে শুনবে', 'कितनी आसानी से सुने'),
                      style: const TextStyle(color: MayaColors.text, fontWeight: FontWeight.w600)),
                  Text(
                    _t(
                      'If Maya misses "Hey Maya", move right. If she wakes by mistake, move left.',
                      '"Hey Maya" শুনতে না পেলে ডানে সরান। ভুল করে জেগে উঠলে বাঁয়ে সরান।',
                      '"Hey Maya" न सुने तो दाएँ करें। गलती से जागे तो बाएँ करें।',
                    ),
                    style: const TextStyle(color: MayaColors.textDim, fontSize: 13),
                  ),
                  Slider(
                    value: _sens ?? wake.sensitivity,
                    divisions: 10,
                    activeColor: MayaColors.violet,
                    onChanged: (v) => setState(() => _sens = v),
                    onChangeEnd: (v) async {
                      await wake.setSensitivity(v);
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(_t('One-time phone setup', 'একবারের ফোন সেটআপ', 'एक बार का फोन सेटअप'),
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _Step(
            done: _mic,
            title: _t('Microphone', 'মাইক্রোফোন', 'माइक्रोफ़ोन'),
            onFix: () async {
              await Permission.microphone.request();
              await _refresh();
            },
          ),
          _Step(
            done: _notifications,
            title: _t('Notifications', 'নোটিফিকেশন', 'नोटिफ़िकेशन'),
            onFix: () async {
              await FlutterForegroundTask.requestNotificationPermission();
              await _refresh();
            },
          ),
          _Step(
            done: _overlay,
            title: _t('Appear on top (to open when you call her)', 'উপরে দেখানো (ডাকলে খোলার জন্য)',
                'ऊपर दिखाना (बुलाने पर खुलने के लिए)'),
            onFix: FlutterForegroundTask.openSystemAlertWindowSettings,
          ),
          _Step(
            done: _battery,
            title: _t('No battery restriction', 'ব্যাটারি বাধা নেই', 'बैटरी पाबंदी नहीं'),
            onFix: () async {
              await FlutterForegroundTask.requestIgnoreBatteryOptimization();
              await _refresh();
            },
          ),
          if (_aggressive)
            _Step(
              done: null,
              title: _t(
                'Vivo / Xiaomi / Oppo: in App info allow Autostart, "Display pop-up windows while running in background" and background activity',
                'Vivo / Xiaomi / Oppo: App info-তে Autostart, "Display pop-up windows while running in background" আর background চালু করুন',
                'Vivo / Xiaomi / Oppo: App info में Autostart, "Display pop-up windows while running in background" और background चालू करें',
              ),
              onFix: openMayaAppInfo,
            ),
          const SizedBox(height: 16),
          Text(
            _t(
              'Tip: with Voice Lock on, Maya only wakes for your voice and can open over the lock screen.',
              'টিপ: ভয়েস লক চালু থাকলে মায়া শুধু আপনার গলায় জাগবে, আর লক স্ক্রিনের উপরেও খুলবে।',
              'टिप: वॉइस लॉक चालू हो तो माया सिर्फ़ आपकी आवाज़ पर जागेगी और लॉक स्क्रीन पर भी खुलेगी।',
            ),
            style: const TextStyle(color: MayaColors.textDim, fontSize: 13, height: 1.4),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.done, required this.title, required this.onFix});

  /// true = done, false = needs fixing, null = can't be checked (manual step).
  final bool? done;
  final String title;
  final Future<void> Function() onFix;

  @override
  Widget build(BuildContext context) {
    final ok = done == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          ok ? Icons.check_circle_rounded : (done == null ? Icons.info_outline_rounded : Icons.error_outline_rounded),
          color: ok ? const Color(0xFF22C55E) : MayaColors.amber,
        ),
        title: Text(title, style: const TextStyle(color: MayaColors.text, fontSize: 14.5)),
        trailing: ok
            ? null
            : TextButton(
                onPressed: () => onFix(),
                child: const Text('Open'),
              ),
      ),
    );
  }
}
