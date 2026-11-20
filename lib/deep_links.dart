import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';
import 'screens/menu_screens.dart';

final GlobalKey<NavigatorState> navKey = GlobalKey<NavigatorState>();

class DeepLinks {
  static String? pending;
  static bool ready = false;
  static VoidCallback? onReturn;
  static final AppLinks _links = AppLinks();

  static Future<void> init() async {
    try {
      final initial = await _links.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {}
    _links.uriLinkStream.listen(_handle, onError: (_) {});
  }

  static String? parse(Uri u) {
    final candidates = <String>[...u.pathSegments, u.host];
    for (final c in candidates) {
      if (RegExp(r'^[A-Za-z0-9]{6}$').hasMatch(c)) return c.toUpperCase();
    }
    return null;
  }

  static void _handle(Uri u) {
    final code = parse(u);
    if (code == null) return;
    if (ready) {
      _open(code);
    } else {
      pending = code;
    }
  }

  static void _open(String code) {
    navKey.currentState
        ?.push(MaterialPageRoute(builder: (_) => JoinRoomScreen(initialCode: code, autoJoin: true)))
        .then((_) => onReturn?.call());
  }

  static void consumePending() {
    ready = true;
    final c = pending;
    pending = null;
    if (c != null) _open(c);
  }
}
