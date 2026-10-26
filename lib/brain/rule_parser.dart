import 'action.dart';

/// Understands common commands without the internet or an AI key.
/// Handles English, Hindi and Bengali phrasings of calls, alarms, timers,
/// reminders, opening apps, WhatsApp, navigation, weather and briefings.
class RuleParser {
  const RuleParser();

  static const _digitMap = {
    '০': '0', '১': '1', '২': '2', '৩': '3', '৪': '4', '৫': '5', '৬': '6', '৭': '7', '৮': '8', '৯': '9',
    '०': '0', '१': '1', '२': '2', '३': '3', '४': '4', '५': '5', '६': '6', '७': '7', '८': '8', '९': '9',
  };

  /// Single-character Bengali/Hindi letters with a dot (nukta) -> the two-character
  /// form this file's keywords use, so "য়" matches however the keyboard or
  /// speech engine encoded it.
  static const _nukta = {
    'ড়': 'ড়', // ড়
    'ঢ়': 'ঢ়', // ঢ়
    'য়': 'য়', // য়
    'क़': 'क़', // क़
    'ख़': 'ख़', // ख़
    'ग़': 'ग़', // ग़
    'ज़': 'ज़', // ज़
    'ड़': 'ड़', // ड़
    'ढ़': 'ढ़', // ढ़
    'फ़': 'फ़', // फ़
    'य़': 'य़', // य़
  };

