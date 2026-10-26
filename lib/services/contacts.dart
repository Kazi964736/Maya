import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';

class FoundContact {
  const FoundContact(this.name, this.number);
  final String name;
  final String number;
}

/// Finds a phone contact from a spoken name ("Maa", "Rahul da", "बाबा").
class ContactFinder {
  ContactFinder._();
  static final instance = ContactFinder._();

  List<Contact>? _cache;
  DateTime? _cachedAt;

  /// Spoken family words -> names people commonly save them under.
  static const _aliases = {
    'maa': ['maa', 'ma', 'mom', 'mummy', 'mother', 'amma', 'মা', 'माँ', 'मां', 'मम्मी'],
    'baba': ['baba', 'papa', 'dad', 'daddy', 'father', 'বাবা', 'बाबा', 'पापा'],
    'didi': ['didi', 'sister', 'দিদি', 'दीदी'],
    'dada': ['dada', 'bhaiya', 'brother', 'দাদা', 'भैया'],
  };

  static String _clean(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'\b(da|di|ji|bhai|sir|madam)\b'), '')
      .replaceAll(RegExp(r'\s+(দা|দি|জি|জী|जी)$'), '')
      // Keep letters, vowel signs (Bengali/Hindi matras are "marks") and digits.
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), '')
      .trim();

  Future<bool> ensurePermission() async {
    try {
      return await FlutterContacts.requestPermission(readonly: true);
    } catch (e) {
      debugPrint('Contacts permission failed: $e');
      return false;
    }
  }

  /// Every contact that matches the spoken name equally well (best score only).
  /// Returns null when contacts can't be read (no permission).
  Future<List<FoundContact>?> findAll(String spokenName) async {
    if (!await ensurePermission()) {
      return null;
    }
    try {
      // Re-read every few minutes so newly saved contacts are found.
      final stale = _cachedAt == null || DateTime.now().difference(_cachedAt!) > const Duration(minutes: 5);
      if (_cache == null || stale) {
        _cache = await FlutterContacts.getContacts(withProperties: true);
        _cachedAt = DateTime.now();
      }
    } catch (e) {
      debugPrint('Reading contacts failed: $e');
      return null;
    }
    final contacts = _cache!.where((c) => c.phones.isNotEmpty).toList();
    final wanted = _clean(spokenName);
    if (wanted.isEmpty) {
      return const [];
    }

    // Family words: match any saved name in the same group.
    final group = _aliases.values.firstWhere(
      (words) => words.contains(wanted),
      orElse: () => const [],
    );
    final candidates = group.isNotEmpty ? group : [wanted];

    var bestScore = 0;
    final best = <FoundContact>[];
    for (final c in contacts) {
      final name = _clean(c.displayName);
      if (name.isEmpty) {
        continue;
      }
      var score = 0;
      for (final w in candidates) {
        int s = 0;
        if (name == w) {
          s = 100;
        } else if (name.split(' ').contains(w)) {
          s = 80;
        } else if (name.startsWith(w)) {
          s = 60;
        } else if (w.length >= 3 && name.contains(w)) {
          s = 40;
        } else {
          s = soundsLike(w, name);
        }
        if (s > score) {
          score = s;
        }
      }
      if (score == 0 || score < bestScore) {
        continue;
      }
      if (score > bestScore) {
        bestScore = score;
        best.clear();
      }
      final number = c.phones.first.number;
      final digits = number.replaceAll(RegExp(r'[^0-9]'), '');
      final duplicate = best.any((f) => f.number.replaceAll(RegExp(r'[^0-9]'), '').endsWith(
            digits.length > 10 ? digits.substring(digits.length - 10) : digits,
          ));
      if (!duplicate) {
        best.add(FoundContact(c.displayName, number));
      }
    }
    return best;
  }

  /// Sound-alike score for names spelled or heard differently:
  /// "Noushad" / "Nowshad" / "নওশাদ" all sound like "Naushad".
  /// 35 when every spoken word sounds like a word of the name, 25 when the
  /// first one does, else 0.
  @visibleForTesting
  static int soundsLike(String spoken, String saved) {
    final said = spoken.split(' ').map(_skeleton).where((k) => k.length >= 2).toList();
    final have = saved.split(' ').map(_skeleton).where((k) => k.length >= 2).toList();
    if (said.isEmpty || have.isEmpty) {
      return 0;
    }
    bool close(String a, String b) => a == b || (a.length >= 3 && b.length >= 3 && a[0] == b[0] && _distance(a, b) <= 1);
    final matched = said.where((k) => have.any((h) => close(k, h))).length;
    if (matched == said.length) {
      return 35;
    }
    if (have.any((h) => close(said.first, h))) {
      return 25;
    }
    return 0;
  }

  static const _indic = {
    // Bengali
    'ক': 'k', 'খ': 'k', 'গ': 'g', 'ঘ': 'g', 'ঙ': 'n', 'চ': 'c', 'ছ': 'c', 'জ': 'j', 'ঝ': 'j', 'ঞ': 'n',
    'ট': 't', 'ঠ': 't', 'ড': 'd', 'ঢ': 'd', 'ণ': 'n', 'ত': 't', 'থ': 't', 'দ': 'd', 'ধ': 'd', 'ন': 'n',
    'প': 'p', 'ফ': 'f', 'ব': 'b', 'ভ': 'b', 'ম': 'm', 'য': 'j', 'র': 'r', 'ল': 'l', 'শ': 's', 'ষ': 's',
    'স': 's', 'হ': 'h', 'ড়': 'r', 'ঢ়': 'r', 'য়': 'y', 'ৎ': 't', 'ং': 'n', 'ঁ': '',
    'অ': 'a', 'আ': 'a', 'ই': 'i', 'ঈ': 'i', 'উ': 'u', 'ঊ': 'u', 'ঋ': 'ri', 'এ': 'e', 'ঐ': 'e', 'ও': 'o', 'ঔ': 'o',
    'া': 'a', 'ি': 'i', 'ী': 'i', 'ু': 'u', 'ূ': 'u', 'ৃ': 'ri', 'ে': 'e', 'ৈ': 'e', 'ো': 'o', 'ৌ': 'o',
    // Devanagari
    'क': 'k', 'ख': 'k', 'ग': 'g', 'घ': 'g', 'ङ': 'n', 'च': 'c', 'छ': 'c', 'ज': 'j', 'झ': 'j', 'ञ': 'n',
    'ट': 't', 'ठ': 't', 'ड': 'd', 'ढ': 'd', 'ण': 'n', 'त': 't', 'थ': 't', 'द': 'd', 'ध': 'd', 'न': 'n',
    'प': 'p', 'फ': 'f', 'ब': 'b', 'भ': 'b', 'म': 'm', 'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 's',
    'ष': 's', 'स': 's', 'ह': 'h', 'ं': 'n', 'ँ': '',
    'अ': 'a', 'आ': 'a', 'इ': 'i', 'ई': 'i', 'उ': 'u', 'ऊ': 'u', 'ऋ': 'ri', 'ए': 'e', 'ऐ': 'e', 'ओ': 'o', 'औ': 'o',
    'ा': 'a', 'ि': 'i', 'ी': 'i', 'ु': 'u', 'ू': 'u', 'ृ': 'ri', 'े': 'e', 'ै': 'e', 'ो': 'o', 'ौ': 'o',
  };

  /// A rough sound "skeleton": first letter, then consonants only.
  static String _skeleton(String word) {
    final latin = StringBuffer();
    for (final ch in word.split('')) {
      latin.write(_indic[ch] ?? ch);
    }
    var w = latin.toString().toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    if (w.isEmpty) {
      return '';
    }
    for (final (a, b) in const [
      ('ph', 'f'), ('sh', 's'), ('ch', 'c'), ('kh', 'k'), ('gh', 'g'), ('th', 't'), ('dh', 'd'),
      ('bh', 'b'), ('ck', 'k'), ('q', 'k'), ('z', 'j'), ('x', 'ks'), ('v', 'b'),
    ]) {
      w = w.replaceAll(a, b);
    }
    final first = w[0];
    final rest = w.substring(1).replaceAll(RegExp(r'[aeiouyhw]'), '');
    final out = StringBuffer(RegExp(r'[aeiou]').hasMatch(first) ? 'a' : first);
    for (final ch in rest.split('')) {
      if (out.toString().endsWith(ch)) {
        continue;
      }
      out.write(ch);
    }
    return out.toString();
  }

  static int _distance(String a, String b) {
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0);
      cur[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        cur[j] = [prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost].reduce((x, y) => x < y ? x : y);
      }
      prev = cur;
    }
    return prev[b.length];
  }

  /// The single best match, or null.
  Future<FoundContact?> find(String spokenName) async {
    final all = await findAll(spokenName);
    return all == null || all.isEmpty ? null : all.first;
  }

  void clearCache() {
    _cache = null;
    _cachedAt = null;
  }

  /// "+91 98765-43210" / "098765 43210" -> "919876543210" for WhatsApp links.
  static String forWhatsApp(String number) {
    var digits = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.startsWith('0')) {
      digits = digits.replaceFirst(RegExp(r'^0+'), '');
    }
    if (digits.length == 10) {
      digits = '91$digits';
    }
    return digits;
  }
}
