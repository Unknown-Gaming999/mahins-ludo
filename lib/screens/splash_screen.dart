
import 'package:flutter/material.dart';
import '../backend.dart';
import '../config.dart';
import '../common.dart';
import 'menu_screens.dart';
import 'profile_settings.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String _status = 'প্রস্তুত হচ্ছে...';
  bool _started = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _start();
    });
  }

  Future<void> _start() async {
    if (_started) return;
    _started = true;

    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;

    if (bootError != null) {
      setState(() => _status = 'Firebase সংযোগে সমস্যা হয়েছে');
      return;
    }

    try {
      setState(() => _status = 'অ্যাকাউন্ট প্রস্তুত হচ্ছে...');
      await Backend.init();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => const MenuScreen(),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'সংযোগ করা যায়নি: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const LudoLogo(),
                const SizedBox(height: 28),
                const Text(
                  'MAHINS LUDO',
                  style: TextStyle(
                    fontSize: 30,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2,
                  ),
                ),
                const SizedBox(height: 20),
                const CircularProgressIndicator(
                  color: Colors.white,
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Text(
                    _status,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                    ),
                  ),
                ),
                if (bootError != null) ...[
                  const SizedBox(height: 18),
                  BigButton(
                    text: 'আবার চেষ্টা করুন',
                    onPressed: () {
                      _started = false;
                      setState(() => _status = 'আবার চেষ্টা হচ্ছে...');
                      _start();
                    },
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
