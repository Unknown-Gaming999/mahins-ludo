import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AppSettings {
  static final ValueNotifier<bool> sound = ValueNotifier<bool>(true);
  static final ValueNotifier<bool> vibration = ValueNotifier<bool>(true);

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    sound.value = p.getBool('sound') ?? true;
    vibration.value = p.getBool('vibration') ?? true;
  }

  static Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool('sound', sound.value);
    await p.setBool('vibration', vibration.value);
  }

  static void tap() {
    if (vibration.value) HapticFeedback.lightImpact();
    if (sound.value) SystemSound.play(SystemSoundType.click);
  }
}
