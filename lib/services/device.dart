import 'package:flutter/services.dart';

/// Torch, volume, ringer, battery and quick settings (MainActivity.kt).
class PhoneControl {
  static const _channel = MethodChannel('maya/phone');

  static Future<bool> _call(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _channel.invokeMethod<bool>(method, args) ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> torch(bool on) => _call('torch', {'on': on});
  static Future<bool> volume(String how) => _call('volume', {'how': how}); // up, down, max, mute
  static Future<bool> ringer(String mode) => _call('ringer', {'mode': mode}); // ring, vibrate, silent
  static Future<bool> panel(String name) => _call('panel', {'name': name}); // wifi, data, bluetooth, dnd, brightness

  static Future<({int level, bool charging})?> battery() async {
    try {
      final m = await _channel.invokeMapMethod<String, dynamic>('battery');
      if (m == null) {
        return null;
      }
      return (level: (m['level'] as num).toInt(), charging: m['charging'] == true);
    } catch (_) {
      return null;
    }
  }
}

class IncomingMessage {
  const IncomingMessage({
    required this.id,
    required this.app,
    required this.sender,
    required this.text,
    required this.time,
    required this.canReply,
  });

  final int id;
  final String app;
  final String sender;
  final String text;
  final DateTime time;
  final bool canReply;
}

/// Chat messages seen in notifications (MayaNotificationListener.kt).
class Messages {
  static const _channel = MethodChannel('maya/messages');

  /// The last message read aloud, so "reply …" knows who to answer.
  static IncomingMessage? lastRead;

  static Future<bool> hasAccess() async {
    try {
      return await _channel.invokeMethod<bool>('hasAccess') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> openAccessSettings() async {
    try {
      await _channel.invokeMethod<bool>('openAccess');
    } catch (_) {}
  }

  static Future<List<IncomingMessage>> recent() async {
    try {
      final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>('recent') ?? const [];
      return [
        for (final m in raw)
          IncomingMessage(
            id: (m['id'] as num).toInt(),
            app: '${m['app']}',
            sender: '${m['sender']}',
            text: '${m['text']}',
            time: DateTime.fromMillisecondsSinceEpoch((m['time'] as num).toInt()),
            canReply: m['canReply'] == true,
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static Future<void> clear() async {
    try {
      await _channel.invokeMethod<bool>('clear');
    } catch (_) {}
  }

  static Future<bool> reply(IncomingMessage to, String text) async {
    try {
      return await _channel.invokeMethod<bool>('reply', {'id': to.id, 'text': text}) ?? false;
    } catch (_) {
      return false;
    }
  }
}
