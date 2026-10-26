import 'package:flutter/material.dart';

import 'screens/home_screen.dart';
import 'services/reminders.dart';
import 'services/voice.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Settings.instance.load();
  // Never let a failing service stop the app from opening.
  try {
    await Reminders.instance.init().timeout(const Duration(seconds: 8));
  } catch (e) {
    debugPrint('Reminders init failed: $e');
  }
  runApp(const MayaApp());
  // Speech set-up can show a permission prompt, so do it after the first frame.
  Voice.instance.init();
}

class MayaApp extends StatelessWidget {
  const MayaApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF5B3CC4);
    return MaterialApp(
      title: 'Maya',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: Brightness.dark),
        useMaterial3: true,
      ),
      home: const HomeScreen(),
    );
  }
}
