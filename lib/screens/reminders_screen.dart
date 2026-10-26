import 'package:flutter/material.dart';

import '../services/reminders.dart';
import '../ui/theme.dart';

class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});

  String _when(DateTime t) {
    final now = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(t.hour)}:${two(t.minute)}';
    final tomorrow = DateTime(now.year, now.month, now.day).add(const Duration(days: 1));
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return 'Today $time';
    }
    if (t.year == tomorrow.year && t.month == tomorrow.month && t.day == tomorrow.day) {
      return 'Tomorrow $time';
    }
    return '${t.day}/${t.month}/${t.year} $time';
  }

  @override
  Widget build(BuildContext context) {
    final reminders = Reminders.instance;
    return Scaffold(
      appBar: AppBar(title: const Text('Reminders')),
      body: ListenableBuilder(
        listenable: reminders,
        builder: (context, _) {
          final items = reminders.upcoming;
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'No reminders yet.\nSay "Remind me to pay the electricity bill tomorrow at 10".',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final r = items[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  contentPadding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: MayaColors.violet.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.alarm_rounded, color: MayaColors.violet, size: 21),
                  ),
                  title: Text(r.text, style: const TextStyle(color: MayaColors.text, fontWeight: FontWeight.w500)),
                  subtitle: Text(_when(r.when), style: const TextStyle(color: MayaColors.textDim)),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => reminders.remove(r),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
