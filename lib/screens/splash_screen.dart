import 'package:flutter/material.dart';
import '../backend.dart';
import '../config.dart';
import '../widgets/common.dart';
import 'menu_screens.dart';
import 'profile_settings.dart';
import 'package:flutter/material.dart';
import '../backend.dart';
import '../config.dart';
import '../common.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    setState(() => _error = null);
    try {
      if (bootError != null) throw Exception(bootError);
      await Future.wait([Backend.init(), Future.delayed(const Duration(milliseconds: 1800))]);
      final profile = await Backend.loadProfile();
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
          builder: (_) => profile == null ? const ProfileScreen(firstRun: true) : const MainMenuScreen()));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBg(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0.3, end: 1),
                  duration: const Duration(milliseconds: 900),
                  curve: Curves.elasticOut,
                  builder: (context, v, child) => Transform.scale(scale: v, child: child),
                  child: const LudoLogo(size: 170),
                ),
                const SizedBox(height: 22),
                const Text("Mahin's Ludo",
                    style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900, color: Colors.white)),
                const SizedBox(height: 6),
                const Text('Play with friends, anywhere',
                    style: TextStyle(fontSize: 16, color: Colors.white70)),
                const SizedBox(height: 36),
                if (_error == null)
                  const CircularProgressIndicator(color: Colors.white)
                else ...[
                  Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.amber)),
                  const SizedBox(height: 16),
                  SizedBox(width: 200, child: BigButton(label: 'Retry', icon: Icons.refresh, onTap: _boot)),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
