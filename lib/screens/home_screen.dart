import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../brain/action.dart';
import '../brain/gemini.dart';
import '../brain/rule_parser.dart';
import '../services/executor.dart';
import '../services/voice.dart';
import '../settings.dart';
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
  'bn': ['মা কে ফোন করো', 'সকাল ৬টায় অ্যালার্ম দাও', '১০ মিনিটের টাইমার', 'আজ আবহাওয়া কেমন?', 'সুপ্রভাত'],
  'hi': ['माँ को फोन करो', 'सुबह 6 बजे का अलार्म लगाओ', '10 मिनट का टाइमर', 'आज मौसम कैसा है?', 'सुप्रभात'],
  'en': ['Call Maa', 'Set an alarm for 6 am', '10 minute timer', "How's the weather today?", 'Good morning'],
};

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final settings = Settings.instance;
  final voice = Voice.instance;
  late final gemini = Gemini(settings);
  late final executor = Executor(settings, gemini);
  final _parser = const RuleParser();
  final _input = TextEditingController();
  final _messages = <ChatMessage>[];
  bool _busy = false;

  static const _historyKey = 'chat_history';

  @override
  void initState() {
    super.initState();
    _loadHistory();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (settings.listenOnOpen) {
        // Give speech set-up a moment on first launch.
        await Future<void>.delayed(const Duration(milliseconds: 600));
        if (mounted) {
          _listen();
        }
      }
    });
  }

  @override
  void dispose() {
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

  Future<void> _listen() async {
    if (voice.listening.value) {
      await voice.stopListening();
      return;
    }
    if (_busy) {
      return;
    }
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
    final words = await voice.listen(settings.language);
    if (words.isNotEmpty && mounted) {
      await _handle(words);
    }
  }

  Future<void> _handle(String text, {AssistantAction? forced}) async {
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
      try {
        action = await gemini.understand(trimmed, history, lang);
      } on GeminiException catch (e) {
        aiProblem = e.message;
        action = _parser.parse(trimmed);
      }
    } else {
      action = _parser.parse(trimmed);
    }

    var reply = await executor.run(action);
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
    final keepTalking = {ActionType.answer, ActionType.weather, ActionType.briefing}.contains(action.type);
    if (settings.conversationMode && keepTalking && mounted) {
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

  Future<void> _clearChat() async {
    setState(_messages.clear);
    await _saveHistory();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lang = settings.language;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maya'),
        actions: [
          IconButton(
            tooltip: 'Good morning briefing',
            icon: const Icon(Icons.wb_sunny_outlined),
            onPressed: _busy ? null : () => _handle('☀️ Briefing', forced: const AssistantAction(type: ActionType.briefing)),
          ),
          IconButton(
            tooltip: 'Reminders',
            icon: const Icon(Icons.notifications_none),
            onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const RemindersScreen())),
          ),
          PopupMenuButton<String>(
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
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('Settings')),
              PopupMenuItem(value: 'clear', child: Text('Clear chat')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: SegmentedButton<String>(
                segments: [
                  for (final l in languages) ButtonSegment(value: l.code, label: Text(l.label)),
                ],
                selected: {lang.code},
                showSelectedIcon: false,
                onSelectionChanged: (s) async {
                  await settings.update(language: languageByCode(s.first));
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
            ),
            Expanded(
              child: _messages.isEmpty
                  ? _Suggestions(items: _suggestions[lang.code]!, onTap: _handle, hasAi: settings.hasAi)
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                      itemCount: _messages.length + (_busy ? 1 : 0),
                      itemBuilder: (_, i) {
                        if (_busy && i == 0) {
                          return const _Bubble(fromUser: false, text: '…');
                        }
                        final m = _messages[_messages.length - 1 - (i - (_busy ? 1 : 0))];
                        return _Bubble(fromUser: m.fromUser, text: m.text);
                      },
                    ),
            ),
            ValueListenableBuilder<bool>(
              valueListenable: voice.listening,
              builder: (_, listening, __) => !listening
                  ? const SizedBox.shrink()
                  : ValueListenableBuilder<String>(
                      valueListenable: voice.heard,
                      builder: (_, heard, __) => Container(
                        width: double.infinity,
                        margin: const EdgeInsets.symmetric(horizontal: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Text(
                          heard.isEmpty ? 'Listening… (${lang.label})' : heard,
                          style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.onPrimaryContainer),
                        ),
                      ),
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Explain a photo',
                    icon: const Icon(Icons.document_scanner_outlined),
                    onPressed: _busy ? null : _explainPhoto,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _input,
                      textInputAction: TextInputAction.send,
                      minLines: 1,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Type or tap the mic…',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.send),
                          onPressed: () {
                            final t = _input.text;
                            _input.clear();
                            _handle(t);
                          },
                        ),
                      ),
                      onSubmitted: (t) {
                        _input.clear();
                        _handle(t);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  ValueListenableBuilder<bool>(
                    valueListenable: voice.listening,
                    builder: (_, listening, __) => SizedBox(
                      width: 64,
                      height: 64,
                      child: FloatingActionButton(
                        heroTag: 'mic',
                        backgroundColor: listening ? theme.colorScheme.error : theme.colorScheme.primary,
                        foregroundColor: listening ? theme.colorScheme.onError : theme.colorScheme.onPrimary,
                        onPressed: _listen,
                        child: Icon(listening ? Icons.stop : Icons.mic, size: 32),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Suggestions extends StatelessWidget {
  const _Suggestions({required this.items, required this.onTap, required this.hasAi});
  final List<String> items;
  final void Function(String) onTap;
  final bool hasAi;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 24),
        Icon(Icons.graphic_eq, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text('Maya', textAlign: TextAlign.center, style: theme.textTheme.headlineMedium),
        const SizedBox(height: 4),
        Text(
          'Tap the mic and speak in বাংলা, हिंदी or English.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 20),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 8,
          children: [for (final s in items) ActionChip(label: Text(s), onPressed: () => onTap(s))],
        ),
        if (!hasAi) ...[
          const SizedBox(height: 24),
          Text(
            'Calls, alarms, timers, reminders, apps and weather work now. '
            'For answers to any question and photo reading, add a free Gemini key in Settings.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: fromUser ? scheme.primary : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(fromUser ? 18 : 4),
            bottomRight: Radius.circular(fromUser ? 4 : 18),
          ),
        ),
        child: SelectableText(
          text,
          style: TextStyle(color: fromUser ? scheme.onPrimary : scheme.onSurface, fontSize: 16),
        ),
      ),
    );
  }
}
