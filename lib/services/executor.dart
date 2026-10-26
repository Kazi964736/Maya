import 'package:android_intent_plus/android_intent.dart';
import 'package:android_intent_plus/flag.dart';
import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import '../brain/action.dart';
import '../brain/gemini.dart';
import '../settings.dart';
import 'apps.dart';
import 'contacts.dart';
import 'phone_brand.dart';
import 'reminders.dart';
import 'weather.dart';

/// Replies used when there is no AI to phrase them. {x} is filled in.
const _phrases = <String, Map<String, String>>{
  'calling': {'bn': '{x} কে ফোন করছি।', 'hi': '{x} को फोन कर रहा हूँ।', 'en': 'Calling {x}.'},
  'no_contact': {
    'bn': '{x} নামে কোনো নম্বর খুঁজে পেলাম না।',
    'hi': '{x} नाम का कोई नंबर नहीं मिला।',
    'en': "I couldn't find a number for {x}.",
  },
  'who': {'bn': 'কাকে?', 'hi': 'किसको?', 'en': 'Who should I contact?'},
  'alarm': {'bn': '{x} টায় অ্যালার্ম দিলাম।', 'hi': '{x} बजे का अलार्म लगा दिया।', 'en': 'Alarm set for {x}.'},
  'timer': {'bn': '{x} এর টাইমার চালু করলাম।', 'hi': '{x} का टाइमर शुरू कर दिया।', 'en': 'Timer started for {x}.'},
  'reminder': {
    'bn': 'ঠিক আছে, {x} মনে করিয়ে দেব।',
    'hi': 'ठीक है, {x} याद दिला दूँगा।',
    'en': "Okay, I'll remind you {x}.",
  },
  'reminder_when': {
    'bn': 'কখন মনে করাব? যেমন: "১০ মিনিট পরে" বা "সন্ধ্যা ৬টায়"।',
    'hi': 'कब याद दिलाऊँ? जैसे: "10 मिनट बाद" या "शाम 6 बजे"।',
    'en': 'When should I remind you? For example "in 10 minutes" or "at 6 pm".',
  },
  'opening': {'bn': '{x} খুলছি।', 'hi': '{x} खोल रहा हूँ।', 'en': 'Opening {x}.'},
  'no_app': {
    'bn': '{x} ফোনে নেই মনে হচ্ছে, প্লে স্টোরে খুঁজছি।',
    'hi': '{x} फोन में नहीं लगता, प्ले स्टोर में ढूँढ रहा हूँ।',
    'en': "{x} doesn't seem to be installed, searching Play Store.",
  },
  'whatsapp': {
    'bn': 'হোয়াটসঅ্যাপ খুলছি, পাঠাতে সেন্ড চাপুন।',
    'hi': 'व्हाट्सएप खोल रहा हूँ, भेजने के लिए सेंड दबाइए।',
    'en': 'Opening WhatsApp. Tap Send to send it.',
  },
  'navigate': {'bn': '{x} এর রাস্তা দেখাচ্ছি।', 'hi': '{x} का रास्ता दिखा रहा हूँ।', 'en': 'Showing directions to {x}.'},
  'search': {'bn': '{x} খুঁজছি।', 'hi': '{x} खोज रहा हूँ।', 'en': 'Searching for {x}.'},
  'weather': {
    'bn': '{place} এ এখন {temp}°, সর্বোচ্চ {max}°, সর্বনিম্ন {min}°, বৃষ্টির সম্ভাবনা {rain}%।',
    'hi': '{place} में अभी {temp}°, अधिकतम {max}°, न्यूनतम {min}°, बारिश की संभावना {rain}%।',
    'en': '{place}: {temp}° now, high {max}°, low {min}°, {rain}% chance of rain.',
  },
  'weather_fail': {
    'bn': 'আবহাওয়ার খবর আনতে পারলাম না। ইন্টারনেট দেখুন।',
    'hi': 'मौसम की जानकारी नहीं मिल पाई। इंटरनेट देखिए।',
    'en': "I couldn't get the weather. Check your internet.",
  },
  'briefing_none': {'bn': 'আজ কোনো রিমাইন্ডার নেই।', 'hi': 'आज कोई रिमाइंडर नहीं है।', 'en': 'No reminders today.'},
  'briefing_some': {'bn': 'আজকের রিমাইন্ডার: {x}।', 'hi': 'आज के रिमाइंडर: {x}।', 'en': "Today's reminders: {x}."},
  'need_ai': {
    'bn': 'এটার উত্তর দিতে AI চাবি লাগবে। সেটিংসে Gemini key দিন। ফোন করা, অ্যালার্ম, টাইমার, রিমাইন্ডার এমনিই চলবে।',
    'hi': 'इसका जवाब देने के लिए AI key चाहिए। सेटिंग्स में Gemini key डालिए। कॉल, अलार्म, टाइमर, रिमाइंडर ऐसे ही चलेंगे।',
    'en': 'I need an AI key to answer that. Add a Gemini key in Settings. Calls, alarms, timers and reminders work without it.',
  },
  'no_contacts_permission': {
    'bn': 'কন্টাক্ট দেখার অনুমতি দিলে তবেই নাম ধরে ফোন করতে পারব।',
    'hi': 'कॉन्टैक्ट देखने की अनुमति देंगे तभी नाम से फोन कर पाऊँगा।',
    'en': 'Allow access to contacts so I can call people by name.',
  },
  'cancelled': {'bn': 'ঠিক আছে, বাতিল করলাম।', 'hi': 'ठीक है, रद्द कर दिया।', 'en': 'Okay, cancelled.'},
  'alarm_fallback': {
    'bn': 'ঘড়ির অ্যাপ সাড়া দিল না, তাই {x} টায় মায়া নিজে নোটিফিকেশন দিয়ে জানাবে।',
    'hi': 'घड़ी ऐप ने जवाब नहीं दिया, इसलिए {x} बजे माया खुद नोटिफिकेशन से बताएगी।',
    'en': "Your clock app didn't respond, so Maya will notify you at {x} instead.",
  },
  'timer_fallback': {
    'bn': 'ঘড়ির অ্যাপ টাইমার নিল না, তাই {x} পরে মায়া নোটিফিকেশন দেবে।',
    'hi': 'घड़ी ऐप ने टाइमर नहीं लिया, इसलिए {x} बाद माया नोटिफिकेशन देगी।',
    'en': "Your clock app didn't take the timer, so Maya will notify you in {x}.",
  },
  'failed': {
    'bn': 'দুঃখিত, এটা করতে পারলাম না।',
    'hi': 'माफ़ कीजिए, यह नहीं कर पाया।',
    'en': "Sorry, I couldn't do that.",
  },
};

