import 'package:flutter/material.dart';

import '../services/reminders.dart';

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
          return ListView.separated(
            itemCount: items.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final r = items[i];
              return ListTile(
                leading: const Icon(Icons.alarm),
                title: Text(r.text),
                subtitle: Text(_when(r.when)),
                trailing: IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => reminders.remove(r),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
