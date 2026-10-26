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
import 'device.dart';
import 'lists.dart';
import 'memory.dart';
import 'phone_brand.dart';
import 'reminders.dart';
import 'weather.dart';

/// Replies used when there is no AI to phrase them. {x} is filled in.
const _phrases = <String, Map<String, String>>{
  'calling': {'bn': '{x} কে ফোন করছি।', 'hi': '{x} को फोन कर रही हूँ।', 'en': 'Calling {x}.'},
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
    'hi': 'ठीक है, {x} याद दिला दूँगी।',
    'en': "Okay, I'll remind you {x}.",
  },
  'reminder_when': {
    'bn': 'কখন মনে করাব? যেমন: "১০ মিনিট পরে" বা "সন্ধ্যা ৬টায়"।',
    'hi': 'कब याद दिलाऊँ? जैसे: "10 मिनट बाद" या "शाम 6 बजे"।',
    'en': 'When should I remind you? For example "in 10 minutes" or "at 6 pm".',
  },
  'opening': {'bn': '{x} খুলছি।', 'hi': '{x} खोल रही हूँ।', 'en': 'Opening {x}.'},
  'no_app': {
    'bn': '{x} ফোনে নেই মনে হচ্ছে, প্লে স্টোরে খুঁজছি।',
    'hi': '{x} फोन में नहीं लगता, प्ले स्टोर में ढूँढ रही हूँ।',
    'en': "{x} doesn't seem to be installed, searching Play Store.",
  },
  'whatsapp': {
    'bn': 'হোয়াটসঅ্যাপ খুলছি, পাঠাতে সেন্ড চাপুন।',
    'hi': 'व्हाट्सएप खोल रही हूँ, भेजने के लिए सेंड दबाइए।',
    'en': 'Opening WhatsApp. Tap Send to send it.',
  },
  'navigate': {'bn': '{x} এর রাস্তা দেখাচ্ছি।', 'hi': '{x} का रास्ता दिखा रही हूँ।', 'en': 'Showing directions to {x}.'},
  'search': {'bn': '{x} খুঁজছি।', 'hi': '{x} खोज रही हूँ।', 'en': 'Searching for {x}.'},
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
    'hi': 'कॉन्टैक्ट देखने की अनुमति देंगे तभी नाम से फोन कर पाऊँगी।',
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
  'reminder_repeat': {
    'bn': 'ঠিক আছে, {rep} {x} টায় মনে করিয়ে দেব।',
    'hi': 'ठीक है, {rep} {x} बजे याद दिला दूँगी।',
    'en': "Okay, I'll remind you {rep} at {x}.",
  },
  'remembered': {'bn': 'মনে রাখলাম।', 'hi': 'याद रख लिया।', 'en': "Got it, I'll remember that."},
  'forgot': {'bn': 'ভুলে গেলাম।', 'hi': 'भूल गई।', 'en': 'Done, I forgot that.'},
  'forget_none': {
    'bn': 'এমন কিছু মনে রাখা ছিল না।',
    'hi': 'ऐसा कुछ याद नहीं रखा था।',
    'en': "I didn't have anything like that saved.",
  },
  'recall_none': {
    'bn': 'এখনও কিছু মনে রাখতে বলেননি। বলুন "মনে রেখো…"।',
    'hi': 'अभी तक कुछ याद रखने को नहीं कहा। बोलिए "याद रखना…"।',
    'en': 'You haven\'t asked me to remember anything yet. Say "remember that…".',
  },
  'recall_some': {'bn': 'আমি মনে রেখেছি: {x}', 'hi': 'मुझे याद है: {x}', 'en': 'Here is what I remember: {x}'},
  'memory_answer': {'bn': 'আপনি বলেছিলেন: {x}', 'hi': 'आपने बताया था: {x}', 'en': 'You told me: {x}'},
  'msg_access': {
    'bn': 'মেসেজ পড়তে "নোটিফিকেশন অ্যাক্সেস" দিন। সেটিংস খুলছি, মায়া চালু করুন।',
    'hi': 'मैसेज पढ़ने के लिए "नोटिफ़िकेशन एक्सेस" दीजिए। सेटिंग्स खोल रही हूँ, माया चालू कीजिए।',
    'en': 'To read messages, allow "Notification access" for Maya. Opening that setting now.',
  },
  'msg_none': {
    'bn': 'নতুন কোনো মেসেজ নেই।',
    'hi': 'कोई नया मैसेज नहीं है।',
    'en': 'No new messages.',
  },
  'msg_none_from': {'bn': '{x}-এর কোনো নতুন মেসেজ নেই।', 'hi': '{x} का कोई नया मैसेज नहीं।', 'en': 'No new messages from {x}.'},
  'msg_reply_hint': {
    'bn': 'উত্তর দিতে বলুন "রিপ্লাই" আর আপনার কথা।',
    'hi': 'जवाब देने के लिए बोलिए "रिप्लाई" और अपनी बात।',
    'en': 'Say "reply" and your message to answer.',
  },
  'msg_who': {
    'bn': 'কাকে উত্তর দেব? আগে বলুন "মেসেজ পড়ো"।',
    'hi': 'किसे जवाब दूँ? पहले बोलिए "मैसेज पढ़ो"।',
    'en': 'Who should I reply to? Say "read my messages" first.',
  },
  'msg_what': {'bn': 'কী লিখব?', 'hi': 'क्या लिखूँ?', 'en': 'What should I say?'},
  'msg_sent': {'bn': '{x}-কে পাঠিয়ে দিলাম।', 'hi': '{x} को भेज दिया।', 'en': 'Sent to {x}.'},
  'msg_cant_reply': {
    'bn': 'এই মেসেজে সরাসরি উত্তর দেওয়া যাচ্ছে না।',
    'hi': 'इस मैसेज का सीधा जवाब नहीं दिया जा सकता।',
    'en': "I can't reply to that message directly.",
  },
  'torch_on': {'bn': 'টর্চ জ্বালালাম।', 'hi': 'टॉर्च जला दी।', 'en': 'Torch on.'},
  'torch_off': {'bn': 'টর্চ নিভিয়ে দিলাম।', 'hi': 'टॉर्च बंद कर दी।', 'en': 'Torch off.'},
  'volume': {'bn': 'ভলিউম ঠিক করলাম।', 'hi': 'आवाज़ बदल दी।', 'en': 'Volume changed.'},
  'ringer': {'bn': 'ফোন {x} মোডে।', 'hi': 'फोन {x} मोड में।', 'en': 'Phone on {x}.'},
  'battery': {
    'bn': 'ব্যাটারি {x}%{c}।',
    'hi': 'बैटरी {x}%{c}।',
    'en': 'Battery is at {x}%{c}.',
  },
  'settings_open': {'bn': '{x} সেটিং খুলছি।', 'hi': '{x} सेटिंग खोल रही हूँ।', 'en': 'Opening {x} settings.'},
  'interpreter': {'bn': 'দোভাষী মোড খুলছি।', 'hi': 'दुभाषिया मोड खोल रही हूँ।', 'en': 'Opening interpreter mode.'},
  'list_added': {'bn': '{list} লিস্টে যোগ করলাম: {x}।', 'hi': '{list} लिस्ट में जोड़ दिया: {x}।', 'en': 'Added to your {list} list: {x}.'},
  'list_read': {'bn': '{list} লিস্টে আছে: {x}।', 'hi': '{list} लिस्ट में है: {x}।', 'en': 'On your {list} list: {x}.'},
  'list_empty': {'bn': '{list} লিস্ট খালি।', 'hi': '{list} लिस्ट खाली है।', 'en': 'Your {list} list is empty.'},
  'list_removed': {'bn': '{x} সরিয়ে দিলাম।', 'hi': '{x} हटा दिया।', 'en': 'Removed {x}.'},
  'list_cleared': {'bn': '{list} লিস্ট মুছে দিলাম।', 'hi': '{list} लिस्ट साफ़ कर दी।', 'en': 'Cleared your {list} list.'},
  'failed': {
    'bn': 'দুঃখিত, এটা করতে পারলাম না।',
    'hi': 'माफ़ कीजिए, यह नहीं कर पाई।',
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
  /// Ask before sending a message by voice (true = send).
  Future<bool> confirmSend(String to, String text);

  /// Open the two-person interpreter screen.
  Future<void> openInterpreter();

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

  /// Carries out [a]. [heard] is what the user said (used for live answers and memory).
  Future<String> run(AssistantAction a, {String heard = '', List<ChatTurn> history = const []}) async {
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
          await Reminders.instance.add(text, when, repeat: a.repeat);
          await _maybeReliabilityTip();
          if (a.repeat != null) {
            final rep = {
              'daily': {'bn': 'প্রতিদিন', 'hi': 'हर दिन', 'en': 'every day'},
              'weekly': {'bn': 'প্রতি সপ্তাহে', 'hi': 'हर हफ़्ते', 'en': 'every week'},
            }[a.repeat]![lang.code]!;
            return said('reminder_repeat', {'rep': rep, 'x': '${_two(when.hour)}:${_two(when.minute)}'});
          }
          return said('reminder', {'x': _timeText(when)});

        case ActionType.openApp:
          final appName = (a.app ?? '').replaceFirst(RegExp(r'^(my|the|আমার|मेरा|मेरी)\s+', caseSensitive: false), '').trim();
          // 1) a well-known app, 2) any installed app with that name, 3) Play Store.
          final known = packageForApp(appName);
          if (known != null && await AppLauncher.launch(known)) {
            return said('opening', {'x': appName});
          }
          final installed = await AppLauncher.findInstalled(appName);
          if (installed != null && await AppLauncher.launch(installed)) {
            return said('opening', {'x': appName});
          }
          await _open('market://search?q=${Uri.encodeComponent(appName)}');
          return phrase('no_app', lang, {'x': appName});

        case ActionType.whatsapp:
          // Nobody to message: just open WhatsApp (or WhatsApp Business).
          if (a.contact == null && (a.message ?? '').isEmpty) {
            final wa = await AppLauncher.launch('com.whatsapp') ||
                await AppLauncher.launch('com.whatsapp.w4b');
            if (wa) {
              return said('opening', {'x': 'WhatsApp'});
            }
          }
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

        case ActionType.multi:
          final results = <String>[];
          for (final step in a.steps) {
            if (step.type == ActionType.multi) {
              continue;
            }
            results.add(await run(step, heard: heard, history: history));
          }
          return results.where((r) => r.trim().isNotEmpty).join(' ');

        case ActionType.remember:
          final fact = (a.message ?? a.query ?? '').trim();
          if (fact.isEmpty) {
            return phrase('failed', lang);
          }
          await Memory.instance.add(fact);
          return said('remembered');

        case ActionType.forget:
          final what = (a.query ?? a.message ?? '').trim();
          final n = what.isEmpty ? 0 : await Memory.instance.forget(what);
          return phrase(n > 0 ? 'forgot' : 'forget_none', lang);

        case ActionType.recall:
          final items = Memory.instance.items;
          if (items.isEmpty) {
            return phrase('recall_none', lang);
          }
          if (a.reply.isNotEmpty) {
            return a.reply;
          }
          final last = items.length > 8 ? items.sublist(items.length - 8) : items;
          return phrase('recall_some', lang, {'x': last.map((m) => m.text).join('. ')});

        case ActionType.readMessages:
          return await _readMessages(a, lang);

        case ActionType.replyMessage:
          return await _replyMessage(a, lang);

        case ActionType.phone:
          return await _phone(a.setting ?? '', lang);

        case ActionType.list:
          final name = Lists.nameFor(a.query);
          final shown = {
                'shopping': {'bn': 'বাজারের', 'hi': 'शॉपिंग', 'en': 'shopping'},
                'to-do': {'bn': 'কাজের', 'hi': 'काम की', 'en': 'to-do'},
              }[name]?[lang.code] ??
              name;
          switch (a.setting) {
            case 'add':
              final added = await Lists.instance.add(name, a.message ?? '');
              if (added.isEmpty) {
                return phrase('failed', lang);
              }
              return phrase('list_added', lang, {'list': shown, 'x': added.join(', ')});
            case 'remove':
              final ok = await Lists.instance.remove(name, a.message ?? '');
              return ok ? phrase('list_removed', lang, {'x': a.message ?? ''}) : phrase('failed', lang);
            case 'clear':
              await Lists.instance.clear(name);
              return phrase('list_cleared', lang, {'list': shown});
            default:
              final items = Lists.instance.items(name);
              return items.isEmpty
                  ? phrase('list_empty', lang, {'list': shown})
                  : phrase('list_read', lang, {'list': shown, 'x': items.join(', ')});
          }

        case ActionType.interpreter:
          await ui.openInterpreter();
          return said('interpreter');

        default:
          // Fresh facts from the web when the AI says the answer needs them.
          if (a.live && settings.hasAi && heard.isNotEmpty) {
            try {
              return await gemini.liveAnswer(heard, history, lang);
            } catch (e) {
              debugPrint('Live answer failed: $e');
            }
          }
          if (a.reply.isNotEmpty) {
            return a.reply;
          }
          // No AI: maybe it's about something the user asked Maya to remember.
          final found = Memory.instance.search(heard);
          if (found.isNotEmpty) {
            return phrase('memory_answer', lang, {'x': found.take(2).map((m) => m.text).join('. ')});
          }
          return phrase('need_ai', lang);
      }
    } catch (e) {
      debugPrint('Action ${a.type} failed: $e');
      return phrase('failed', lang);
    }
  }

  /// Messages already read aloud (so "read my messages" only reads new ones).
  final _readIds = <int>{};

  Future<String> _readMessages(AssistantAction a, AppLanguage lang) async {
    if (!await Messages.hasAccess()) {
      await Messages.openAccessSettings();
      return phrase('msg_access', lang);
    }
    var list = await Messages.recent();
    final from = a.contact?.trim();
    if (from != null && from.isNotEmpty) {
      final want = from.toLowerCase();
      list = list
          .where((m) =>
              m.sender.toLowerCase().contains(want) || ContactFinder.soundsLike(want, m.sender.toLowerCase()) > 0)
          .toList();
    } else {
      final cutoff = DateTime.now().subtract(const Duration(hours: 24));
      list = list.where((m) => !_readIds.contains(m.id) && m.time.isAfter(cutoff)).toList();
    }
    if (list.isEmpty) {
      return from != null && from.isNotEmpty ? phrase('msg_none_from', lang, {'x': from}) : phrase('msg_none', lang);
    }
    final newest = list.length > 6 ? list.sublist(list.length - 6) : list;
    _readIds.addAll(newest.map((m) => m.id));
    Messages.lastRead = newest.last;
    final spoken = newest.map((m) => '${m.sender}, ${m.app}: ${m.text}.').join(' ');
    return '$spoken ${newest.last.canReply ? phrase('msg_reply_hint', lang) : ''}'.trim();
  }

  Future<String> _replyMessage(AssistantAction a, AppLanguage lang) async {
    var target = Messages.lastRead;
    final who = a.contact?.trim().toLowerCase();
    if (who != null && who.isNotEmpty) {
      final list = await Messages.recent();
      final matches = list
          .where((m) => m.sender.toLowerCase().contains(who) || ContactFinder.soundsLike(who, m.sender.toLowerCase()) > 0)
          .toList();
      if (matches.isNotEmpty) {
        target = matches.last;
      }
    }
    if (target == null) {
      return phrase('msg_who', lang);
    }
    final text = (a.message ?? '').trim();
    if (text.isEmpty) {
      return phrase('msg_what', lang);
    }
    if (!target.canReply) {
      return phrase('msg_cant_reply', lang);
    }
    if (!await ui.confirmSend(target.sender, text)) {
      return phrase('cancelled', lang);
    }
    final ok = await Messages.reply(target, text);
    return ok ? phrase('msg_sent', lang, {'x': target.sender}) : phrase('msg_cant_reply', lang);
  }

  Future<String> _phone(String setting, AppLanguage lang) async {
    String names(String en, String bn, String hi) => {'bn': bn, 'hi': hi, 'en': en}[lang.code]!;
    switch (setting) {
      case 'torch_on':
        return await PhoneControl.torch(true) ? phrase('torch_on', lang) : phrase('failed', lang);
      case 'torch_off':
        return await PhoneControl.torch(false) ? phrase('torch_off', lang) : phrase('failed', lang);
      case 'volume_up':
      case 'volume_down':
      case 'volume_max':
      case 'mute':
        final how = setting == 'mute' ? 'mute' : setting.replaceFirst('volume_', '');
        return await PhoneControl.volume(how) ? phrase('volume', lang) : phrase('failed', lang);
      case 'vibrate':
      case 'ring':
        final ok = await PhoneControl.ringer(setting);
        return ok
            ? phrase('ringer', lang, {
                'x': setting == 'vibrate' ? names('vibrate', 'ভাইব্রেট', 'वाइब्रेट') : names('ring', 'রিং', 'रिंग'),
              })
            : phrase('settings_open', lang, {'x': names('Do Not Disturb', 'বিরক্ত করবেন না', 'डू नॉट डिस्टर्ब')});
      case 'battery':
        final b = await PhoneControl.battery();
        if (b == null) {
          return phrase('failed', lang);
        }
        final charging = b.charging ? names(', charging', ', চার্জ হচ্ছে', ', चार्ज हो रही है') : '';
        return phrase('battery', lang, {'x': '${b.level}', 'c': charging});
      case 'wifi':
      case 'bluetooth':
      case 'dnd':
      case 'brightness':
      case 'data':
        final label = {
          'wifi': 'Wi-Fi',
          'bluetooth': 'Bluetooth',
          'dnd': names('Do Not Disturb', 'বিরক্ত করবেন না', 'डू नॉट डिस्टर्ब'),
          'brightness': names('brightness', 'উজ্জ্বলতা', 'ब्राइटनेस'),
          'data': names('mobile data', 'মোবাইল ডেটা', 'मोबाइल डेटा'),
        }[setting] ?? setting;
        return await PhoneControl.panel(setting)
            ? phrase('settings_open', lang, {'x': label})
            : phrase('failed', lang);
      default:
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
            'x': today.map((r) => '${_two(r.next.hour)}:${_two(r.next.minute)} ${r.text}').join(', '),
          });
    if (settings.hasAi) {
      try {
        final name = settings.userName.isEmpty ? '' : 'Greet ${settings.userName} by name. ';
        final h = DateTime.now().hour;
        final greet = h < 12 ? 'Good morning' : (h < 17 ? 'Good afternoon' : 'Good evening');
        return await gemini.phrase('${name}$greet briefing (it is ${_two(h)}:00 now). $weather $remindersText', lang);
      } catch (_) {}
    }
    return '$weather $remindersText';
  }
}
