import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'backend.dart';
import 'config.dart';
import 'deep_links.dart';
import 'screens/splash_screen.dart';
import 'settings.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (e) {
    bootError = 'Firebase is not configured correctly: $e';
  }
  await AppSettings.load();
  DeepLinks.init();
  runApp(const LudoApp());
}

class LudoApp extends StatefulWidget {
  const LudoApp({super.key});
  @override
  State<LudoApp> createState() => _LudoAppState();
}

class _LudoAppState extends State<LudoApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && bootError == null) {
      try {
        Backend.db.goOnline();
      } catch (_) {}
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: "Mahin's Ludo",
      debugShowCheckedModeBanner: false,
      navigatorKey: navKey,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        colorSchemeSeed: const Color(0xFF7C4DFF),
      ),
      home: const SplashScreen(),
    );
  }
}
