import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:image_picker/image_picker.dart';

import '../brain/action.dart';
import '../brain/gemini.dart';
import '../brain/rule_parser.dart';
import '../services/contacts.dart';
import '../services/executor.dart';
import '../services/phone_brand.dart';
import '../services/voice.dart';
import '../services/voice_id.dart';
import '../services/wake_word.dart';
import '../settings.dart';
import '../ui/orb.dart';
import '../ui/theme.dart';
import 'interpreter_screen.dart';
import 'reminders_screen.dart';
import 'settings_screen.dart';

class ChatMessage {
  const ChatMessage({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;

  Map<String, dynamic> toJson() => {'u': fromUser, 't': text};
  static ChatMessage? fromJson(dynamic j) =>
      j is Map && j['t'] is String ? ChatMessage(fromUser: j['u'] == true, text: j['t'] as String) : null;
}

const _suggestions = {
  'bn': [
    'মা কে ফোন করো',
    'সকাল ৬টায় অ্যালার্ম দাও আর ৮টায় মাকে ফোনের কথা মনে করিয়ে দাও',
    'মেসেজ পড়ো',
    'টর্চ জ্বালাও',
    'আজকের ক্রিকেট ম্যাচ কে জিতল?',
    'মনে রেখো বাইক B2-তে রাখা আছে',
  ],
  'hi': [
    'माँ को फोन करो',
    'सुबह 6 बजे अलार्म लगाओ और 8 बजे माँ को फोन करना याद दिलाओ',
    'मैसेज पढ़ो',
    'टॉर्च जलाओ',
    'आज क्रिकेट मैच कौन जीता?',
    'याद रखना बाइक B2 पर खड़ी है',
  ],
  'en': [
    'Call Maa',
    'Alarm at 6 am and remind me to call Maa at 8',
    'Read my messages',
    'Turn on the torch',
    'Who won the cricket match today?',
    'Remember my bike is on level B2',
  ],
};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver implements ActionUi {
  final settings = Settings.instance;
  final voice = Voice.instance;
  final voiceId = VoiceId.instance;
  final wake = WakeWord.instance;
  bool _resumed = true;
  bool _checkingVoice = false;
  String _checkText = '';
  late final gemini = Gemini(settings);
  late final executor = Executor(settings, gemini, this);
  final _parser = const RuleParser();
  final _input = TextEditingController();
  final _messages = <ChatMessage>[];
  bool _busy = false;

  static const _historyKey = 'chat_history';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    FlutterForegroundTask.addTaskDataCallback(_onWakeMessage);
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Hands-free listening can only be (re)started while Maya is open.
      unawaited(wake.start());
      // Show over the lock screen only when Voice Lock protects it.
      FlutterForegroundTask.setOnLockScreenVisibility(wake.enabled && voiceId.lockOn);
      final fromTile = await _takeListenRequest();
      if (settings.listenOnOpen || fromTile) {
        // Give speech set-up a moment on first launch.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          _listen(fromWake: fromTile);
        }
      }
    });
  }

  /// True if the Quick Settings tile asked Maya to listen in the last few seconds.
  Future<bool> _takeListenRequest() async {
    try {
      await settings.prefs.reload();
      final at = settings.prefs.getInt('listen_request');
      if (at == null) {
        return false;
      }
      await settings.prefs.remove('listen_request');
      return DateTime.now().millisecondsSinceEpoch - at < 15000;
    } catch (_) {
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _resumed = state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      unawaited(wake.start());
      _takeListenRequest().then((asked) {
        if (asked && mounted && !voice.listening.value && !_checkingVoice) {
          _listen(fromWake: true);
        }
      });
    }
  }

  /// "Hey Maya" was heard by the listening service.
  void _onWakeMessage(Object data) {
    if (data != WakeMsg.wake || !_resumed || !mounted) {
      return; // if Maya is in the background, she handles it when she opens
    }
    _takeListenRequest().then((asked) {
      if (asked && mounted && !voice.listening.value && !_checkingVoice && !_busy) {
        _listen(fromWake: true);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FlutterForegroundTask.removeTaskDataCallback(_onWakeMessage);
    _input.dispose();
    super.dispose();
  }

  void _loadHistory() {
    final raw = settings.prefs.getString(_historyKey);
    if (raw == null) {
      return;
    }
    try {
      _messages.addAll((jsonDecode(raw) as List).map(ChatMessage.fromJson).whereType<ChatMessage>());
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    final keep = _messages.length > 60 ? _messages.sublist(_messages.length - 60) : _messages;
    await settings.prefs.setString(_historyKey, jsonEncode(keep.map((m) => m.toJson()).toList()));
  }

  void _add(ChatMessage m) {
    setState(() => _messages.add(m));
    _saveHistory();
  }

  Future<void> _listen({bool fromWake = false}) async {
    if (_checkingVoice) {
      voiceId.stopRecording();
      return;
    }
    if (voice.listening.value) {
      await voice.stopListening();
      return;
    }
    if (_busy) {
      return;
    }
    // The microphone can't be shared: pause "Hey Maya" while Maya listens.
    wake.pause();
    if (wake.enabled) {
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    try {
      await _listenNow(fromWake);
    } finally {
      wake.resume();
    }
  }

  Future<void> _listenNow(bool fromWake) async {
    if (!voice.canListen && !await voice.init()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Speech recognition is not available. Allow the microphone, or type instead.'),
          ),
        );
      }
      return;
    }
    // "Hey Maya" already checked the voice in the background.
    final alreadyChecked = fromWake && (settings.prefs.getBool(WakeKeys.verified) ?? false);
    await settings.prefs.remove(WakeKeys.verified);
    if (!alreadyChecked && await voiceId.active) {
      if (!await _checkOwner()) {
        return;
      }
      // Give the microphone a moment to pass from the recorder to speech recognition.
      await Future<void>.delayed(const Duration(milliseconds: 200));
      if (!mounted) {
        return;
      }
    }
    final words = await voice.listen(settings.language);
    if (words.isNotEmpty && mounted) {
      await _handle(words, fromVoice: true);
    }
  }

  /// Voice Lock: hear "Maya" and check it is the owner speaking.
  Future<bool> _checkOwner() async {
    await voice.stopSpeaking();
    setState(() {
      _checkingVoice = true;
      _checkText = _t('Say “Maya”', 'বলুন “মায়া”', 'बोलें “माया”');
    });
    var ok = false;
    String? problem;
    try {
      // Two tries: a short word in a noisy room can be misjudged once.
      for (var attempt = 0; attempt < 2 && !ok; attempt++) {
        if (attempt == 1 && mounted) {
          setState(() => _checkText = _t('Say “Maya” once more', 'আর একবার “মায়া” বলুন', 'एक बार और “माया” बोलें'));
        }
        final clip = await voiceId.recordPhrase(maxLength: const Duration(seconds: 3));
        if (clip == null) {
          problem = _t("I didn't hear you. Tap and say “Maya”.", 'শুনতে পাইনি। ট্যাপ করে “মায়া” বলুন।',
              'सुनाई नहीं दिया। टैप करके “माया” बोलें।');
          break;
        }
        if (mounted) {
          setState(() => _checkText = _t('Checking your voice…', 'গলা মিলিয়ে দেখছি…', 'आवाज़ मिला रही हूँ…'));
        }
        ok = await voiceId.isOwner(clip);
      }
    } catch (e) {
      debugPrint('Voice check failed: $e');
      problem = _t(
        'Voice check is not working. You can turn off Voice Lock in Settings › My voice.',
        'গলা মেলানো কাজ করছে না। সেটিংস › আমার গলা থেকে ভয়েস লক বন্ধ করতে পারেন।',
        'आवाज़ जाँच काम नहीं कर रही। सेटिंग्स › मेरी आवाज़ में वॉइस लॉक बंद कर सकते हैं।',
      );
    }
    if (!mounted) {
      return false;
    }
    setState(() => _checkingVoice = false);
    if (problem != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(problem)));
      return false;
    }
    if (!ok) {
      final reply = _t('Sorry, I only listen to my owner.', 'দুঃখিত, আমি শুধু আমার মালিকের কথা শুনি।',
          'माफ़ कीजिए, मैं सिर्फ़ अपने मालिक की बात सुनती हूँ।');
      final tip = _t(
        'If this is you: Settings › My voice › Teach again, or move Strictness to the left.',
        'আপনিই হলে: সেটিংস › আমার গলা › আবার শেখাও, বা কড়াভাব বাঁয়ে সরান।',
        'अगर आप ही हैं: सेटिंग्स › मेरी आवाज़ › फिर से सिखाओ, या सख़्ती बाईं ओर करें।',
      );
      _add(ChatMessage(fromUser: false, text: '🔒 $reply\n$tip'));
      if (settings.speakReplies) {
        await voice.speak(reply, settings.language);
      }
      return false;
    }
    HapticFeedback.mediumImpact();
    return true;
  }

  /// Clear phone commands are done instantly on the phone, without asking the AI
  /// (faster, works offline and saves free AI requests).
  static const _instant = {
    ActionType.phone,
    ActionType.alarm,
    ActionType.timer,
    ActionType.openApp,
    ActionType.readMessages,
    ActionType.interpreter,
    ActionType.briefing,
    ActionType.list,
  };

  Future<void> _handle(String text, {AssistantAction? forced, bool fromVoice = false}) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _busy) {
      return;
    }
    await voice.stopSpeaking();
    final history = _messages.map((m) => ChatTurn(fromUser: m.fromUser, text: m.text)).toList();
    _add(ChatMessage(fromUser: true, text: trimmed));
    setState(() => _busy = true);

    final lang = settings.language;
    AssistantAction action;
    String? aiProblem;
    if (forced != null) {
      action = forced;
    } else if (settings.hasAi) {
      final quick = _parser.parse(trimmed);
      if (_instant.contains(quick.type)) {
        action = quick;
      } else {
        try {
          action = await gemini.understand(trimmed, history, lang);
        } on GeminiException catch (e) {
          aiProblem = e.message;
          action = quick;
        }
      }
    } else {
      action = _parser.parse(trimmed);
    }

    var reply = await executor.run(action, heard: trimmed, history: history);
    if (aiProblem != null && action.type == ActionType.answer) {
      reply = aiProblem;
    }
    if (!mounted) {
      return;
    }
    _add(ChatMessage(fromUser: false, text: reply));
    setState(() => _busy = false);

    if (settings.speakReplies) {
      await voice.speak(reply, lang);
    }
    final keepTalking = {ActionType.answer, ActionType.weather, ActionType.briefing, ActionType.readMessages, ActionType.recall}
        .contains(action.type);
    // Maya asked something back ("Which Rahul?", "What time?"): listen for the answer,
    // like a person would, even when conversation mode is off.
    final askedBack = fromVoice && RegExp(r'[?？]\s*$').hasMatch(reply.trim());
    if (((settings.conversationMode && keepTalking) || askedBack) && mounted) {
      _listen();
    }
  }

  Future<void> _explainPhoto() async {
    final lang = settings.language;
    if (!settings.hasAi) {
      _add(ChatMessage(fromUser: false, text: phrase('need_ai', lang)));
      return;
    }
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Show me a bill, letter, medicine or anything — I\'ll explain it.'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_camera),
              title: const Text('Take a photo'),
              onTap: () => Navigator.pop(ctx, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from gallery'),
              onTap: () => Navigator.pop(ctx, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source == null) {
      return;
    }
    final XFile? file;
    try {
      file = await ImagePicker().pickImage(source: source, maxWidth: 1600, imageQuality: 80);
    } catch (e) {
      _add(ChatMessage(fromUser: false, text: phrase('failed', lang)));
      return;
    }
    if (file == null) {
      return;
    }
    final bytes = await file.readAsBytes();
    _add(const ChatMessage(fromUser: true, text: '📷 Photo'));
    setState(() => _busy = true);
    String reply;
    try {
      final mime = file.path.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      reply = await gemini.explainImage(bytes, mime, lang, question: _input.text);
      _input.clear();
    } on GeminiException catch (e) {
      reply = e.message;
    }
    if (!mounted) {
      return;
    }
    _add(ChatMessage(fromUser: false, text: reply));
    setState(() => _busy = false);
    if (settings.speakReplies) {
      await voice.speak(reply, lang);
    }
  }

  // ---- Questions the executor asks on screen ----

  @override
  Future<FoundContact?> chooseContact(String spoken, List<FoundContact> options) async {
    if (!mounted) {
      return null;
    }
    await voice.stopSpeaking();
    if (!mounted) {
      return null;
    }
    return showDialog<FoundContact>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(_t('Which $spoken?', 'কোন $spoken?', 'कौन से $spoken?')),
        children: [
          for (final c in options)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, c),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: MayaColors.violet.withValues(alpha: 0.2),
                  foregroundColor: MayaColors.text,
                  child: Text(c.name.trim().isEmpty ? '?' : c.name.trim().characters.first.toUpperCase()),
                ),
                title: Text(c.name),
                subtitle: Text(c.number),
              ),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t('Cancel', 'বাতিল', 'रद्द करें')),
          ),
        ],
      ),
    );
  }

  @override
  Future<bool> confirmCall(FoundContact contact) async {
    if (!mounted) {
      return false;
    }
    final go = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CallCountdown(
        contact: contact,
        cancelLabel: _t('Cancel', 'বাতিল', 'रद्द करें'),
        callingLabel: _t('Calling in 3 seconds…', '৩ সেকেন্ডে ফোন যাবে…', '3 सेकंड में कॉल होगी…'),
      ),
    );
    return go ?? false;
  }

  @override
  Future<bool> confirmSend(String to, String text) async {
    if (!mounted) {
      return false;
    }
    await voice.stopSpeaking();
    if (!mounted) {
      return false;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.send_rounded, color: MayaColors.violet),
        title: Text(_t('Send to $to?', '$to-কে পাঠাব?', '$to को भेजूँ?'), textAlign: TextAlign.center),
        content: Text('“$text”', textAlign: TextAlign.center, style: const TextStyle(fontSize: 17)),
        actionsAlignment: MainAxisAlignment.spaceBetween,
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(_t('Cancel', 'বাতিল', 'रद्द करें'))),
          FilledButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.send_rounded),
            label: Text(_t('Send', 'পাঠাও', 'भेजो')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  @override
  Future<void> openInterpreter() async {
    if (!mounted) {
      return;
    }
    await voice.stopSpeaking();
    if (!mounted) {
      return;
    }
    wake.pause();
    unawaited(
      Navigator.push(context, MaterialPageRoute(builder: (_) => const InterpreterScreen())).whenComplete(wake.resume),
    );
  }

  @override
  Future<void> showReliabilityTip() async {
    if (!mounted) {
      return;
    }
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('Make reminders reliable', 'রিমাইন্ডার যেন ঠিক সময়ে আসে', 'रिमाइंडर समय पर आएँ')),
        content: Text(_t(
          'Your phone may stop Maya in the background to save battery, so alarms and reminders can be late. '
              'In App info, allow Autostart / background activity and set Battery to "No restrictions".',
          'ব্যাটারি বাঁচাতে আপনার ফোন মায়াকে বন্ধ করে দিতে পারে, তাতে অ্যালার্ম আর রিমাইন্ডার দেরিতে আসবে। '
              'App info-তে Autostart / background চালু করুন আর Battery-তে "No restrictions" দিন।',
          'बैटरी बचाने के लिए फोन माया को बंद कर सकता है, जिससे अलार्म और रिमाइंडर देर से आएँगे। '
              'App info में Autostart / background चालू करें और Battery में "No restrictions" चुनें।',
        )),
        actions: [
          TextButton(onPressed: () => openBatterySettings(), child: const Text('Battery')),
          TextButton(onPressed: () => openMayaAppInfo(), child: const Text('App info')),
          FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK')),
        ],
      ),
    );
  }

  /// Picks the text for the current language.
  String _t(String en, String bn, String hi) => switch (settings.language.code) {
        'bn' => bn,
        'hi' => hi,
        _ => en,
      };


  String get _greeting {
    final h = DateTime.now().hour;
    final name = settings.userName.isEmpty ? '' : ', ${settings.userName}';
    if (h < 12) {
      return _t('Good morning$name', 'সুপ্রভাত$name', 'सुप्रभात$name');
    }
    if (h < 17) {
      return _t('Good afternoon$name', 'শুভ দুপুর$name', 'नमस्ते$name');
    }
    return _t('Good evening$name', 'শুভ সন্ধ্যা$name', 'शुभ संध्या$name');
  }

  Widget _languageBanner(LanguageProblem problem) {
    final name = problem.language.label;
    final isVoice = problem.kind == 'voice';
    final text = isVoice
        ? _t(
            'No $name voice is installed, so replies are read in English.',
            '$name ভয়েস ইনস্টল নেই, তাই উত্তর ইংরেজিতে পড়ছে।',
            '$name आवाज़ इंस्टॉल नहीं है, इसलिए जवाब अंग्रेज़ी में पढ़े जा रहे हैं।',
          )
        : _t(
            "Your phone may not understand $name speech yet.",
            'আপনার ফোন হয়তো এখনও $name কথা বোঝে না।',
            'आपका फोन शायद अभी $name नहीं समझता।',
          );
    void dismiss() {
      settings.prefs.setBool('dismissed_${problem.key}', true);
      voice.languageProblem.value = null;
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
      decoration: BoxDecoration(
        color: MayaColors.amber.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: MayaColors.amber.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: MayaColors.amber, size: 22),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(color: MayaColors.text, fontSize: 13.5, height: 1.3))),
          TextButton(
            onPressed: () => isVoice ? openVoiceSettings() : openSpeechSettings(),
            style: TextButton.styleFrom(foregroundColor: MayaColors.amber, visualDensity: VisualDensity.compact),
            child: Text(_t('Fix', 'ঠিক করুন', 'ठीक करें')),
          ),
          IconButton(
            onPressed: dismiss,
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close_rounded, size: 18, color: MayaColors.textDim),
          ),
        ],
      ),
    );
  }

  Future<void> _clearChat() async {
    setState(_messages.clear);
    await _saveHistory();
  }

  void _send() {
    final t = _input.text;
    _input.clear();
    FocusScope.of(context).unfocus();
    _handle(t);
  }

  OrbMood get _mood {
    if (voice.listening.value) {
      return OrbMood.listening;
    }
    if (_busy) {
      return OrbMood.thinking;
    }
    if (voice.speaking.value) {
      return OrbMood.speaking;
    }
    return OrbMood.idle;
  }

  @override
  Widget build(BuildContext context) {
    final lang = settings.language;
    final state = Listenable.merge([voice.listening, voice.speaking]);
    return Scaffold(
      backgroundColor: MayaColors.bg,
      body: Stack(
        children: [
          const Positioned.fill(child: _Backdrop()),
          SafeArea(
            child: Column(
              children: [
                _header(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: _LanguageSwitch(
                    selected: lang.code,
                    onChanged: (code) async {
                      await settings.update(language: languageByCode(code));
                      if (mounted) {
                        setState(() {});
                      }
                    },
                  ),
                ),
                ValueListenableBuilder<LanguageProblem?>(
                  valueListenable: voice.languageProblem,
                  builder: (_, problem, __) => AnimatedSize(
                    duration: const Duration(milliseconds: 250),
                    child: problem == null ||
                            problem.language.code != lang.code ||
                            settings.prefs.getBool('dismissed_${problem.key}') == true
                        ? const SizedBox(width: double.infinity)
                        : _languageBanner(problem),
                  ),
                ),
                Expanded(
                  child: ListenableBuilder(
                    listenable: state,
                    builder: (_, __) => AnimatedSwitcher(
                      duration: const Duration(milliseconds: 300),
                      child: _messages.isEmpty && !_busy
                          ? _Welcome(
                              key: const ValueKey('welcome'),
                              greeting: _greeting,
                              subtitle: _t(
                                'Tap the orb and speak in বাংলা, हिंदी or English',
                                'অর্বে ট্যাপ করে বাংলা, हिंदी বা English-এ বলুন',
                                'ऑर्ब पर टैप करके বাংলা, हिंदी या English में बोलें',
                              ),
                              mood: _mood,
                              level: voice.soundLevel,
                              onOrbTap: _listen,
                              items: _suggestions[lang.code]!,
                              onTap: _handle,
                              hasAi: settings.hasAi,
                            )
                          : _chat(),
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: state,
                  builder: (_, __) => AnimatedSwitcher(
                    duration: const Duration(milliseconds: 250),
                    transitionBuilder: (child, anim) => FadeTransition(
                      opacity: anim,
                      child: SizeTransition(sizeFactor: anim, axisAlignment: -1, child: child),
                    ),
                    child: voice.listening.value || _checkingVoice ? _listeningPanel(lang) : _composer(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 4),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: const BoxDecoration(shape: BoxShape.circle, gradient: MayaColors.brand),
          ),
          const SizedBox(width: 10),
          const Text(
            'Maya',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: 0.3, color: MayaColors.text),
          ),
          const Spacer(),
          _RoundIcon(
            icon: Icons.wb_sunny_outlined,
            tooltip: 'Good morning briefing',
            onTap: _busy ? null : () => _handle('☀️ Briefing', forced: const AssistantAction(type: ActionType.briefing)),
          ),
          _RoundIcon(
            icon: Icons.notifications_none_rounded,
            tooltip: 'Reminders',
            onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RemindersScreen())),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded, color: MayaColors.text),
            color: MayaColors.surfaceHigh,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (v) async {
              if (v == 'settings') {
                await Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()));
                if (mounted) {
                  setState(() {});
                }
              } else if (v == 'clear') {
                await _clearChat();
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'settings',
                child: Row(children: [
                  const Icon(Icons.tune_rounded, size: 20),
                  const SizedBox(width: 12),
                  Text(_t('Settings', 'সেটিংস', 'सेटिंग्स')),
                ]),
              ),
              PopupMenuItem(
                value: 'clear',
                child: Row(children: [
                  const Icon(Icons.delete_sweep_outlined, size: 20),
                  const SizedBox(width: 12),
                  Text(_t('Clear chat', 'চ্যাট মুছুন', 'चैट साफ़ करें')),
                ]),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chat() {
    return ListView.builder(
      key: const ValueKey('chat'),
      reverse: true,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      itemCount: _messages.length + (_busy ? 1 : 0),
      itemBuilder: (_, i) {
        if (_busy && i == 0) {
          return const _MayaRow(child: _TypingDots());
        }
        final m = _messages[_messages.length - 1 - (i - (_busy ? 1 : 0))];
        return m.fromUser ? _UserBubble(text: m.text) : _MayaRow(child: _MayaText(text: m.text));
      },
    );
  }

  Widget _listeningPanel(AppLanguage lang) {
    return Container(
      key: const ValueKey('listening'),
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      decoration: BoxDecoration(
        color: MayaColors.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: MayaColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_checkingVoice)
            Text(
              _checkText,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w600, color: MayaColors.text),
            )
          else
          ValueListenableBuilder<String>(
            valueListenable: voice.heard,
            builder: (_, heard, __) => AnimatedSwitcher(
              duration: const Duration(milliseconds: 150),
              child: Text(
                heard.isEmpty ? _t('Listening…', 'শুনছি…', 'सुन रही हूँ…') : heard,
                key: ValueKey(heard.isEmpty),
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: heard.isEmpty ? 18 : 22,
                  height: 1.3,
                  fontWeight: FontWeight.w500,
                  color: heard.isEmpty ? MayaColors.textDim : MayaColors.text,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: _listen,
            child: MayaOrb(
              size: 150,
              mood: OrbMood.listening,
              level: _checkingVoice ? voiceId.level : voice.soundLevel,
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: MayaColors.violet.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_checkingVoice) ...[
                      const Icon(Icons.lock_rounded, size: 13, color: MayaColors.text),
                      const SizedBox(width: 4),
                    ],
                    Text(
                      _checkingVoice ? _t('Voice Lock', 'ভয়েস লক', 'वॉइस लॉक') : lang.label,
                      style: const TextStyle(color: MayaColors.text, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text(
                _t('Tap the orb to stop', 'থামাতে অর্বে ট্যাপ করুন', 'रोकने के लिए ऑर्ब पर टैप करें'),
                style: const TextStyle(color: MayaColors.textDim, fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _composer() {
    final hasText = _input.text.trim().isNotEmpty;
    final speaking = voice.speaking.value;
    return Padding(
      key: const ValueKey('composer'),
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints: const BoxConstraints(minHeight: 56),
              padding: const EdgeInsets.only(left: 4, right: 4),
              decoration: BoxDecoration(
                color: MayaColors.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: MayaColors.border),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: IconButton(
                      tooltip: 'Explain a photo',
                      icon: const Icon(Icons.photo_camera_outlined, color: MayaColors.textDim),
                      onPressed: _busy ? null : _explainPhoto,
                    ),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 4,
                      style: const TextStyle(color: MayaColors.text, fontSize: 16),
                      decoration: InputDecoration(
                        hintText: _t('Ask Maya…', 'মায়াকে বলুন…', 'माया से पूछें…'),
                        filled: false,
                        border: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 17),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  if (hasText)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: IconButton(
                        icon: const Icon(Icons.arrow_upward_rounded, color: MayaColors.text),
                        style: IconButton.styleFrom(backgroundColor: MayaColors.violet),
                        onPressed: _send,
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 10),
          _MicButton(
            busy: _busy,
            speaking: speaking,
            onTap: speaking ? voice.stopSpeaking : _listen,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pieces of the home screen
// ---------------------------------------------------------------------------

class _Backdrop extends StatelessWidget {
  const _Backdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -1.1),
          radius: 1.3,
          colors: [MayaColors.bgTop, MayaColors.bg],
          stops: [0.0, 0.7],
        ),
      ),
    );
  }
}

class _RoundIcon extends StatelessWidget {
  const _RoundIcon({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onTap,
        icon: Icon(icon, color: MayaColors.text, size: 22),
        style: IconButton.styleFrom(backgroundColor: Colors.white.withValues(alpha: 0.06)),
      ),
    );
  }
}

class _LanguageSwitch extends StatelessWidget {
  const _LanguageSwitch({required this.selected, required this.onChanged});
  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final found = languages.indexWhere((l) => l.code == selected);
    final index = found < 0 ? 0 : found;
    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: MayaColors.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: MayaColors.border),
      ),
      child: LayoutBuilder(
        builder: (_, box) {
          final w = box.maxWidth / languages.length;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                left: w * index,
                top: 0,
                bottom: 0,
                width: w,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: MayaColors.brand,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(color: MayaColors.violet.withValues(alpha: 0.45), blurRadius: 14)],
                  ),
                ),
              ),
              Row(
                children: [
                  for (final l in languages)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(l.code),
                        child: Center(
                          child: Text(
                            l.label,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: l.code == selected ? FontWeight.w600 : FontWeight.w400,
                              color: l.code == selected ? Colors.white : MayaColors.textDim,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _Welcome extends StatelessWidget {
  const _Welcome({
    super.key,
    required this.greeting,
    required this.subtitle,
    required this.mood,
    required this.level,
    required this.onOrbTap,
    required this.items,
    required this.onTap,
    required this.hasAi,
  });

  final String greeting;
  final String subtitle;
  final OrbMood mood;
  final ValueNotifier<double> level;
  final VoidCallback onOrbTap;
  final List<String> items;
  final void Function(String) onTap;
  final bool hasAi;

  static const _icons = [
    Icons.call_rounded,
    Icons.alarm_rounded,
    Icons.mark_chat_unread_rounded,
    Icons.flashlight_on_rounded,
    Icons.sports_cricket_rounded,
    Icons.bookmark_rounded,
  ];
  static const _tints = [
    MayaColors.cyan,
    MayaColors.pink,
    Color(0xFF22C55E),
    MayaColors.amber,
    MayaColors.violet,
    MayaColors.cyan,
  ];

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
      children: [
        const SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: onOrbTap,
            child: MayaOrb(size: 200, mood: mood, level: level),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          greeting,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: MayaColors.text, height: 1.2),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 14.5, color: MayaColors.textDim, height: 1.4),
        ),
        const SizedBox(height: 24),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 2.3,
          children: [
            for (var i = 0; i < items.length; i++)
              _SuggestionCard(
                text: items[i],
                icon: _icons[i % _icons.length],
                tint: _tints[i % _tints.length],
                onTap: () => onTap(items[i]),
              ),
          ],
        ),
        if (!hasAi) ...[
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: MayaColors.violet.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: MayaColors.violet.withValues(alpha: 0.25)),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome_rounded, color: MayaColors.violet, size: 20),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Add a free Gemini key in Settings to ask Maya anything and read photos.',
                    style: TextStyle(color: MayaColors.textDim, fontSize: 13, height: 1.35),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({required this.text, required this.icon, required this.tint, required this.onTap});
  final String text;
  final IconData icon;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: MayaColors.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: MayaColors.border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: tint.withValues(alpha: 0.15), shape: BoxShape.circle),
                child: Icon(icon, color: tint, size: 19),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: MayaColors.text, fontSize: 13.5, height: 1.25),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MicButton extends StatelessWidget {
  const _MicButton({required this.busy, required this.speaking, required this.onTap});
  final bool busy;
  final bool speaking;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: busy ? null : onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: MayaColors.brand,
          boxShadow: [
            BoxShadow(color: MayaColors.violet.withValues(alpha: 0.55), blurRadius: 20, spreadRadius: 1),
          ],
        ),
        child: busy
            ? const Padding(
                padding: EdgeInsets.all(17),
                child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
              )
            : Icon(speaking ? Icons.stop_rounded : Icons.mic_rounded, color: Colors.white, size: 28),
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(top: 10, bottom: 4, left: 48),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: const BoxDecoration(
          gradient: MayaColors.brand,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(22),
            topRight: Radius.circular(22),
            bottomLeft: Radius.circular(22),
            bottomRight: Radius.circular(6),
          ),
        ),
        child: SelectableText(text, style: const TextStyle(color: Colors.white, fontSize: 16, height: 1.35)),
      ),
    );
  }
}

/// Maya's replies: a small orb avatar and text on a soft glass card.
class _MayaRow extends StatelessWidget {
  const _MayaRow({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4, right: 40),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(
                center: Alignment(-0.3, -0.4),
                colors: [MayaColors.pink, MayaColors.violet, Color(0xFF2A1A5E)],
                stops: [0.0, 0.55, 1.0],
              ),
              boxShadow: [BoxShadow(color: MayaColors.violet.withValues(alpha: 0.5), blurRadius: 10)],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: BoxDecoration(
                color: MayaColors.surface,
                border: Border.all(color: MayaColors.border),
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(22),
                  topRight: Radius.circular(22),
                  bottomLeft: Radius.circular(6),
                  bottomRight: Radius.circular(22),
                ),
              ),
              child: child,
            ),
          ),
        ],
      ),
    );
  }
}

