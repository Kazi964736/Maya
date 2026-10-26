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
