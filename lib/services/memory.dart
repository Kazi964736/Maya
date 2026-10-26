import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../settings.dart';

class MemoryItem {
  MemoryItem({required this.text, required this.at});
  final String text;
  final DateTime at;

  Map<String, dynamic> toJson() => {'t': text, 'at': at.toIso8601String()};

  static MemoryItem? fromJson(dynamic j) {
    if (j is! Map || j['t'] is! String) {
      return null;
    }
    return MemoryItem(text: j['t'] as String, at: DateTime.tryParse('${j['at']}') ?? DateTime.now());
  }
}

/// Things the user asked Maya to remember. Stored only on this phone.
class Memory extends ChangeNotifier {
  Memory._();
  static final instance = Memory._();

  static const _key = 'memories';
  static const _max = 200;

  List<MemoryItem> get items {
    final raw = Settings.instance.prefs.getString(_key);
    if (raw == null) {
      return [];
    }
    try {
      return (jsonDecode(raw) as List).map(MemoryItem.fromJson).whereType<MemoryItem>().toList();
    } catch (_) {
      return [];
    }
  }

  Future<void> _save(List<MemoryItem> list) async {
    final keep = list.length > _max ? list.sublist(list.length - _max) : list;
    await Settings.instance.prefs.setString(_key, jsonEncode(keep.map((m) => m.toJson()).toList()));
    notifyListeners();
  }

  Future<void> add(String text) async {
    final t = text.trim();
    if (t.isEmpty) {
      return;
    }
    final list = items..removeWhere((m) => m.text.toLowerCase() == t.toLowerCase());
    list.add(MemoryItem(text: t, at: DateTime.now()));
    await _save(list);
  }

  Future<void> remove(MemoryItem item) async {
    final list = items..removeWhere((m) => m.text == item.text && m.at == item.at);
    await _save(list);
  }

  /// Forgets memories that mention [query]. Returns how many were removed.
  Future<int> forget(String query) async {
    final words = _words(query);
    if (words.isEmpty) {
      return 0;
    }
    final list = items;
    final before = list.length;
    list.removeWhere((m) {
      final have = _words(m.text);
      return words.every(have.contains);
    });
    await _save(list);
    return before - list.length;
  }

  /// Memories that share words with [question], best first (for offline answers).
  List<MemoryItem> search(String question) {
    final words = _words(question).where((w) => w.length > 2 && !_stop.contains(w)).toSet();
    if (words.isEmpty) {
      return [];
    }
    final scored = <(int, MemoryItem)>[];
    for (final m in items) {
      final have = _words(m.text).toSet();
      final score = words.where(have.contains).length;
      if (score > 0) {
        scored.add((score, m));
      }
    }
    scored.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final s in scored) s.$2];
  }

  /// For the AI: what the user has asked Maya to remember.
  String promptBlock() {
    final list = items;
    if (list.isEmpty) {
      return '';
    }
    final recent = list.length > 60 ? list.sublist(list.length - 60) : list;
    final lines = recent.map((m) => '- ${m.text} (saved ${m.at.day}/${m.at.month}/${m.at.year})').join('\n');
    return '\nThings the user asked you to remember (use them when relevant; they are facts from the user):\n$lines\n';
  }

  static List<String> _words(String s) => s
      .toLowerCase()
      .replaceAll(RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true), ' ')
      .split(RegExp(r'\s+'))
      .where((w) => w.isNotEmpty)
      .toList();

  static const _stop = {
    'the', 'what', 'where', 'when', 'which', 'who', 'did', 'does', 'is', 'are', 'was', 'my', 'me', 'you', 'your',
    'tell', 'about', 'remember', 'কি', 'কী', 'কোথায়', 'কবে', 'আমার', 'বলো', 'क्या', 'कहाँ', 'कब', 'मेरा', 'मेरी', 'बताओ',
  };
}
