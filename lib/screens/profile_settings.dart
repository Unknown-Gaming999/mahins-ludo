import 'package:flutter/material.dart';
import '../backend.dart';
import '../settings.dart';
import '../widgets/common.dart';
import 'menu_screens.dart';
import 'splash_screen.dart';
import 'package:flutter/material.dart';
import '../backend.dart';
import '../models.dart';
import '../common.dart';
class ProfileScreen extends StatefulWidget {
  final bool firstRun;
  const ProfileScreen({super.key, this.firstRun = false});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final TextEditingController _name = TextEditingController();
  int _avatar = 0;
  int _games = 0, _wins = 0;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await Backend.loadProfile();
      final s = await Backend.loadStats();
      if (!mounted) return;
      setState(() {
        if (p != null) {
          _name.text = p.name;
          _avatar = p.avatar;
        }
        _games = s['gamesPlayed'] ?? 0;
        _wins = s['wins'] ?? 0;
      });
    } catch (_) {}
  }

  Future<void> _save() async {
    final n = _name.text.trim();
    if (n.length < 2 || n.length > 16) {
      showMsg(context, 'Name must be 2 to 16 characters.');
      return;
    }
    setState(() => _busy = true);
    try {
      await Backend.saveProfile(Profile(n, _avatar));
      if (!mounted) return;
      if (widget.firstRun) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => const MainMenuScreen()));
      } else {
        showMsg(context, 'Profile saved');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) showMsg(context, 'Could not save profile. Check your internet.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(widget.firstRun ? 'Welcome!' : 'Player Profile'),
        backgroundColor: Colors.transparent,
        automaticallyImplyLeading: !widget.firstRun,
      ),
      body: GradientBg(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  children: [
                    const SizedBox(height: 40),
                    AvatarBubble(index: _avatar, size: 96),
                    const SizedBox(height: 6),
                    const Text('Playing as a guest', style: TextStyle(color: Colors.white70)),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _name,
                      maxLength: 16,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
                      decoration: InputDecoration(
                        hintText: 'Your name',
                        filled: true,
                        fillColor: Colors.white12,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        for (var i = 0; i < kAvatars.length; i++)
                          GestureDetector(
                            onTap: () => setState(() => _avatar = i),
                            child: AvatarBubble(
                                index: i, size: 52, ring: i == _avatar ? const Color(0xFFFFC107) : Colors.white24),
                          ),
                      ],
                    ),
                    if (!widget.firstRun) ...[
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _stat('Games', _games),
                          _stat('Wins', _wins),
                        ],
                      ),
                    ],
                    const SizedBox(height: 24),
                    BigButton(
                        label: widget.firstRun ? 'Continue' : 'Save',
                        icon: Icons.check,
                        busy: _busy,
                        onTap: _save),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _stat(String label, int v) => Column(children: [
        Text('$v', style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ]);
}

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});
  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  Future<void> _resetGuest() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('New guest account?'),
        content: const Text('You will get a brand-new guest identity. Your name, avatar and stats on this account will be lost.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Continue')),
        ],
      ),
    );
    if (ok != true) return;
    await Backend.resetGuest();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
        MaterialPageRoute(builder: (_) => const SplashScreen()), (r) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(title: const Text('Settings'), backgroundColor: Colors.transparent),
      body: GradientBg(
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 60, 16, 16),
                children: [
                  ValueListenableBuilder<bool>(
                    valueListenable: AppSettings.sound,
                    builder: (context, v, _) => SwitchListTile(
                      title: const Text('Sound effects'),
                      secondary: const Icon(Icons.volume_up),
                      value: v,
                      onChanged: (x) {
                        AppSettings.sound.value = x;
                        AppSettings.save();
                      },
                    ),
                  ),
                  ValueListenableBuilder<bool>(
                    valueListenable: AppSettings.vibration,
                    builder: (context, v, _) => SwitchListTile(
                      title: const Text('Vibration'),
                      secondary: const Icon(Icons.vibration),
                      value: v,
                      onChanged: (x) {
                        AppSettings.vibration.value = x;
                        AppSettings.save();
                      },
                    ),
                  ),
                  const Divider(),
                  ListTile(
                    leading: const Icon(Icons.person_off),
                    title: const Text('Switch to a new guest account'),
                    onTap: _resetGuest,
                  ),
                  const ListTile(
                    leading: Icon(Icons.info_outline),
                    title: Text("Mahin's Ludo"),
                    subtitle: Text('Version 1.0.0'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