String phrase(String key, AppLanguage lang, [Map<String, String> fill = const {}]) {
  var s = _phrases[key]?[lang.code] ?? _phrases[key]?['en'] ?? '';
  fill.forEach((k, v) => s = s.replaceAll('{$k}', v));
  return s;
}

String _two(int v) => v.toString().padLeft(2, '0');

String _durationText(int seconds, AppLanguage lang) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  final unit = {
    'bn': ['ঘণ্টা', 'মিনিট', 'সেকেন্ড'],
    'hi': ['घंटे', 'मिनट', 'सेकंड'],
    'en': ['hours', 'minutes', 'seconds'],
  }[lang.code]!;
  return [
    if (h > 0) '$h ${unit[0]}',
    if (m > 0) '$m ${unit[1]}',
    if (s > 0) '$s ${unit[2]}',
  ].join(' ');
}

String _timeText(DateTime t) {
  final now = DateTime.now();
  final sameDay = t.year == now.year && t.month == now.month && t.day == now.day;
  final hm = '${_two(t.hour)}:${_two(t.minute)}';
  return sameDay ? hm : '${t.day}/${t.month} $hm';
}

/// Things the executor needs to ask the person on screen.
abstract class ActionUi {
  /// Several contacts match: let the person pick one (null = cancelled).
  Future<FoundContact?> chooseContact(String spoken, List<FoundContact> options);

  /// Last chance to stop a call; true means go ahead.
  Future<bool> confirmCall(FoundContact contact);

