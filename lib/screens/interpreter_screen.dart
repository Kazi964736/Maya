import 'package:flutter/material.dart';

import '../brain/gemini.dart';
import '../services/voice.dart';
import '../settings.dart';
import '../ui/orb.dart';
import '../ui/theme.dart';

/// Two people, two languages: each taps their side, speaks, and Maya says it
/// out loud in the other person's language. The top half faces the other person.
class InterpreterScreen extends StatefulWidget {
  const InterpreterScreen({super.key});

  @override
  State<InterpreterScreen> createState() => _InterpreterScreenState();
}

class _InterpreterScreenState extends State<InterpreterScreen> {
  final settings = Settings.instance;
  final voice = Voice.instance;
  late final gemini = Gemini(settings);

  late AppLanguage _mine = settings.language;
  late AppLanguage _theirs = settings.language.code == 'en' ? languageByCode('hi') : languageByCode('en');

  String _myText = '';
  String _theirText = '';
  bool _busy = false;
  bool? _listeningMine; // which side is listening

  static const _names = {'bn': 'Bengali', 'hi': 'Hindi', 'en': 'English'};

  Future<void> _turn({required bool mine}) async {
    if (_busy) {
      if (voice.listening.value) {
        await voice.stopListening();
      }
      return;
    }
    if (!settings.hasAi) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Interpreter needs the Gemini key in Settings.')),
      );
      return;
    }
    final from = mine ? _mine : _theirs;
    final to = mine ? _theirs : _mine;
    setState(() {
      _busy = true;
      _listeningMine = mine;
    });
    try {
      await voice.stopSpeaking();
      final heard = await voice.listen(from);
      if (!mounted) {
        return;
      }
      setState(() => _listeningMine = null);
      if (heard.isEmpty) {
        return;
      }
      setState(() {
        if (mine) {
          _myText = heard;
          _theirText = '…';
        } else {
          _theirText = heard;
          _myText = '…';
        }
      });
      final translated = await gemini.translate(heard, _names[from.code]!, _names[to.code]!);
      if (!mounted) {
        return;
      }
      setState(() {
        if (mine) {
          _theirText = translated;
        } else {
          _myText = translated;
        }
      });
      await voice.speak(translated, to);
    } on GeminiException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _listeningMine = null;
        });
      }
    }
  }

  Widget _side({required bool mine}) {
    final lang = mine ? _mine : _theirs;
    final text = mine ? _myText : _theirText;
    final listening = _listeningMine == mine;
    return Expanded(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: MayaColors.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: listening ? MayaColors.violet : MayaColors.border, width: listening ? 2 : 1),
        ),
        child: Column(
          children: [
            Row(
              children: [
                DropdownButton<String>(
                  value: lang.code,
                  dropdownColor: MayaColors.surfaceHigh,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (final l in languages)
                      DropdownMenuItem(
                        value: l.code,
                        child: Text(l.label, style: const TextStyle(color: MayaColors.text, fontSize: 16)),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (code) => setState(() {
                            if (mine) {
                              _mine = languageByCode(code);
                            } else {
                              _theirs = languageByCode(code);
                            }
                          }),
                ),
                const Spacer(),
                Text(
                  mine ? 'You' : 'Them',
                  style: const TextStyle(color: MayaColors.textDim),
                ),
              ],
            ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  child: Text(
                    text.isEmpty ? (mine ? 'Tap the orb and speak' : 'Tap the orb and speak') : text,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: text.isEmpty ? 16 : 24,
                      height: 1.3,
                      fontWeight: FontWeight.w500,
                      color: text.isEmpty ? MayaColors.textDim : MayaColors.text,
                    ),
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: () => _turn(mine: mine),
              child: MayaOrb(
                size: 84,
                mood: listening ? OrbMood.listening : (_busy ? OrbMood.thinking : OrbMood.idle),
                level: voice.soundLevel,
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Interpreter')),
      body: SafeArea(
        child: Column(
          children: [
            // The other person sits across the table, so their half is upside down.
            Expanded(child: RotatedBox(quarterTurns: 2, child: Column(children: [_side(mine: false)]))),
            Expanded(child: Column(children: [_side(mine: true)])),
          ],
        ),
      ),
    );
  }
}
