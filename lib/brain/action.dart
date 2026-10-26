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
    this.repeat,
    this.setting,
    this.live = false,
    this.steps = const [],
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

  /// For reminders: null (once), "daily" or "weekly".
  final String? repeat;

  /// For phone control: torch_on, torch_off, volume_up, volume_down, volume_max,
  /// mute, vibrate, ring, battery, wifi, bluetooth, dnd, brightness, data.
  final String? setting;

  /// For answers: true when it needs fresh information from the web.
  final bool live;

  /// For several things at once ("set an alarm and remind me…").
  final List<AssistantAction> steps;

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
    final rawSteps = json['steps'];
    if (rawSteps is List && rawSteps.isNotEmpty) {
      final steps = [
        for (final st in rawSteps)
          if (st is Map) AssistantAction.fromJson(Map<String, dynamic>.from(st)),
      ];
      final reply = _str(json['reply']) ?? '';
      if (steps.length == 1) {
        final one = steps.first;
        return one.reply.isEmpty && reply.isNotEmpty ? one.withReply(reply) : one;
      }
      if (steps.isNotEmpty) {
        return AssistantAction(type: ActionType.multi, steps: steps, reply: reply);
      }
    }
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
      repeat: const {'daily', 'weekly'}.contains(_str(json['repeat'])) ? _str(json['repeat']) : null,
      setting: _str(json['setting']),
      live: json['live'] == true || json['live'] == 'true',
      reply: _str(json['reply']) ?? '',
    );
  }

  AssistantAction withReply(String newReply) => AssistantAction(
        type: type,
        contact: contact,
        message: message,
        hour: hour,
        minute: minute,
        seconds: seconds,
        when: when,
        app: app,
        place: place,
        query: query,
        repeat: repeat,
        setting: setting,
        live: live,
        steps: steps,
        reply: newReply,
      );

  @override
  String toString() => 'AssistantAction($type, contact: $contact, message: $message, hour: $hour, '
      'minute: $minute, seconds: $seconds, when: $when, app: $app, place: $place, query: $query, '
      'repeat: $repeat, setting: $setting, live: $live, steps: $steps)';
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
  static const remember = 'remember';
  static const forget = 'forget';
  static const recall = 'recall';
  static const readMessages = 'read_messages';
  static const replyMessage = 'reply_message';
  static const phone = 'phone';
  static const interpreter = 'interpreter';
  static const multi = 'multi';

  static const all = {
    call, alarm, timer, reminder, openApp, whatsapp, navigate, weather, briefing, search, answer, //
    remember, forget, recall, readMessages, replyMessage, phone, interpreter, multi,
  };
}