  /// Bengali/Hindi digits -> 0-9, one spelling for dotted letters, lower-case, single spaces.
  static String normalize(String input) {
    final buf = StringBuffer();
    for (final ch in input.split('')) {
      final decomposed = _nukta[ch];
      if (decomposed != null) {
        buf.write(decomposed);
        continue;
      }
      buf.write(_digitMap[ch] ?? ch);
    }
    return buf.toString().toLowerCase().replaceAll(RegExp(r'[।?!,]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  static final _normalCache = <String, String>{};

  /// True if [text] contains any of [words] (spelled either way for dotted letters).
  static bool _hasAny(String text, List<String> words) =>
      words.any((w) => text.contains(_normalCache.putIfAbsent(w, () => normalize(w))));

  static const _timerWords = ['timer', 'টাইমার', 'टाइमर'];
  static const _alarmWords = ['alarm', 'অ্যালার্ম', 'এলার্ম', 'অ্যালার্ম', 'अलार्म', 'wake me', 'উঠিয়ে', 'জাগিয়ে', 'उठा'];
  static const _remindWords = ['remind', 'reminder', 'মনে করিয়ে', 'মনে করাবে', 'রিমাইন্ড', 'याद दिला', 'रिमाइंड'];
  static const _weatherWords = ['weather', 'আবহাওয়া', 'আবহাওয়া', 'বৃষ্টি', 'मौसम', 'बारिश', 'temperature', 'তাপমাত্রা', 'तापमान'];
  static const _briefingWords = ['good morning', 'সুপ্রভাত', 'শুভ সকাল', 'सुप्रभात', 'गुड मॉर्निंग', 'briefing', 'my day', 'আজ কী আছে', 'आज क्या है'];
  static const _whatsappWords = ['whatsapp', 'হোয়াটসঅ্যাপ', 'হোয়াটসঅ্যাপ', 'व्हाट्सएप', 'व्हाट्सऐप'];
  static const _navigateWords = ['navigate', 'direction', 'route to', 'take me to', 'রাস্তা', 'নিয়ে চলো', 'रास्ता', 'ले चलो'];
  static const _pmWords = ['pm', 'p.m', 'evening', 'night', 'afternoon', 'রাত', 'বিকেল', 'সন্ধ্যা', 'দুপুর', 'शाम', 'रात', 'दोपहर'];
  static const _amWords = ['am', 'a.m', 'morning', 'সকাল', 'ভোর', 'सुबह'];

  /// "Hey Maya", "Maya,", "মায়া", "माया" at the start of a command.
  static final _wakeWord = RegExp(
    '^\\s*(?:(?:hey|hi|ok|okay|হে|হাই|अरे|हे)\\s+)?'
    '(?:maya|মায়া|মায়া|माया)[\\s,।!.]*',
    caseSensitive: false,
  );

  /// Words that join several commands: "set an alarm at 6 and remind me…".
  static final _joiners = RegExp(
    r'\s*,?\s+(?:and then|then|and|আর তারপর|তারপর|আর|এবং|और फिर|फिर|और)\s+',
    caseSensitive: false,
  );

  AssistantAction parse(String input, {DateTime? now}) {
    final spoken = input.replaceFirst(_wakeWord, '');
    final clock = now ?? DateTime.now();
    final whole = _parseOne(spoken, clock);

    // Several commands in one sentence? Only if every part is a real command.
    final parts = spoken.split(_joiners).map((p) => p.trim()).where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2 && parts.length <= 5) {
      final steps = [for (final p in parts) _parseOne(p, clock)];
      final allReal = steps.every((a) => a.type != ActionType.answer && a.type != ActionType.search);
      if (allReal) {
        return AssistantAction(type: ActionType.multi, steps: steps);
      }
    }
    return whole;
  }

  AssistantAction _parseOne(String spoken, DateTime clock) {
    final text = normalize(spoken);

    if (text.isEmpty) {
      return const AssistantAction(type: ActionType.answer);
    }

    final memory = _memory(text, spoken);
    if (memory != null) {
      return memory;
    }

    if (_hasAny(text, _timerWords)) {
      final seconds = _duration(text);
      if (seconds != null) {
        return AssistantAction(type: ActionType.timer, seconds: seconds);
      }
    }

    if (_hasAny(text, _remindWords)) {
      final repeat = _repeat(text);
      var when = _reminderTime(text, clock);
      if (repeat != null && when == null) {
        final t = _clockTime(text);
        if (t != null) {
          when = DateTime(clock.year, clock.month, clock.day, t.$1, t.$2);
          if (!when.isAfter(clock)) {
            when = when.add(const Duration(days: 1));
          }
        }
      }
      final what = _reminderText(spoken);
      return AssistantAction(type: ActionType.reminder, when: when, message: what, repeat: repeat);
    }

    if (_hasAny(text, _alarmWords)) {
      final t = _clockTime(text);
      if (t != null) {
        return AssistantAction(type: ActionType.alarm, hour: t.$1, minute: t.$2);
      }
    }

    if (_hasAny(text, _briefingWords)) {
      return const AssistantAction(type: ActionType.briefing);
    }

    if (_hasAny(text, _weatherWords)) {
      return AssistantAction(type: ActionType.weather, place: _afterAny(text, [' in ', ' at ']));
    }

    final device = _device(text);
    if (device != null) {
      return device;
    }

    // "open WhatsApp" / "হোয়াটসঅ্যাপ খোলো" just opens the app.
    final openOnly = _openApp(text);
    if (openOnly != null && _whatsappWords.contains(openOnly)) {
      return AssistantAction(type: ActionType.openApp, app: openOnly);
    }

    if (_hasAny(text, _whatsappWords)) {
      return AssistantAction(type: ActionType.whatsapp, contact: _whatsappContact(text), message: _whatsappMessage(text));
    }

    final call = _callContact(text);
    if (call != null) {
      return AssistantAction(type: ActionType.call, contact: call);
    }

    if (_hasAny(text, _navigateWords)) {
      final place = _afterAny(text, ['navigate to ', 'directions to ', 'direction to ', 'route to ', 'take me to ']) ??
          _beforeAny(text, [' রাস্তা', ' নিয়ে চলো', ' का रास्ता', ' ले चलो', ' রাস্তা দেখাও']);
      if (place != null && place.isNotEmpty) {
        return AssistantAction(type: ActionType.navigate, place: place);
      }
    }

    final app = _openApp(text);
    if (app != null) {
      return AssistantAction(type: ActionType.openApp, app: app);
    }

    final search = _afterAny(text, ['search for ', 'search ', 'google ']) ??
        _beforeAny(text, [' সার্চ করো', ' খুঁজে দাও', ' सर्च करो', ' खोजो']);
    if (search != null && search.isNotEmpty) {
      return AssistantAction(type: ActionType.search, query: search);
    }

    return const AssistantAction(type: ActionType.answer);
  }

  // ---- memory, messages and the phone ----

  static AssistantAction? _memory(String text, String spoken) {
    final save = RegExp(r'^(?:please\s+)?(?:remember|note|keep in mind)\s+(?:that\s+)?(.+)$').firstMatch(text) ??
        RegExp(r'^(?:মনে রেখো|মনে রাখো|মনে রাখবে|याद रखना|याद रखो)\s+(?:যে|कि)?\s*(.+)$').firstMatch(text) ??
        RegExp(r'^(.+?)\s*(?:মনে রেখো|মনে রাখো|মনে রাখবে|याद रखना|याद रखो)$').firstMatch(text);
    if (save != null) {
      final fact = save.group(1)!.trim();
      // "remember to call Maa at 6" is a reminder, not a memory.
      if (fact.startsWith('to ') || RegExp(r'\d').hasMatch(fact) && _hasAny(fact, _amWords + _pmWords + ['at '])) {
        return null;
      }
      return AssistantAction(type: ActionType.remember, message: fact);
    }
    final forget = RegExp(r'^(?:please\s+)?forget\s+(?:about\s+|that\s+)?(.+)$').firstMatch(text) ??
        RegExp(r'^(.+?)\s*(?:ভুলে যাও|ভুলে যা|भूल जाओ|भूल जा)$').firstMatch(text);
    if (forget != null) {
      return AssistantAction(type: ActionType.forget, query: forget.group(1)!.trim());
    }
    if (RegExp(r'what do you remember|what have you remembered|কী মনে রেখেছ|কি মনে রেখেছ|क्या याद है|क्या याद रखा')
        .hasMatch(text)) {
      return const AssistantAction(type: ActionType.recall);
    }
    return null;
  }

  static AssistantAction? _device(String text) {
    // Messages
    final readFrom = RegExp(r'(?:read|any) (?:my )?(?:new )?messages? from (.+)$').firstMatch(text) ??
        RegExp(r'^(.+?)(?:র|এর|-এর)? মেসেজ পড়ো$').firstMatch(text) ??
        RegExp(r'^(.+?) (?:का|के) मैसेज पढ़ो$').firstMatch(text);
    final fromWho = readFrom?.group(1)?.trim();
    if (fromWho != null && !const {'new', 'my', 'the', 'নতুন', 'আমার', 'সব', 'नए', 'मेरे', 'सब'}.contains(fromWho)) {
      return AssistantAction(type: ActionType.readMessages, contact: fromWho);
    }
    if (RegExp(r'read (?:my |the )?(?:new |latest )?(?:whatsapp )?messages|who messaged|any new messages|'
            r'মেসেজ পড়|মেসেজ শোনাও|কে মেসেজ|मैसेज पढ़|मैसेज सुनाओ|किसका मैसेज')
        .hasMatch(text)) {
      return const AssistantAction(type: ActionType.readMessages);
    }
    final reply = RegExp(r'^(?:reply)(?: to (\S+))?\s*(?:saying|that|:)?\s+(.+)$').firstMatch(text) ??
        RegExp(r'^(?:রিপ্লাই|উত্তর দাও|জবাব দাও|रिप्लाई|जवाब दो)\s*(?:করো|कर)?\s+(?:যে|कि)?\s*(.+)$').firstMatch(text);
    if (reply != null) {
      final hasTo = reply.groupCount >= 2;
      return AssistantAction(
        type: ActionType.replyMessage,
        contact: hasTo ? reply.group(1) : null,
        message: (hasTo ? reply.group(2) : reply.group(1))!.trim(),
      );
    }

    // Torch
    final torch = _hasAny(text, ['torch', 'flashlight', 'flash light', 'টর্চ', 'টর্চলাইট', 'टॉर्च', 'फ्लैशलाइट']);
    if (torch) {
      final off = _hasAny(text, ['off', 'বন্ধ', 'নেভাও', 'নিভিয়ে', 'बंद', 'बुझा']);
      return AssistantAction(type: ActionType.phone, setting: off ? 'torch_off' : 'torch_on');
    }
    // Volume
    if (_hasAny(text, ['volume', 'ভলিউম', 'আওয়াজ', 'आवाज़', 'आवाज', 'वॉल्यूम'])) {
      if (_hasAny(text, ['mute', 'মিউট', 'म्यूट'])) {
        return const AssistantAction(type: ActionType.phone, setting: 'mute');
      }
      if (_hasAny(text, ['full', 'max', 'পুরো', 'फुल', 'पूरी'])) {
        return const AssistantAction(type: ActionType.phone, setting: 'volume_max');
      }
      final down = _hasAny(text, ['down', 'lower', 'decrease', 'reduce', 'কমাও', 'কম', 'कम']);
      return AssistantAction(type: ActionType.phone, setting: down ? 'volume_down' : 'volume_up');
    }
    if (_hasAny(text, ['vibrate', 'vibration', 'ভাইব্রেট', 'वाइब्रेट'])) {
      return const AssistantAction(type: ActionType.phone, setting: 'vibrate');
    }
    if (_hasAny(text, ['ring mode', 'normal mode', 'sound mode', 'রিং মোড', 'रिंग मोड'])) {
      return const AssistantAction(type: ActionType.phone, setting: 'ring');
    }
    if (_hasAny(text, ['battery', 'charge left', 'ব্যাটারি', 'চার্জ কত', 'बैटरी', 'चार्ज कितना'])) {
      return const AssistantAction(type: ActionType.phone, setting: 'battery');
    }
    if (_hasAny(text, ['wifi', 'wi-fi', 'wi fi', 'ওয়াইফাই', 'ওয়াই-ফাই', 'वाईफाई', 'वाई-फाई'])) {
      return const AssistantAction(type: ActionType.phone, setting: 'wifi');
    }
    if (_hasAny(text, ['bluetooth', 'ব্লুটুথ', 'ब्लूटूथ'])) {
      return const AssistantAction(type: ActionType.phone, setting: 'bluetooth');
    }
    if (_hasAny(text, ['do not disturb', 'dnd', 'ডু নট ডিস্টার্ব', 'डू नॉट डिस्टर्ब'])) {
      return const AssistantAction(type: ActionType.phone, setting: 'dnd');
    }
    if (_hasAny(text, ['brightness', 'উজ্জ্বলতা', 'ব্রাইটনেস', 'ब्राइटनेस'])) {
      return const AssistantAction(type: ActionType.phone, setting: 'brightness');
    }
    if (_hasAny(text, ['mobile data', 'internet on', 'মোবাইল ডেটা', 'মোবাইল ডাটা', 'मोबाइल डेटा'])) {
      return const AssistantAction(type: ActionType.phone, setting: 'data');
    }
    if (_hasAny(text, ['interpreter', 'translate conversation', 'translator', 'দোভাষী', 'दुभाषिया', 'ট্রান্সলেটর'])) {
      return const AssistantAction(type: ActionType.interpreter);
    }
    return null;
  }

  static String? _repeat(String text) {
    if (_hasAny(text, ['every day', 'everyday', 'daily', 'each day', 'প্রতিদিন', 'রোজ', 'हर दिन', 'रोज़', 'रोज', 'रोजाना'])) {
      return 'daily';
    }
    if (_hasAny(text, ['every week', 'weekly', 'every monday', 'every tuesday', 'every wednesday', 'every thursday',
      'every friday', 'every saturday', 'every sunday', 'প্রতি সপ্তাহে', 'প্রতি সোমবার', 'প্রতি রবিবার', 'हर हफ्ते', 'हर हफ़्ते',
      'हर सोमवार', 'हर रविवार'])) {
      return 'weekly';
    }
    return null;
  }

  // ---- durations and times ----

  static int? _duration(String text) {
    var total = 0;
    var found = false;
    final units = <RegExp, int>{
      RegExp(r'(\d+)\s*(hours?|hrs?|ঘণ্টা|ঘন্টা|घंटे|घंटा)'): 3600,
      RegExp(r'(\d+)\s*(minutes?|mins?|মিনিট|मिनट)'): 60,
      RegExp(r'(\d+)\s*(seconds?|secs?|সেকেন্ড|सेकंड)'): 1,
    };
    units.forEach((re, mult) {
      for (final m in re.allMatches(text)) {
        total += int.parse(m.group(1)!) * mult;
        found = true;
      }
    });
    if (!found) {
      if (_hasAny(text, ['half an hour', 'আধ ঘণ্টা', 'আধা ঘণ্টা', 'आधा घंटा', 'आधे घंटे'])) {
        return 1800;
      }
      final bare = RegExp(r'(\d+)').firstMatch(text);
      if (bare != null) {
        return int.parse(bare.group(1)!) * 60; // "timer 10" means minutes
      }
      return null;
    }
    return total > 0 ? total : null;
  }

  /// "6", "6:30", "6.30", "6 টা", "6 बजे", "6 pm" -> (hour, minute) on a 24h clock.
  static (int, int)? _clockTime(String text) {
    // Prefer a number that looks like a time ("at 6", "6 pm", "6:30", "৬টায়", "6 बजे"),
    // so amounts like "pay 500" are not read as the hour.
    final timeLike = RegExp(
      r'(?:at|by|@)\s*(\d{1,2})(?:\s*[:.]\s*(\d{2}))?'
      r'|(\d{1,2})(?:\s*[:.]\s*(\d{2}))?\s*(?:am|pm|a\.m|p\.m|o.?clock|টা|টায়|টার|বাজে|बजे|baje|tay)',
    ).firstMatch(text);
    String? h;
    String? mm;
    if (timeLike != null) {
      h = timeLike.group(1) ?? timeLike.group(3);
      mm = timeLike.group(2) ?? timeLike.group(4);
    } else {
      for (final m in RegExp(r'(?<!\d)(\d{1,2})(?:\s*[:.]\s*(\d{2}))?(?!\d)').allMatches(text)) {
        if (int.parse(m.group(1)!) <= 23) {
          h = m.group(1);
          mm = m.group(2);
          break;
        }
      }
    }
    if (h == null) {
      return null;
    }
    var hour = int.parse(h);
    final minute = mm == null ? 0 : int.parse(mm);
    if (hour > 23 || minute > 59) {
      return null;
    }
    if (_hasAny(text, _pmWords) && hour < 12) {
      hour += 12;
    } else if (_hasAny(text, _amWords) && hour == 12) {
      hour = 0;
    }
    return (hour, minute);
  }

  static DateTime? _reminderTime(String text, DateTime now) {
    final rel = RegExp(r'(?:in|after)?\s*(\d+)\s*(minutes?|mins?|hours?|hrs?|মিনিট|ঘণ্টা|ঘন্টা|मिनट|घंटे|घंटा)\s*(?:পরে|পর|बाद|later)?')
        .firstMatch(text);
    final hasRelWord = _hasAny(text, [' in ', 'after', 'পরে', 'পর ', 'बाद', 'later']) || text.startsWith('in ');
    if (rel != null && hasRelWord) {
      final n = int.parse(rel.group(1)!);
      final unit = rel.group(2)!;
      final isHour = unit.startsWith('h') || unit.contains('ঘণ') || unit.contains('ঘন') || unit.contains('घं');
      return now.add(Duration(minutes: isHour ? n * 60 : n));
    }
    final t = _clockTime(text);
    if (t == null) {
      return null;
    }
    var day = DateTime(now.year, now.month, now.day, t.$1, t.$2);
    if (_hasAny(text, ['tomorrow', 'কাল', 'आगामी', 'कल'])) {
      day = day.add(const Duration(days: 1));
    } else if (!day.isAfter(now)) {
      day = day.add(const Duration(days: 1));
    }
    return day;
  }

  /// The thing to remember, with the command words stripped off (keeps the original script).
  static String _reminderText(String original) {
    var s = original.trim();
    final patterns = [
      RegExp(r'^(please\s+)?remind me( to)?\s*', caseSensitive: false),
      RegExp(r'^(set\s+)?(a\s+)?reminder( to| for)?\s*', caseSensitive: false),
      RegExp(r'\s*(in|after)\s+\d+\s*(minutes?|mins?|hours?|hrs?)\s*$', caseSensitive: false),
      RegExp(r'\s*(at|by)\s+\d{1,2}([:.]\d{2})?\s*(am|pm)?\s*(tomorrow|today)?\s*$', caseSensitive: false),
      RegExp(r'\s*(tomorrow|today)\s*$', caseSensitive: false),
      RegExp(r'\s*(মনে করিয়ে দিও|মনে করিয়ে দেবে|মনে করাবে|মনে করিয়ে দাও|রিমাইন্ড করো)\s*$'),
      RegExp(r'\s*(याद दिलाना|याद दिला देना|याद दिलाओ|रिमाइंड करो)\s*$'),
    ];
    for (final p in patterns) {
      s = s.replaceAll(p, '').trim();
    }
    return s.isEmpty ? original.trim() : s;
  }

  // ---- people, apps and places ----

  static String? _callContact(String text) {
    final english =
        RegExp(r'^(?:(?:please|can you|could you|hey maya)\s+)*(?:call|phone|dial|ring)\s+(.+?)(?:\s+(?:now|please))?$')
            .firstMatch(text);
    if (english != null) {
      return english.group(1)!.trim();
    }
    final bengali = RegExp(r'^(.+?)\s*(?:কে|কে একটা)?\s*(?:ফোন|কল)\s*(?:করো|কর|লাগাও|দাও)').firstMatch(text);
    if (bengali != null) {
      return bengali.group(1)!.replaceAll(RegExp(r'\s*কে$'), '').trim();
    }
    final hindi = RegExp(r'^(.+?)\s*(?:को)?\s*(?:फोन|फ़ोन|कॉल|call)\s*(?:करो|कर|लगाओ|मिलाओ|karo|lagao)').firstMatch(text);
    if (hindi != null) {
      return hindi.group(1)!.replaceAll(RegExp(r'\s*(को|ko|ke)$'), '').trim();
    }
    final hinglish = RegExp(r'^(.+?)\s+(?:ko|ke)\s+(?:call|phone)\s+(?:karo|lagao|koro)').firstMatch(text);
    if (hinglish != null) {
      return hinglish.group(1)!.trim();
    }
    // "কল কাজী নাসার", "ফোন করো মাকে", "कॉल राहुल": the call word comes first.
    final leading = RegExp(
      r'^(?:কল|ফোন|कॉल|फोन|फ़ोन)\s+(?:(?:করো|কর|লাগাও|দাও|करो|लगाओ|मिलाओ)\s+)?(.+?)$',
    ).firstMatch(text);
    if (leading != null) {
      final name = leading.group(1)!.replaceAll(RegExp(r'\s*(?:কে|को)$'), '').trim();
      if (name.isNotEmpty) {
        return name;
      }
    }
    return null;
  }

  static String? _whatsappContact(String text) {
    final m = RegExp(r'(?:whatsapp|হোয়াটসঅ্যাপ|व्हाट्सएप)\s+(?:to\s+|message\s+)?([^\s:]+)\s*:').firstMatch(text) ??
        RegExp(r'(?:to|message|tell)\s+([^\s:]+)').firstMatch(text) ??
        RegExp(r'([^\s]+)\s*(?:কে|को)\s').firstMatch(text);
    final name = m?.group(1)?.trim();
    if (name == null || _whatsappWords.contains(name) || name == 'on') {
      return null;
    }
    return name;
  }

  static String? _whatsappMessage(String text) {
    final colon = text.indexOf(':');
    if (colon >= 0 && colon < text.length - 1) {
      return text.substring(colon + 1).trim();
    }
    final m = RegExp(r'(?:saying|that|bolo|বলো|লেখো|लिखो|कि)\s+(.+)$').firstMatch(text);
    return m?.group(1)?.trim();
  }

  static String? _openApp(String text) {
    final english = RegExp(r'^(?:please\s+)?(?:open|launch|start)\s+(.+?)(?:\s+app)?$').firstMatch(text);
    if (english != null) {
      return english.group(1)!.trim();
    }
    final other = RegExp(r'^(.+?)\s*(?:app\s*)?(?:খোলো|খোল|চালু করো|खोलो|खोल|चालू करो|kholo|kholo na)$').firstMatch(text);
    if (other != null) {
      return other.group(1)!.trim();
    }
    return null;
  }

  static String? _afterAny(String text, List<String> markers) {
    for (final m in markers) {
      final i = text.indexOf(m);
      if (i >= 0) {
        final rest = text.substring(i + m.length).trim();
        if (rest.isNotEmpty) {
          return rest;
        }
      }
    }
    return null;
  }

  static String? _beforeAny(String text, List<String> markers) {
    for (final m in markers) {
      final i = text.indexOf(m);
      if (i > 0) {
        return text.substring(0, i).trim();
      }
    }
    return null;
  }
}
