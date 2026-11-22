
import 'package:flutter/material.dart';
import '../backend.dart';
import '../settings.dart';
import '../models.dart';
import '../common.dart';
import 'menu_screens.dart';
import 'splash_screen.dart';

class ProfileSettingsScreen extends StatefulWidget {
  const ProfileSettingsScreen({super.key});

  @override
  State<ProfileSettingsScreen> createState() =>
      _ProfileSettingsScreenState();
}

class _ProfileSettingsScreenState
    extends State<ProfileSettingsScreen> {
  final TextEditingController _nameController =
      TextEditingController();

  bool _saving = false;
  bool _soundEnabled = true;
  bool _vibrationEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      _soundEnabled = AppSettings.soundEnabled;
      _vibrationEnabled = AppSettings.vibrationEnabled;

      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _saveSettings() async {
    if (_saving) return;

    setState(() => _saving = true);

    try {
      await AppSettings.setSoundEnabled(_soundEnabled);
      await AppSettings.setVibrationEnabled(_vibrationEnabled);

      if (mounted) {
        showMsg(context, 'Settings saved');
      }
    } catch (e) {
      if (mounted) {
        showMsg(context, 'Save failed: $e');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Widget _settingTile({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return Card(
      color: Colors.white.withValues(alpha: 0.12),
      child: SwitchListTile(
        secondary: Icon(icon, color: Colors.white),
        title: Text(
          title,
          style: const TextStyle(color: Colors.white),
        ),
        subtitle: Text(
          subtitle,
          style: const TextStyle(color: Colors.white70),
        ),
        value: value,
        activeColor: Colors.greenAccent,
        onChanged: onChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile & Settings'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: GradientBg(
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 12),
              const Center(child: LudoLogo()),
              const SizedBox(height: 20),
              const Text(
                'PROFILE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                color: Colors.white.withValues(alpha: 0.12),
                child: ListTile(
                  leading: const CircleAvatar(
                    child: Icon(Icons.person),
                  ),
                  title: const Text(
                    'Player Profile',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: const Text(
                    'Your game account',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'SETTINGS',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _settingTile(
                title: 'Sound',
                subtitle: 'Game sound effects',
                value: _soundEnabled,
                icon: Icons.volume_up,
                onChanged: (value) {
                  setState(() => _soundEnabled = value);
                },
              ),
              _settingTile(
                title: 'Vibration',
                subtitle: 'Vibrate during game actions',
                value: _vibrationEnabled,
                icon: Icons.vibration,
                onChanged: (value) {
                  setState(() => _vibrationEnabled = value);
                },
              ),
              const SizedBox(height: 18),
              BigButton(
                text: _saving ? 'SAVING...' : 'SAVE SETTINGS',
                onPressed: _saving ? null : _saveSettings,
              ),
              const SizedBox(height: 18),
              BigButton(
                text: 'BACK TO MENU',
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 18),
              const Center(
                child: Text(
                  'MAHINS LUDO',
                  style: TextStyle(
                    color: Colors.white54,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
