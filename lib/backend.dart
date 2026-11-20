import 'dart:async';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'config.dart';
import 'models.dart';

class BackendException implements Exception {
  final String message;
  BackendException(this.message);
  @override
  String toString() => message;
}

class Profile {
  final String name;
  final int avatar;
  Profile(this.name, this.avatar);
}

class Backend {
  static FirebaseAuth get auth => FirebaseAuth.instance;
  static FirebaseDatabase get db => kDatabaseUrl.isEmpty
      ? FirebaseDatabase.instance
      : FirebaseDatabase.instanceFor(app: Firebase.app(), databaseURL: kDatabaseUrl);
  static FirebaseFunctions get fn => FirebaseFunctions.instanceFor(region: kFunctionsRegion);
  static String get uid => auth.currentUser!.uid;

  static int _offset = 0;
  static StreamSubscription? _offsetSub;
  static int now() => DateTime.now().millisecondsSinceEpoch + _offset;

  static Future<void> init() async {
    if (auth.currentUser == null) await auth.signInAnonymously();
    _offsetSub ??= db.ref('.info/serverTimeOffset').onValue.listen((e) {
      final v = e.snapshot.value;
      if (v is num) _offset = v.toInt();
    });
  }

  static Future<Profile?> loadProfile() async {
    final s = await db.ref('users/$uid').get();
    if (!s.exists) return null;
    final m = asMap(s.value);
    final n = m['name'];
    if (n is! String || n.isEmpty) return null;
    return Profile(n, toInt(m['avatar'], 0));
  }

  static Future<void> saveProfile(Profile p) =>
      db.ref('users/$uid').set({'name': p.name, 'avatar': p.avatar});

  static Future<Map<String, int>> loadStats() async {
    final s = await db.ref('stats/$uid').get();
    final m = asMap(s.value);
    return {'gamesPlayed': toInt(m['gamesPlayed'], 0), 'wins': toInt(m['wins'], 0)};
  }

  static Future<void> resetGuest() async {
    detachPresence();
    await forgetRoom();
    await auth.signOut();
  }

  static Future<Map<String, dynamic>> _call(String name, Map<String, dynamic> data) async {
    try {
      final r = await fn.httpsCallable(name).call(data);
      return asMap(r.data);
    } on FirebaseFunctionsException catch (e) {
      throw BackendException(e.message ?? 'Server error (${e.code})');
    } catch (_) {
      throw BackendException('Connection problem. Check your internet and try again.');
    }
  }

  static Future<Map<String, dynamic>> _remember(Future<Map<String, dynamic>> f) async {
    final r = await f;
    final code = r['code'];
    if (code is String) {
      final p = await SharedPreferences.getInstance();
      await p.setString('lastRoom', code);
    }
    return r;
  }

  static Future<Map<String, dynamic>> createRoom(int maxPlayers) =>
      _remember(_call('createRoom', {'maxPlayers': maxPlayers}));
  static Future<Map<String, dynamic>> joinRoom(String code) =>
      _remember(_call('joinRoom', {'code': code}));
  static Future<Map<String, dynamic>> quickMatch() => _remember(_call('quickMatch', {}));
  static Future<void> startGame(String code) => _call('startGame', {'code': code});
  static Future<void> rollDice(String code) => _call('rollDice', {'code': code});
  static Future<void> moveToken(String code, int token) =>
      _call('moveToken', {'code': code, 'token': token});
  static Future<void> skipTurn(String code) => _call('skipTurn', {'code': code});

  static Future<void> leaveRoom(String code) async {
    try {
      await _call('leaveRoom', {'code': code});
    } finally {
      await forgetRoom();
    }
  }

  static Stream<Room?> watchRoom(String code) => db
      .ref('rooms/$code')
      .onValue
      .map((e) => e.snapshot.exists ? Room.parse(code, e.snapshot.value) : null);

  static Future<void> forgetRoom() async {
    detachPresence();
    final p = await SharedPreferences.getInstance();
    await p.remove('lastRoom');
  }

  static Future<String?> activeRoom() async {
    final p = await SharedPreferences.getInstance();
    final code = p.getString('lastRoom');
    if (code == null) return null;
    try {
      final s = await db.ref('rooms/$code').get();
      if (!s.exists) {
        await p.remove('lastRoom');
        return null;
      }
      final room = Room.parse(code, s.value);
      final me = room.players[uid];
      if (me == null || me.left || room.status == 'finished') {
        await p.remove('lastRoom');
        return null;
      }
      return code;
    } catch (_) {
      return null;
    }
  }

  static StreamSubscription? _presenceSub;
  static String? _presenceCode;

  static void attachPresence(String code) {
    if (_presenceCode == code) return;
    detachPresence();
    _presenceCode = code;
    final me = db.ref('rooms/$code/players/$uid');
    _presenceSub = db.ref('.info/connected').onValue.listen((e) async {
      if (e.snapshot.value == true) {
        try {
          await me.child('connected').onDisconnect().set(false);
          await me.child('lastSeen').onDisconnect().set(ServerValue.timestamp);
          await me.child('connected').set(true);
          await me.child('lastSeen').set(ServerValue.timestamp);
        } catch (_) {}
      }
    });
  }

  static void detachPresence() {
    _presenceSub?.cancel();
    _presenceSub = null;
    _presenceCode = null;
  }
}
