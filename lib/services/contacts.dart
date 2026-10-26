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

  Future<FoundContact?> find(String spokenName) async {
    if (!await ensurePermission()) {
      return null;
    }
    try {
      _cache ??= await FlutterContacts.getContacts(withProperties: true);
    } catch (e) {
      debugPrint('Reading contacts failed: $e');
      return null;
    }
    final contacts = _cache!.where((c) => c.phones.isNotEmpty).toList();
    final wanted = _clean(spokenName);
    if (wanted.isEmpty) {
      return null;
    }

    // Family words: match any saved name in the same group.
    final group = _aliases.values.firstWhere(
      (words) => words.contains(wanted),
      orElse: () => const [],
    );
    final candidates = group.isNotEmpty ? group : [wanted];

    Contact? best;
    var bestScore = 0;
    for (final c in contacts) {
      final name = _clean(c.displayName);
      if (name.isEmpty) {
        continue;
      }
      for (final w in candidates) {
        int score = 0;
        if (name == w) {
          score = 100;
        } else if (name.split(' ').contains(w)) {
          score = 80;
        } else if (name.startsWith(w)) {
          score = 60;
        } else if (w.length >= 3 && name.contains(w)) {
          score = 40;
        }
        if (score > bestScore) {
          bestScore = score;
          best = c;
        }
      }
    }
    if (best == null) {
      return null;
    }
    return FoundContact(best.displayName, best.phones.first.number);
  }

  void clearCache() => _cache = null;

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
