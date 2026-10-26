import 'package:flutter/material.dart';

import '../services/memory.dart';
import '../ui/theme.dart';

/// Everything the user asked Maya to remember, with delete.
class MemoriesScreen extends StatelessWidget {
  const MemoriesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final memory = Memory.instance;
    return Scaffold(
      appBar: AppBar(title: const Text("Maya's memory")),
      body: ListenableBuilder(
        listenable: memory,
        builder: (context, _) {
          final items = memory.items.reversed.toList();
          if (items.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text(
                  'Nothing saved yet.\n\nSay "Remember that my bike is parked on level B2" or '
                  '"মনে রেখো গাড়ির চাবি আলমারিতে". Later ask "Where is my bike?"',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: MayaColors.textDim, height: 1.5),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            itemCount: items.length,
            itemBuilder: (_, i) {
              final m = items[i];
              return Card(
                margin: const EdgeInsets.only(bottom: 10),
                child: ListTile(
                  leading: const Icon(Icons.bookmark_rounded, color: MayaColors.violet),
                  title: Text(m.text, style: const TextStyle(color: MayaColors.text)),
                  subtitle: Text('${m.at.day}/${m.at.month}/${m.at.year}', style: const TextStyle(color: MayaColors.textDim)),
                  trailing: IconButton(
                    tooltip: 'Forget',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: () => memory.remove(m),
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
