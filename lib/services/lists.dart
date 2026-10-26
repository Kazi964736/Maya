import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../settings.dart';

/// Simple named lists ("shopping", "to-do"), kept on the phone.
class Lists extends ChangeNotifier {
  Lists._();
  static final instance = Lists._();

  static const _key = 'lists';

  Map<String, List<String>> get all {
    final raw = Settings.instance.prefs.getString(_key);
    if (raw == null) {
      return {};
    }
    try {
      final m = jsonDecode(raw) as Map<String, dynamic>;
      return {for (final e in m.entries) e.key: List<String>.from(e.value as List)};
    } catch (_) {
      return {};
    }
  }

  Future<void> _save(Map<String, List<String>> lists) async {
    lists.removeWhere((_, v) => v.isEmpty);
    await Settings.instance.prefs.setString(_key, jsonEncode(lists));
    notifyListeners();
  }

  /// "shopping list", "বাজারের ফর্দ", "खरीदारी" → "shopping"; anything else keeps its own name.
  static String nameFor(String? spoken) {
    final s = (spoken ?? '').toLowerCase().trim();
    if (s.isEmpty ||
        RegExp(r'shop|grocer|bazar|bazaar|market|বাজার|ফর্দ|মুদি|बाज़ार|बाजार|खरीद|सामान|राशन').hasMatch(s)) {
      return 'shopping';
    }
    if (RegExp(r'to ?do|task|কাজ|काम').hasMatch(s)) {
      return 'to-do';
    }
    return s.replaceAll(RegExp(r'\s*(list|লিস্ট|লিস্টে|सूची|लिस्ट)\s*$'), '').trim();
  }

  /// Splits "milk, eggs and bread" into three items.
  static List<String> splitItems(String text) => text
      .split(RegExp(r'\s*,\s*|\s+(?:and|আর|এবং|और|तथा)\s+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  Future<List<String>> add(String list, String itemsText) async {
    final items = splitItems(itemsText);
    final lists = all;
    final current = lists[list] ?? [];
    for (final i in items) {
      if (!current.any((c) => c.toLowerCase() == i.toLowerCase())) {
        current.add(i);
      }
    }
    lists[list] = current;
    await _save(lists);
    return items;
  }

  Future<bool> remove(String list, String item) async {
    final lists = all;
    final current = lists[list] ?? [];
    final before = current.length;
    final want = item.toLowerCase().trim();
    current.removeWhere((c) => c.toLowerCase() == want || c.toLowerCase().contains(want));
    lists[list] = current;
    await _save(lists);
    return current.length < before;
  }

  Future<void> clear(String list) async {
    final lists = all..remove(list);
    await _save(lists);
  }

  List<String> items(String list) => all[list] ?? [];
}
