/// What the user asked for, in a form the app can carry out.
class AssistantAction {
  const AssistantAction({
    required this.type,
    this.contact,
    this.message,
    this.hour,
    this.minute,
    this.seconds,
    this.when,
    this.app,
    this.place,
    this.query,
    this.reply = '',
  });

  /// One of [ActionType] values.
  final String type;

  /// Person to call or message, as spoken ("Maa", "Rahul").
  final String? contact;

  /// WhatsApp text, or what to be reminded about.
  final String? message;

  /// Alarm time (24-hour clock).
  final int? hour;
  final int? minute;

  /// Timer length.
  final int? seconds;

  /// Reminder time, phone-local.
  final DateTime? when;

  /// App to open ("YouTube", "PhonePe").
  final String? app;

  /// Destination for navigation, or a city for weather.
  final String? place;

  /// Search text.
  final String? query;

  /// What the assistant should say back, in the user's language.
  final String reply;

  static int? _int(dynamic v) {
    if (v is int) {
      return v;
    }
    if (v is num) {
      return v.round();
    }
    if (v is String) {
      return int.tryParse(v.trim());
    }
    return null;
  }

  static String? _str(dynamic v) {
    if (v == null) {
      return null;
    }
    final s = v.toString().trim();
    return s.isEmpty || s == 'null' ? null : s;
  }

  factory AssistantAction.fromJson(Map<String, dynamic> json) {
    final type = _str(json['action'] ?? json['type']) ?? ActionType.answer;
    DateTime? when;
    final whenText = _str(json['when']);
    if (whenText != null) {
      when = DateTime.tryParse(whenText);
      if (when != null && when.isUtc) {
        when = when.toLocal();
      }
    }
    return AssistantAction(
      type: ActionType.all.contains(type) ? type : ActionType.answer,
      contact: _str(json['contact']),
      message: _str(json['message']),
      hour: _int(json['hour']),
      minute: _int(json['minute']),
      seconds: _int(json['seconds']),
      when: when,
      app: _str(json['app']),
      place: _str(json['place']),
      query: _str(json['query']),
      reply: _str(json['reply']) ?? '',
    );
  }

  @override
  String toString() => 'AssistantAction($type, contact: $contact, message: $message, hour: $hour, '
      'minute: $minute, seconds: $seconds, when: $when, app: $app, place: $place, query: $query)';
}

class ActionType {
  static const call = 'call';
  static const alarm = 'alarm';
  static const timer = 'timer';
  static const reminder = 'reminder';
  static const openApp = 'open_app';
  static const whatsapp = 'whatsapp';
  static const navigate = 'navigate';
  static const weather = 'weather';
  static const briefing = 'briefing';
  static const search = 'search';
  static const answer = 'answer';

  static const all = {call, alarm, timer, reminder, openApp, whatsapp, navigate, weather, briefing, search, answer};
}
