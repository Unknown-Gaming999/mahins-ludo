
import 'dart:async';
import 'dart:math';

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
      : FirebaseDatabase.instanceFor(
          app: Firebase.app(),
          databaseURL: kDatabaseUrl,
        );

  static String get uid {
    final user = auth.currentUser;
    if (user == null) {
      throw BackendException('Please sign in first.');
    }
    return user.uid;
  }

  static int _offset = 0;
  static StreamSubscription? _offsetSub;

  static int now() =>
      DateTime.now().millisecondsSinceEpoch + _offset;

  static Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) return {};
    return value.map((k, v) => MapEntry(
          k.toString(),
          v is Map
              ? _map(v)
              : v is List
                  ? v.map((e) => e is Map ? _map(e) : e).toList()
                  : v,
        ));
  }

  static Future<void> init() async {
    if (auth.currentUser == null) {
      await auth.signInAnonymously();
    }

    _offsetSub ??= db.ref('.info/serverTimeOffset').onValue.listen((e) {
      final v = e.snapshot.value;
      if (v is num) _offset = v.toInt();
    });
  }

  static Future<Profile?> loadProfile() async {
    final s = await db.ref('users/$uid').get();
    if (!s.exists) return null;

    final m = _map(s.value);
    final name = m['name'];

    if (name is! String || name.isEmpty) return null;

    return Profile(name, toInt(m['avatar'], 0));
  }

  static Future<void> saveProfile(Profile p) async {
    final name = p.name.trim();

    if (name.isEmpty || name.length > 16) {
      throw BackendException('Name must be 1-16 characters.');
    }

    await db.ref('users/$uid').set({
      'name': name,
      'avatar': p.avatar,
    });
  }

  static Future<Map<String, int>> loadStats() async {
    final s = await db.ref('stats/$uid').get();
    final m = _map(s.value);

    return {
      'gamesPlayed': toInt(m['gamesPlayed'], 0),
      'wins': toInt(m['wins'], 0),
    };
  }

  static Future<void> resetGuest() async {
    await forgetRoom();
    await auth.signOut();
  }

  static Future<Profile> _getProfile() async {
    final p = await loadProfile();
    return p ?? Profile('Player', 0);
  }

  static String _newCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random.secure();

    return List.generate(
      6,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
  }

  static String _cleanCode(String value) {
    final code = value.trim().toUpperCase();

    if (!RegExp(r'^[A-Z0-9]{6}$').hasMatch(code)) {
      throw BackendException('Invalid room code.');
    }

    return code;
  }

  static Map<String, dynamic> _player(Profile p, int time) {
    return {
      'name': p.name,
      'avatar': p.avatar,
      'joinedAt': time,
      'connected': true,
      'lastSeen': time,
    };
  }

  static Future<dynamic> _transaction(
    String code,
    dynamic Function(Map<String, dynamic>, int) action,
  ) async {
    BackendException? failure;
    dynamic output;

    final ref = db.ref('rooms/$code');

    final result = await ref.runTransaction((current) {
      failure = null;
      output = null;

      if (current == null) {
        failure = BackendException('Room not found.');
        return Transaction.abort();
      }

      final room = _map(current);

      try {
        output = action(room, now());
        return Transaction.success(room);
      } catch (e) {
        failure = e is BackendException
            ? e
            : BackendException(e.toString());
        return Transaction.abort();
      }
    }, applyLocally: false);

    if (failure != null) {
      throw failure!;
    }

    if (!result.committed) {
      throw BackendException('Could not update room. Try again.');
    }

    return output;
  }

  static Future<void> _remember(Future<dynamic> future) async {
    final result = await future;
    if (result is Map && result['code'] is String) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastRoom', result['code']);
    }
  }

  static Future<Map<String, dynamic>> createRoom(
      int maxPlayers) async {
    final p = await _getProfile();
    final maximum = maxPlayers.clamp(2, 4);

    for (var i = 0; i < 10; i++) {
      final code = _newCode();
      final time = now();

      final room = {
        'code': code,
        'host': uid,
        'status': 'lobby',
        'createdAt': time,
        'maxPlayers': maximum,
        'players': {
          uid: _player(p, time),
        },
      };

      final ref = db.ref('rooms/$code');

      final result = await ref.runTransaction((current) {
        if (current != null) return Transaction.abort();
        return Transaction.success(room);
      }, applyLocally: false);

      if (result.committed) {
        final answer = {'code': code, 'status': 'lobby'};
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('lastRoom', code);
        return answer;
      }
    }

    throw BackendException('Could not create room.');
  }

  static Future<Map<String, dynamic>> joinRoom(String value) async {
    final code = _cleanCode(value);
    final p = await _getProfile();

    final result = await _transaction(code, (room, time) {
      final players = _map(room['players']);
      final existing = players[uid];

      if (existing != null) {
        if (existing['left'] == true) {
          throw BackendException('You already left this game.');
        }
        return {'code': code, 'status': room['status']};
      }

      if (room['status'] != 'lobby') {
        throw BackendException('Game already started.');
      }

      final max = toInt(room['maxPlayers'], 4);

      if (players.length >= max) {
        throw BackendException('Room is full.');
      }

      players[uid] = _player(p, time);
      room['players'] = players;

      return {'code': code, 'status': room['status']};
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastRoom', code);

    return Map<String, dynamic>.from(result);
  }

  static Future<Map<String, dynamic>> quickMatch() async {
    final p = await _getProfile();

    final snap = await db
        .ref('rooms')
        .orderByChild('isPublic')
        .equalTo(true)
        .limitToLast(40)
        .get();

    final candidates = <String>[];

    if (snap.value is Map) {
      _map(snap.value).forEach((code, room) {
        if (room is Map &&
            room['status'] == 'lobby' &&
            now() - toInt(room['createdAt'], 0) < 900000) {
          final players = _map(room['players']);
          if (players.containsKey(uid) ||
              players.length < toInt(room['maxPlayers'], 4)) {
            candidates.add(code);
          }
        }
      });
    }

    for (final code in candidates) {
      try {
        final result = await _transaction(code, (room, time) {
          final players = _map(room['players']);

          if (players.containsKey(uid)) {
            return {'code': code, 'status': room['status']};
          }

          if (room['status'] != 'lobby' ||
              players.length >= toInt(room['maxPlayers'], 4)) {
            throw BackendException('Room unavailable.');
          }

          players[uid] = _player(p, time);
          room['players'] = players;

          if (players.length >= toInt(room['maxPlayers'], 4)) {
            _beginGame(room, time);
          }

          return {'code': code, 'status': room['status']};
        });

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('lastRoom', code);

        return Map<String, dynamic>.from(result);
      } catch (_) {}
    }

    final code = _newCode();
    final time = now();

    final room = {
      'code': code,
      'host': uid,
      'status': 'lobby',
      'createdAt': time,
      'maxPlayers': 4,
      'isPublic': true,
      'players': {
        uid: _player(p, time),
      },
    };

    await db.ref('rooms/$code').set(room);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('lastRoom', code);

    return {'code': code, 'status': 'lobby'};
  }

  static const List<int> _start = [0, 13, 26, 39];
  static const Set<int> _safe = {
    0, 8, 13, 21, 26, 34, 39, 47
  };

  static const int _finish = 56;
  static const int _turnMs = 45000;

  static int _absIndex(int color, int position) =>
      (_start[color] + position) % 52;

  static void _beginGame(Map<String, dynamic> room, int time) {
    final players = _map(room['players']);

    final entries = players.entries.toList()
      ..sort((a, b) =>
          toInt(a.value['joinedAt'], 0)
              .compareTo(toInt(b.value['joinedAt'], 0)));

    final n = entries.length;

    if (n < 2 || n > 4) {
      throw BackendException('Invalid player count.');
    }

    final seats = n == 2
        ? [0, 2]
        : n == 3
            ? [0, 1, 2]
            : [0, 1, 2, 3];

    final tokens = <String, dynamic>{};

    for (var i = 0; i < entries.length; i++) {
      final player = _map(entries[i].value);
      player['color'] = seats[i];
      player['missed'] = 0;
      players[entries[i].key] = player;
      tokens['c${seats[i]}'] = [-1, -1, -1, -1];
    }

    room['players'] = players;
    room['status'] = 'playing';
    room['startedAt'] = time;
    room.remove('isPublic');

    room['game'] = {
      'order': seats,
      'tokens': tokens,
      'turn': seats[0],
      'phase': 'roll',
      'dice': 0,
      'diceSeq': 0,
      'seq': 0,
      'sixes': 0,
      'turnDeadline': time + _turnMs,
    };
  }

  static Map<String, dynamic> _game(Map<String, dynamic> room) {
    if (room['status'] != 'playing' || room['game'] is! Map) {
      throw BackendException('Game is not running.');
    }
    return _map(room['game']);
  }

  static int _uidColor(Map<String, dynamic> room, String user) {
    final player = _map(_map(room['players'])[user]);
    return toInt(player['color'], -1);
  }

  static List<int> _activeColors(Map<String, dynamic> room) {
    final game = _map(room['game']);
    final order = (game['order'] as List? ?? [])
        .map((e) => (e as num).toInt())
        .toList();
    final players = _map(room['players']);

    return order.where((color) {
      for (final p in players.values) {
        if (p is Map &&
            p['color'] == color &&
            p['left'] != true) {
          return true;
        }
      }
      return false;
    }).toList();
  }

  static void _passTurn(Map<String, dynamic> room, int time) {
    final game = _map(room['game']);
    final order = (game['order'] as List)
        .map((e) => (e as num).toInt())
        .toList();
    final active = _activeColors(room);

    if (active.isEmpty) return;

    final index = order.indexOf(toInt(game['turn'], 0));

    for (var k = 1; k <= order.length; k++) {
      final color = order[(index + k) % order.length];
      if (active.contains(color)) {
        game['turn'] = color;
        break;
      }
    }

    game['phase'] = 'roll';
    game.remove('movable');
    game['sixes'] = 0;
    game['turnDeadline'] = time + _turnMs;
    game['seq'] = toInt(game['seq'], 0) + 1;

    room['game'] = game;
  }

  static void _finishGame(
      Map<String, dynamic> room, int? winner, int time) {
    final game = _map(room['game']);

    room['status'] = 'finished';
    room['finishedAt'] = time;

    game['phase'] = 'over';
    game.remove('movable');

    if (winner != null) game['winner'] = winner;

    game['seq'] = toInt(game['seq'], 0) + 1;
    room['game'] = game;
  }

  static Future<void> _addStat(String user, String field) async {
    final ref = db.ref('stats/$user/$field');

    await ref.runTransaction((current) {
      final value = current is num ? current.toInt() : 0;
      return Transaction.success(value + 1);
    });
  }

  static Future<void> _recordFinished(
      Map<String, dynamic> room) async {
    final players = _map(room['players']);
    final game = _map(room['game']);

    for (final entry in players.entries) {
      if (entry.value is Map &&
          entry.value['color'] != null) {
        await _addStat(entry.key, 'gamesPlayed');
      }
    }

    final winnerColor = game['winner'];

    if (winnerColor is num) {
      for (final entry in players.entries) {
        if (entry.value is Map &&
            entry.value['color'] == winnerColor.toInt()) {
          await _addStat(entry.key, 'wins');
          break;
        }
      }
    }
  }

  static Future<void> startGame(String value) async {
    final code = _cleanCode(value);

    await _transaction(code, (room, time) {
      if (room['host'] != uid) {
        throw BackendException('Only host can start.');
      }

      if (room['status'] != 'lobby') {
        throw BackendException('Game already started.');
      }

      if (_map(room['players']).length < 2) {
        throw BackendException('At least 2 players are needed.');
      }

      _beginGame(room, time);
      return {'ok': true};
    });
  }

  static Future<void> rollDice(String value) async {
    final code = _cleanCode(value);

    await _transaction(code, (room, time) {
      final game = _game(room);
      final players = _map(room['players']);
      final me = _map(players[uid]);

      if (me.isEmpty ||
          me['left'] == true ||
          game['turn'] != me['color']) {
        throw BackendException('It is not your turn.');
      }

      if (game['phase'] != 'roll') {
        throw BackendException('Move a token first.');
      }

      final dice = Random.secure().nextInt(6) + 1;

      me['missed'] = 0;
      players[uid] = me;
      room['players'] = players;

      game['dice'] = dice;
      game['diceSeq'] = toInt(game['diceSeq'], 0) + 1;
      game['rolledBy'] = me['color'];
      game['seq'] = toInt(game['seq'], 0) + 1;
      game.remove('event');

      final sixes = dice == 6
          ? toInt(game['sixes'], 0) + 1
          : 0;

      game['sixes'] = sixes;
      room['game'] = game;

      if (sixes >= 3) {
        game['event'] = '${me['name']} rolled three sixes. Turn lost!';
        _passTurn(room, time);
        return {'dice': dice};
      }

      final tokens = _map(game['tokens']);
      final positions = (tokens['c${me['color']}'] as List)
          .map((e) => (e as num).toInt())
          .toList();

      final movable = <int>[];

      for (var i = 0; i < positions.length; i++) {
        final pos = positions[i];
        if (pos == -1 && dice == 6) {
          movable.add(i);
        } else if (pos >= 0 &&
            pos < _finish &&
            pos + dice <= _finish) {
          movable.add(i);
        }
      }

      if (movable.isEmpty) {
        game['event'] = '${me['name']} rolled $dice. No move possible.';
        _passTurn(room, time);
      } else {
        game['phase'] = 'move';
        game['movable'] = movable;
        game['turnDeadline'] = time + _turnMs;
      }

      room['game'] = game;
      return {'dice': dice};
    });
  }

  static Future<void> moveToken(String value, int token) async {
    final code = _cleanCode(value);
    Map<String, dynamic>? finishedRoom;

    await _transaction(code, (room, time) {
      final game = _game(room);
      final players = _map(room['players']);
      final me = _map(players[uid]);

      if (me.isEmpty ||
          me['left'] == true ||
          game['turn'] != me['color']) {
        throw BackendException('It is not your turn.');
      }

      final movable = (game['movable'] as List? ?? [])
          .map((e) => (e as num).toInt())
          .toList();

      if (game['phase'] != 'move' ||
          !movable.contains(token) ||
          token < 0 ||
          token > 3) {
        throw BackendException('Token cannot move.');
      }

      final tokens = _map(game['tokens']);
      final key = 'c${me['color']}';

      final positions = (tokens[key] as List)
          .map((e) => (e as num).toInt())
          .toList();

      final from = positions[token];
      final dice = toInt(game['dice'], 0);
      final to = from == -1 ? 0 : from + dice;

      positions[token] = to;
      tokens[key] = positions;

      var captured = 0;

      if (to <= 50) {
        final absolute = _absIndex(toInt(me['color'], 0), to);

        if (!_safe.contains(absolute)) {
          final order = (game['order'] as List)
              .map((e) => (e as num).toInt())
              .toList();

          for (final color in order) {
            if (color == me['color']) continue;

            final otherKey = 'c$color';
            final other = (tokens[otherKey] as List)
                .map((e) => (e as num).toInt())
                .toList();

            for (var i = 0; i < other.length; i++) {
              if (other[i] >= 0 &&
                  other[i] <= 50 &&
                  _absIndex(color, other[i]) == absolute) {
                other[i] = -1;
                captured++;
              }
            }

            tokens[otherKey] = other;
          }
        }
      }

      game['tokens'] = tokens;
      game['lastMove'] = {
        'color': me['color'],
        'token': token,
        'from': from,
        'to': to,
        'captured': captured,
      };

      game['seq'] = toInt(game['seq'], 0) + 1;
      me['missed'] = 0;
      players[uid] = me;
      room['players'] = players;

      if (positions.every((p) => p == _finish)) {
        _finishGame(room, toInt(me['color'], 0), time);
        finishedRoom = room;
        return {'ok': true};
      }

      if (dice == 6 || captured > 0 || to == _finish) {
        game['phase'] = 'roll';
        game.remove('movable');
        game['turnDeadline'] = time + _turnMs;

        if (captured > 0) {
          game['event'] = '${me['name']} captured $captured token(s)!';
        } else if (to == _finish) {
          game['event'] = '${me['name']} got a token home!';
        } else {
          game['event'] = '${me['name']} rolled a 6!';
        }
      } else {
        game.remove('event');
        _passTurn(room, time);
      }

      room['game'] = game;
      return {'ok': true};
    });

    if (finishedRoom != null) {
      await _recordFinished(finishedRoom!);
    }
  }

  static Future<void> skipTurn(String value) async {
    final code = _cleanCode(value);
    Map<String, dynamic>? finishedRoom;

    await _transaction(code, (room, time) {
      final game = _game(room);

      if (!_map(room['players']).containsKey(uid)) {
        throw BackendException('You are not in this room.');
      }

      final turn = toInt(game['turn'], 0);
      final players = _map(room['players']);

      String? currentUid;

      for (final entry in players.entries) {
        if (entry.value is Map &&
            entry.value['color'] == turn &&
            entry.value['left'] != true) {
          currentUid = entry.key;
          break;
        }
      }

      if (currentUid == null) {
        throw BackendException('Nothing to skip.');
      }

      final current = _map(players[currentUid]);
      final expired = time > toInt(game['turnDeadline'], 0);

      final dropped = current['connected'] == false &&
          toInt(current['lastSeen'], 0) > 0 &&
          time - toInt(current['lastSeen'], 0) > 10000;

      if (!expired && !dropped) {
        throw BackendException('The turn is still active.');
      }

      if (expired && !dropped) {
        current['missed'] = toInt(current['missed'], 0) + 1;

        if (toInt(current['missed'], 0) >= 3) {
          current['left'] = true;
        }
      }

      players[currentUid] = current;
      room['players'] = players;

      game['event'] = '${current['name']} missed a turn.';

      final active = _activeColors(room);

      if (active.length < 2) {
        _finishGame(room, active.isEmpty ? null : active.first, time);
        finishedRoom = room;
      } else {
        _passTurn(room, time);
      }

      room['game'] = game;
      return {'ok': true};
    });

    if (finishedRoom != null) {
      await _recordFinished(finishedRoom!);
    }
  }

  static Future<void> leaveRoom(String value) async {
    final code = _cleanCode(value);
    Map<String, dynamic>? finishedRoom;

    try {
      await _transaction(code, (room, time) {
        final players = _map(room['players']);
        final me = _map(players[uid]);

        if (me.isEmpty) return {'ok': true};

        if (room['status'] == 'lobby') {
          players.remove(uid);

          if (players.isEmpty) {
            room.clear();
            return {'ok': true};
          }

          if (room['host'] == uid) {
            final entries = players.entries.toList()
              ..sort((a, b) =>
                  toInt(a.value['joinedAt'], 0)
                      .compareTo(toInt(b.value['joinedAt'], 0)));
            room['host'] = entries.first.key;
          }

          room['players'] = players;
          return {'ok': true};
        }

        if (room['status'] == 'playing') {
          me['left'] = true;
          me['connected'] = false;
          players[uid] = me;
          room['players'] = players;

          final active = _activeColors(room);

          if (active.length < 2) {
            _finishGame(
                room, active.isEmpty ? null : active.first, time);
            finishedRoom = room;
          } else if (_map(room['game'])['turn'] == me['color']) {
            _passTurn(room, time);
          }
        }

        return {'ok': true};
      });
    } catch (e) {
      if (e is! BackendException ||
          !e.message.contains('not found')) {
        rethrow;
      }
    } finally {
      await forgetRoom();
    }

    if (finishedRoom != null) {
      await _recordFinished(finishedRoom!);
    }
  }

  static Stream<Room?> watchRoom(String code) {
    return db.ref('rooms/${_cleanCode(code)}').onValue.map((event) {
      if (!event.snapshot.exists) return null;
      return Room.parse(code, event.snapshot.value);
    });
  }

  static Future<void> forgetRoom() async {
    detachPresence();

    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('lastRoom');
  }

  static Future<String?> activeRoom() async {
    final prefs = await SharedPreferences.getInstance();
    final code = prefs.getString('lastRoom');

    if (code == null) return null;

    try {
      final snapshot = await db.ref('rooms/$code').get();

      if (!snapshot.exists) {
        await prefs.remove('lastRoom');
        return null;
      }

      final room = Room.parse(code, snapshot.value);
      final player = room.players[uid];

      if (player == null ||
          player.left ||
          room.status == 'finished') {
        await prefs.remove('lastRoom');
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

    _presenceSub = db.ref('.info/connected').onValue.listen((event) async {
      if (event.snapshot.value == true) {
        try {
          await me.child('connected').onDisconnect().set(false);
          await me.child('lastSeen')
              .onDisconnect()
              .set(ServerValue.timestamp);

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
