import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/phone_brand.dart';
import '../services/voice_id.dart';
import '../settings.dart';
import '../ui/theme.dart';
import 'voice_id_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final s = Settings.instance;
  late final _key = TextEditingController(text: s.apiKey);
  late final _model = TextEditingController(text: s.model);
  late final _city = TextEditingController(text: s.city);
  late final _name = TextEditingController(text: s.userName);
  bool _showKey = false;

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _city.dispose();
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await s.update(apiKey: _key.text, model: _model.text, city: _city.text, userName: _name.text);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Saved')));
    }
  }

  Future<void> _openDefaultApps() async {
    try {
      await AndroidIntent(
        action: 'android.settings.MANAGE_DEFAULT_APPS_SETTINGS',
        flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
      ).launch();
    } catch (_) {
      await AndroidIntent(action: 'android.settings.SETTINGS', flags: [Flag.FLAG_ACTIVITY_NEW_TASK]).launch();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) {
          s.update(apiKey: _key.text, model: _model.text, city: _city.text, userName: _name.text);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Settings'),
          actions: [TextButton(onPressed: _save, child: const Text('Save'))],
        ),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.lock_person_rounded, color: MayaColors.violet),
                title: const Text('My voice (Voice Lock)', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(
                  VoiceId.instance.enrolled
                      ? (VoiceId.instance.lockOn ? 'On — Maya only obeys your voice' : 'Off')
                      : 'Teach Maya your voice so she only obeys you',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () async {
                  await Navigator.push(context, MaterialPageRoute(builder: (_) => const VoiceIdScreen()));
                  if (mounted) {
                    setState(() {});
                  }
                },
              ),
            ),
            const SizedBox(height: 20),
            Text('Language', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: [for (final l in languages) ButtonSegment(value: l.code, label: Text(l.label))],
              selected: {s.language.code},
              showSelectedIcon: false,
              onSelectionChanged: (v) async {
                await s.update(language: languageByCode(v.first));
                setState(() {});
              },
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Your name (optional)', hintText: 'Baby'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _city,
              decoration: const InputDecoration(labelText: 'Your city (for weather)', hintText: 'Berhampore'),
            ),
            const SizedBox(height: 24),
            Text('AI answers and photo reading', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Get a free key at aistudio.google.com → "Get API key", then paste it here. '
              'It is stored only on this phone.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _key,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: 'Gemini API key',
                hintText: 'AIza…',
                suffixIcon: IconButton(
                  icon: Icon(_showKey ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 18),
                label: const Text('Get a free key'),
                onPressed: () => launchUrl(
                  Uri.parse('https://aistudio.google.com/app/apikey'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
            ),
            TextField(
              controller: _model,
              decoration: const InputDecoration(
                labelText: 'AI model',
                helperText: 'Change only if Google retires this model name.',
              ),
            ),
            const SizedBox(height: 24),
            Text('Behaviour', style: theme.textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Start listening when opened'),
              subtitle: const Text('Opening Maya (or the assistant button) starts the mic'),
              value: s.listenOnOpen,
              onChanged: (v) async {
                await s.update(listenOnOpen: v);
                setState(() {});
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Speak replies'),
              value: s.speakReplies,
              onChanged: (v) async {
                await s.update(speakReplies: v);
                setState(() {});
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Conversation mode'),
              subtitle: const Text('After answering, listen again so you can keep talking (hands-free)'),
              value: s.conversationMode,
              onChanged: (v) async {
                await s.update(conversationMode: v);
                setState(() {});
              },
            ),
            const SizedBox(height: 24),
            Text('Start Maya quickly', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              '• Quick Settings tile: pull down the notification shade twice, tap the pencil (Edit), and drag the '
              '"Maya" tile up. One tap starts Maya listening, even from inside other apps.\n'
              '• Home screen: keep the Maya icon on your first screen or dock.\n'
              '• Assistant button: on some phones, Default apps → Digital assistant app lists Maya; choose it to '
              'open Maya with a long-press of home/power. Most phones only list Google there.',
              style: theme.textTheme.bodySmall,
            ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                icon: const Icon(Icons.settings, size: 18),
                label: const Text('Open Default apps settings'),
                onPressed: _openDefaultApps,
              ),
            ),
            const SizedBox(height: 24),
            Text('Reliable alarms and reminders', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Phones from Xiaomi/Redmi, Vivo, Oppo, Realme, OnePlus and others may stop Maya in the background. '
              'In App info allow Autostart / background activity, and set Battery to "No restrictions".',
              style: theme.textTheme.bodySmall,
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.info_outline, size: 18),
                  label: const Text('App info'),
                  onPressed: openMayaAppInfo,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.battery_saver, size: 18),
                  label: const Text('Battery settings'),
                  onPressed: openBatterySettings,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text('Voices and languages', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'If Maya speaks English instead of Bengali or Hindi, install the voice in Text-to-speech settings '
              '(Speech Services by Google). If it doesn\'t understand you, update the Google app and add the '
              'language in voice input settings.',
              style: theme.textTheme.bodySmall,
            ),
            Wrap(
              spacing: 8,
              children: [
                TextButton.icon(
                  icon: const Icon(Icons.record_voice_over, size: 18),
                  label: const Text('Voices'),
                  onPressed: openVoiceSettings,
                ),
                TextButton.icon(
                  icon: const Icon(Icons.mic_none, size: 18),
                  label: const Text('Voice input'),
                  onPressed: openSpeechSettings,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
