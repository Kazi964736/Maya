import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../settings.dart';
import 'action.dart';

class GeminiException implements Exception {
  GeminiException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// One past message, so the assistant remembers the conversation.
class ChatTurn {
  const ChatTurn({required this.fromUser, required this.text});
  final bool fromUser;
  final String text;
}

const _languageNames = {'bn': 'Bengali (বাংলা script)', 'hi': 'Hindi (Devanagari script)', 'en': 'English'};

/// Talks to Google's Gemini API.
///
/// For personal testing the key is stored on the phone (Settings). Before
/// publishing, route these calls through a small server so the key isn't
/// shipped inside the app.
class Gemini {
  Gemini(this.settings);
  final Settings settings;

  Uri get _url => Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/${settings.model}:generateContent',
      );

  Future<String> _generate({
    required String system,
    required List<Map<String, dynamic>> contents,
    bool json = false,
  }) async {
    if (!settings.hasAi) {
      throw GeminiException('No AI key set');
    }
    final body = <String, dynamic>{
      'systemInstruction': {
        'parts': [
          {'text': system},
        ],
      },
      'contents': contents,
      'generationConfig': {
        'temperature': 0.4,
        if (json) 'responseMimeType': 'application/json',
      },
    };
    final http.Response res;
    try {
      res = await http
          .post(
            _url,
            headers: {'Content-Type': 'application/json', 'x-goog-api-key': settings.apiKey},
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    } catch (e) {
      throw GeminiException('Could not reach the AI service. Check your internet.');
    }
    final Map<String, dynamic> data;
    try {
      data = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    } catch (_) {
      throw GeminiException('The AI service sent an unreadable answer (HTTP ${res.statusCode}).');
    }
    if (res.statusCode != 200) {
      final msg = (data['error'] is Map ? data['error']['message'] : null) ?? 'HTTP ${res.statusCode}';
      throw GeminiException('AI error: $msg');
    }
    final candidates = data['candidates'];
    if (candidates is! List || candidates.isEmpty) {
      throw GeminiException('The AI gave no answer. Try asking differently.');
    }
    final parts = (candidates.first['content']?['parts'] as List?) ?? const [];
    final text = parts.map((p) => p is Map ? (p['text'] ?? '') : '').join().trim();
    if (text.isEmpty) {
      throw GeminiException('The AI gave an empty answer.');
    }
    return text;
  }

  String _now() {
    final n = DateTime.now();
    const days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
    final two = (int v) => v.toString().padLeft(2, '0');
    return '${days[n.weekday - 1]} ${n.year}-${two(n.month)}-${two(n.day)} ${two(n.hour)}:${two(n.minute)}';
  }

  /// Turns what the user said into an action plus a spoken reply.
  Future<AssistantAction> understand(String text, List<ChatTurn> history, AppLanguage lang) async {
    final name = settings.userName.isEmpty ? '' : ' The user\'s name is ${settings.userName}.';
    final system = '''
You are Bolo, a friendly voice assistant on an Android phone in India.$name
The user speaks ${_languageNames[lang.code]}, often mixed with English words. Reply in ${_languageNames[lang.code]}.
Current local date and time: ${_now()}. The user's city: ${settings.city}.

Decide what the user wants and return ONLY a JSON object with these keys:
- "action": one of "call", "alarm", "timer", "reminder", "open_app", "whatsapp", "navigate", "weather", "briefing", "search", "answer"
- "contact": person's name exactly as the user said it (for call / whatsapp), else null
- "message": text to send on WhatsApp, or what to remind about (keep the user's language), else null
- "hour", "minute": alarm time on a 24-hour clock (e.g. "6 in the evening" -> 18, 0), else null
- "seconds": timer length in seconds, else null
- "when": reminder time as local ISO "YYYY-MM-DDTHH:MM:00", worked out from the current time, else null
- "app": app name in English (e.g. "YouTube", "PhonePe", "Camera"), else null
- "place": destination for navigate, or a city for weather if the user named one, else null
- "query": what to search the web for, else null
- "reply": a short, warm spoken reply (1-3 sentences, no markdown, no emojis). For "answer", this IS the answer:
  helpful, accurate and brief enough to listen to. For other actions, say what you are doing.

Rules: "briefing" is for good-morning / what's my day. "search" only if the user asks to search the web.
For time-sensitive facts you cannot know (live scores, today's news, prices), say so briefly and suggest "search".
Never invent phone numbers. If unsure what they want, use "answer" and ask a short question.''';

    final contents = <Map<String, dynamic>>[
      for (final t in history.length > 8 ? history.sublist(history.length - 8) : history)
        {
          'role': t.fromUser ? 'user' : 'model',
          'parts': [
            {'text': t.text},
          ],
        },
      {
        'role': 'user',
        'parts': [
          {'text': text},
        ],
      },
    ];
    final raw = await _generate(system: system, contents: contents, json: true);
    try {
      final cleaned = raw.replaceAll(RegExp(r'^```(json)?|```$', multiLine: true), '').trim();
      final decoded = jsonDecode(cleaned);
      final map = decoded is List && decoded.isNotEmpty ? decoded.first : decoded;
      return AssistantAction.fromJson(Map<String, dynamic>.from(map as Map));
    } catch (_) {
      // Not JSON after all: treat it as a plain answer.
      return AssistantAction(type: ActionType.answer, reply: raw);
    }
  }

  /// Explains a photo (bill, letter, medicine strip, sign...) in the user's language.
  Future<String> explainImage(Uint8List bytes, String mimeType, AppLanguage lang, {String? question}) {
    final system = '''
You are Bolo, a helpful assistant in India. Reply in ${_languageNames[lang.code]}, simply, for someone who may not read English well.
Explain what the photo shows. If it is a bill, letter, notice, prescription or form: say what it is, the key details
(amounts, dates, deadlines, names), and what the person should do next. If it is medicine, say what it is commonly used
for and remind them to follow their doctor's advice. Keep it under 120 words, no markdown.''';
    return _generate(
      system: system,
      contents: [
        {
          'role': 'user',
          'parts': [
            {
              'inline_data': {'mime_type': mimeType, 'data': base64Encode(bytes)},
            },
            {'text': question?.trim().isNotEmpty == true ? question : 'What is this and what should I do?'},
          ],
        },
      ],
    );
  }

  /// Rewrites plain facts (weather, briefing) as a natural spoken reply.
  Future<String> phrase(String facts, AppLanguage lang) {
    return _generate(
      system: 'You are Bolo, a voice assistant. Turn these facts into a short, natural spoken reply in '
          '${_languageNames[lang.code]}. No markdown, no emojis, under 70 words.',
      contents: [
        {
          'role': 'user',
          'parts': [
            {'text': facts},
          ],
        },
      ],
    );
  }
}