class _MayaText extends StatelessWidget {
  const _MayaText({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return SelectableText(text, style: const TextStyle(color: MayaColors.text, fontSize: 16, height: 1.4));
  }
}

class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))
    ..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 22,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Transform.translate(
                  offset: Offset(0, -4 * math.sin(((_c.value - i * 0.15) % 1.0) * math.pi).clamp(0.0, 1.0)),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Color.lerp(MayaColors.violet, MayaColors.pink, i / 2),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Calling Rahul Das" with a ring that runs down for 3 seconds and a Cancel
/// button, so a misheard name never dials the wrong person.
class _CallCountdown extends StatefulWidget {
  const _CallCountdown({required this.contact, required this.cancelLabel, required this.callingLabel});
  final FoundContact contact;
  final String cancelLabel;
  final String callingLabel;

  @override
  State<_CallCountdown> createState() => _CallCountdownState();
}

class _CallCountdownState extends State<_CallCountdown> with SingleTickerProviderStateMixin {
  late final AnimationController _ring = AnimationController(vsync: this, duration: const Duration(seconds: 3))
    ..forward();
  bool _closed = false;

  @override
  void initState() {
    super.initState();
    _ring.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        _close(true);
      }
    });
  }

  void _close(bool call) {
    if (_closed || !mounted) {
      return;
    }
    _closed = true;
    Navigator.of(context).pop(call);
  }

  @override
  void dispose() {
    _ring.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.contact.name.trim();
    final initial = name.isEmpty ? '?' : name.characters.first.toUpperCase();
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 32),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.callingLabel, style: const TextStyle(color: MayaColors.textDim, fontSize: 14)),
            const SizedBox(height: 18),
            SizedBox(
              width: 112,
              height: 112,
              child: AnimatedBuilder(
                animation: _ring,
                builder: (_, __) => Stack(
                  fit: StackFit.expand,
                  children: [
                    CircularProgressIndicator(
                      value: 1 - _ring.value,
                      strokeWidth: 4,
                      color: MayaColors.cyan,
                      backgroundColor: Colors.white.withValues(alpha: 0.08),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(10),
                      child: Container(
                        decoration: const BoxDecoration(shape: BoxShape.circle, gradient: MayaColors.brand),
                        alignment: Alignment.center,
                        child: Text(
                          initial,
                          style: const TextStyle(fontSize: 38, fontWeight: FontWeight.w700, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: MayaColors.text),
            ),
            const SizedBox(height: 4),
            Text(widget.contact.number, style: const TextStyle(color: MayaColors.textDim, fontSize: 15)),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: _PillButton(
                    color: MayaColors.danger,
                    icon: Icons.call_end_rounded,
                    label: widget.cancelLabel,
                    onTap: () => _close(false),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _PillButton(
                    color: const Color(0xFF22C55E),
                    icon: Icons.call_rounded,
                    label: 'Call',
                    onTap: () => _close(true),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _PillButton extends StatelessWidget {
  const _PillButton({required this.color, required this.icon, required this.label, required this.onTap});
  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      ),
      icon: Icon(icon),
      label: Text(label, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
    );
  }
}