  /// Once, on phones known to delay alarms and reminders: explain battery settings.
  Future<void> showReliabilityTip();
}

/// Carries out an action and returns what to say back.
class Executor {
  Executor(this.settings, this.gemini, this.ui);
  final Settings settings;
  final Gemini gemini;
  final ActionUi ui;
  final _weather = WeatherService();

  Future<void> _open(String url) async {
    final ok = await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    if (!ok) {
      throw Exception('Could not open $url');
    }
  }

  /// Finds one contact for a spoken name, asking when several match.
  /// Returns the contact, or a reply explaining why not.
  Future<(FoundContact?, String?)> _resolveContact(String spoken, AppLanguage lang) async {
    final all = await ContactFinder.instance.findAll(spoken);
    if (all == null) {
      return (null, phrase('no_contacts_permission', lang));
    }
    if (all.isEmpty) {
      return (null, phrase('no_contact', lang, {'x': spoken}));
    }
    if (all.length == 1) {
      return (all.first, null);
    }
    final chosen = await ui.chooseContact(spoken, all.take(8).toList());
    return chosen == null ? (null, phrase('cancelled', lang)) : (chosen, null);
  }

  Future<bool> _clockAppHandles(AndroidIntent intent) async {
    try {
      return await intent.canResolveActivity() ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _maybeReliabilityTip() async {
    if (settings.prefs.getBool('reliability_tip_shown') == true) {
      return;
    }
    if (await isAggressiveBatteryBrand()) {
      await settings.prefs.setBool('reliability_tip_shown', true);
      await ui.showReliabilityTip();
    }
  }

  Future<String> run(AssistantAction a) async {
    final lang = settings.language;
    String said(String fallbackKey, [Map<String, String> fill = const {}]) =>
        a.reply.isNotEmpty ? a.reply : phrase(fallbackKey, lang, fill);

    try {
      switch (a.type) {
        case ActionType.call:
          final name = a.contact;
          if (name == null) {
            return phrase('who', lang);
          }
          final (contact, problem) = await _resolveContact(name, lang);
          if (contact == null) {
            return problem ?? phrase('failed', lang);
          }
          if (!await ui.confirmCall(contact)) {
            return phrase('cancelled', lang);
          }
          final status = await Permission.phone.request();
          if (status.isGranted) {
            await AndroidIntent(
              action: 'android.intent.action.CALL',
              data: 'tel:${contact.number}',
              flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
            ).launch();
          } else {
            await _open('tel:${contact.number}');
          }
          return said('calling', {'x': contact.name});

        case ActionType.alarm:
          final h = a.hour;
          if (h == null) {
            return phrase('failed', lang);
          }
          final m = a.minute ?? 0;
          final alarmIntent = AndroidIntent(
            action: 'android.intent.action.SET_ALARM',
            arguments: <String, dynamic>{
              'android.intent.extra.alarm.HOUR': h,
              'android.intent.extra.alarm.MINUTES': m,
              'android.intent.extra.alarm.MESSAGE': 'Maya',
              'android.intent.extra.alarm.SKIP_UI': true,
            },
            flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
          );
          if (await _clockAppHandles(alarmIntent)) {
            await alarmIntent.launch();
            return said('alarm', {'x': '${_two(h)}:${_two(m)}'});
          }
          // No clock app accepts alarms: ring with Maya's own notification instead.
          final now = DateTime.now();
          var at = DateTime(now.year, now.month, now.day, h, m);
          if (!at.isAfter(now)) {
            at = at.add(const Duration(days: 1));
          }
          await Reminders.instance.add('⏰ Alarm', at);
          await _maybeReliabilityTip();
          return phrase('alarm_fallback', lang, {'x': '${_two(h)}:${_two(m)}'});

        case ActionType.timer:
          final secs = a.seconds;
          if (secs == null || secs <= 0) {
            return phrase('failed', lang);
          }
          final timerIntent = AndroidIntent(
            action: 'android.intent.action.SET_TIMER',
            arguments: <String, dynamic>{
              'android.intent.extra.alarm.LENGTH': secs,
              'android.intent.extra.alarm.MESSAGE': 'Maya',
              'android.intent.extra.alarm.SKIP_UI': true,
            },
            flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
          );
          if (await _clockAppHandles(timerIntent)) {
            await timerIntent.launch();
            return said('timer', {'x': _durationText(secs, lang)});
          }
          await Reminders.instance.add('⏱ Timer done', DateTime.now().add(Duration(seconds: secs)));
          await _maybeReliabilityTip();
          return phrase('timer_fallback', lang, {'x': _durationText(secs, lang)});

        case ActionType.reminder:
          final when = a.when;
          if (when == null || !when.isAfter(DateTime.now())) {
            return phrase('reminder_when', lang);
          }
          final text = (a.message ?? '').isEmpty ? 'Reminder' : a.message!;
          await Reminders.instance.add(text, when);
          await _maybeReliabilityTip();
          return said('reminder', {'x': _timeText(when)});

        case ActionType.openApp:
          final appName = a.app ?? '';
          final pkg = packageForApp(appName);
          if (pkg != null) {
            try {
              await AndroidIntent(
                action: 'android.intent.action.MAIN',
                category: 'android.intent.category.LAUNCHER',
                package: pkg,
                flags: [Flag.FLAG_ACTIVITY_NEW_TASK],
              ).launch();
              return said('opening', {'x': appName});
            } catch (e) {
              debugPrint('Open app failed: $e');
            }
          }
          await _open('market://search?q=${Uri.encodeComponent(appName)}');
          return phrase('no_app', lang, {'x': appName});

        case ActionType.whatsapp:
          String url = 'https://wa.me/';
          if (a.contact != null) {
            final (waContact, waProblem) = await _resolveContact(a.contact!, lang);
            if (waContact == null) {
              return waProblem ?? phrase('failed', lang);
            }
            url += ContactFinder.forWhatsApp(waContact.number);
          }
          if ((a.message ?? '').isNotEmpty) {
            url += '?text=${Uri.encodeComponent(a.message!)}';
          }
          await _open(url);
          return said('whatsapp');

        case ActionType.navigate:
          final place = a.place ?? '';
          if (place.isEmpty) {
            return phrase('failed', lang);
          }
          await _open('https://www.google.com/maps/dir/?api=1&destination=${Uri.encodeComponent(place)}');
          return said('navigate', {'x': place});

        case ActionType.search:
          final q = a.query ?? '';
          await _open('https://www.google.com/search?q=${Uri.encodeComponent(q)}');
          return said('search', {'x': q});

        case ActionType.weather:
          return await _weatherReply(a.place ?? settings.city, lang);

        case ActionType.briefing:
          return await _briefing(lang);

        default:
          if (a.reply.isNotEmpty) {
            return a.reply;
          }
          return phrase('need_ai', lang);
      }
    } catch (e) {
      debugPrint('Action ${a.type} failed: $e');
      return phrase('failed', lang);
    }
  }

  Future<String> _weatherReply(String city, AppLanguage lang) async {
    try {
      final w = await _weather.fetch(city);
      if (settings.hasAi) {
        try {
          return await gemini.phrase(w.facts(), lang);
        } catch (_) {}
      }
      return phrase('weather', lang, {
        'place': w.place,
        'temp': '${w.temperature.round()}',
        'max': '${w.max.round()}',
        'min': '${w.min.round()}',
        'rain': '${w.rainChance}',
      });
    } catch (e) {
      debugPrint('Weather failed: $e');
      return phrase('weather_fail', lang);
    }
  }

  Future<String> _briefing(AppLanguage lang) async {
    final today = Reminders.instance.today;
    final weather = await _weatherReply(settings.city, lang);
    final remindersText = today.isEmpty
        ? phrase('briefing_none', lang)
        : phrase('briefing_some', lang, {
            'x': today.map((r) => '${_two(r.when.hour)}:${_two(r.when.minute)} ${r.text}').join(', '),
          });
    if (settings.hasAi) {
      try {
        final name = settings.userName.isEmpty ? '' : 'Greet ${settings.userName} by name. ';
        return await gemini.phrase('${name}Good morning briefing. $weather $remindersText', lang);
      } catch (_) {}
    }
    return '$weather $remindersText';
  }
}
