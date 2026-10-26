import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../settings.dart';

class Reminder {
  Reminder({required this.id, required this.text, required this.when, this.repeat});
  final int id;
  final String text;

  /// First time it fires.
  final DateTime when;

  /// null (once), "daily" or "weekly".
  final String? repeat;

  /// The next time it fires (for repeating reminders, the next one from now).
  DateTime get next {
    if (repeat == null) {
      return when;
    }
    final now = DateTime.now();
    var t = when;
    final step = repeat == 'weekly' ? const Duration(days: 7) : const Duration(days: 1);
    while (!t.isAfter(now)) {
      t = t.add(step);
    }
    return t;
  }

  Map<String, dynamic> toJson() =>
      {'id': id, 'text': text, 'when': when.toIso8601String(), if (repeat != null) 'repeat': repeat};

  static Reminder? fromJson(dynamic j) {
    if (j is! Map) {
      return null;
    }
    final when = DateTime.tryParse('${j['when']}');
    final id = j['id'];
    if (when == null || id is! int) {
      return null;
    }
    final repeat = j['repeat'];
    return Reminder(
      id: id,
      text: '${j['text'] ?? ''}',
      when: when,
      repeat: repeat == 'daily' || repeat == 'weekly' ? repeat as String : null,
    );
  }
}

/// Reminders saved on the phone, each with a scheduled notification.
class Reminders extends ChangeNotifier {
  Reminders._();
  static final instance = Reminders._();

  final _plugin = FlutterLocalNotificationsPlugin();
  static const _key = 'reminders';
  List<Reminder> _items = [];

  List<Reminder> get upcoming {
    final now = DateTime.now();
    return _items.where((r) => r.next.isAfter(now)).toList()..sort((a, b) => a.next.compareTo(b.next));
  }

  List<Reminder> get today {
    final now = DateTime.now();
    return upcoming.where((r) => r.next.year == now.year && r.next.month == now.month && r.next.day == now.day).toList();
  }

  Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      await _plugin.initialize(
        const InitializationSettings(android: AndroidInitializationSettings('@mipmap/ic_launcher')),
      );
    } catch (e) {
      debugPrint('Notification init failed: $e');
    }
    final raw = Settings.instance.prefs.getString(_key);
    if (raw != null) {
      try {
        _items = (jsonDecode(raw) as List).map(Reminder.fromJson).whereType<Reminder>().toList();
      } catch (_) {
        _items = [];
      }
    }
    // Forget reminders that are long past.
    final cutoff = DateTime.now().subtract(const Duration(days: 1));
    _items.removeWhere((r) => r.repeat == null && r.when.isBefore(cutoff));
    await _save();
  }

  Future<void> _save() async {
    await Settings.instance.prefs.setString(_key, jsonEncode(_items.map((r) => r.toJson()).toList()));
    notifyListeners();
  }

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<void> requestPermissions() async {
    try {
      await _android?.requestNotificationsPermission();
      await _android?.requestExactAlarmsPermission();
    } catch (e) {
      debugPrint('Reminder permission request failed: $e');
    }
  }

  Future<Reminder> add(String text, DateTime when, {String? repeat}) async {
    await requestPermissions();
    final id = DateTime.now().millisecondsSinceEpoch ~/ 1000 % 2000000000 + _items.length;
    final reminder = Reminder(id: id, text: text, when: when, repeat: repeat);
    final details = const NotificationDetails(
      android: AndroidNotificationDetails(
        'reminders',
        'Reminders',
        channelDescription: 'Reminders you set by voice',
        importance: Importance.high,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
      ),
    );
    final at = tz.TZDateTime.from(when.toUtc(), tz.UTC);
    Future<void> schedule(AndroidScheduleMode mode) => _plugin.zonedSchedule(
          id,
          'Maya reminder',
          text,
          at,
          details,
          androidScheduleMode: mode,
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: switch (repeat) {
            'daily' => DateTimeComponents.time,
            'weekly' => DateTimeComponents.dayOfWeekAndTime,
            _ => null,
          },
        );
    try {
      await schedule(AndroidScheduleMode.exactAllowWhileIdle);
    } catch (e) {
      debugPrint('Exact reminder failed, using inexact: $e');
      await schedule(AndroidScheduleMode.inexactAllowWhileIdle);
    }
    _items.add(reminder);
    await _save();
    return reminder;
  }

  Future<void> remove(Reminder r) async {
    try {
      await _plugin.cancel(r.id);
    } catch (_) {}
    _items.removeWhere((x) => x.id == r.id);
    await _save();
  }
}
