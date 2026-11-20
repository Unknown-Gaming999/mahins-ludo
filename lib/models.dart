Map<String, dynamic> asMap(Object? v) {
  if (v is Map) return v.map((k, val) => MapEntry(k.toString(), val));
  return <String, dynamic>{};
}

int toInt(Object? v, int d) => v is num ? v.toInt() : d;

List<int> asIntList(Object? v) {
  if (v is List) return v.map((e) => e is num ? e.toInt() : 0).toList();
  if (v is Map) {
    final es = v.entries.toList()
      ..sort((a, b) => int.parse('${a.key}').compareTo(int.parse('${b.key}')));
    return es.map((e) => e.value is num ? (e.value as num).toInt() : 0).toList();
  }
  return <int>[];
}

class RoomPlayer {
  final String uid, name;
  final int avatar, joinedAt, lastSeen;
  final int? color;
  final bool connected, left;
  RoomPlayer({
    required this.uid,
    required this.name,
    required this.avatar,
    required this.joinedAt,
    required this.lastSeen,
    required this.color,
    required this.connected,
    required this.left,
  });
  factory RoomPlayer.from(String uid, Map<String, dynamic> m) => RoomPlayer(
        uid: uid,
        name: (m['name'] ?? 'Player').toString(),
        avatar: toInt(m['avatar'], 0),
        joinedAt: toInt(m['joinedAt'], 0),
        lastSeen: toInt(m['lastSeen'], 0),
        color: m['color'] is num ? (m['color'] as num).toInt() : null,
        connected: m['connected'] != false,
        left: m['left'] == true,
      );
}

class GameState {
  final List<int> order;
  final Map<int, List<int>> tokens;
  final int turn, dice, diceSeq, seq, turnDeadline;
  final String phase, event;
  final List<int> movable;
  final int? winner, rolledBy;
  GameState({
    required this.order,
    required this.tokens,
    required this.turn,
    required this.dice,
    required this.diceSeq,
    required this.seq,
    required this.turnDeadline,
    required this.phase,
    required this.event,
    required this.movable,
    required this.winner,
    required this.rolledBy,
  });
  factory GameState.from(Map<String, dynamic> m) {
    final tk = <int, List<int>>{};
    asMap(m['tokens']).forEach((k, v) {
      tk[int.parse(k.substring(1))] = asIntList(v);
    });
    return GameState(
      order: asIntList(m['order']),
      tokens: tk,
      turn: toInt(m['turn'], 0),
      dice: toInt(m['dice'], 0),
      diceSeq: toInt(m['diceSeq'], 0),
      seq: toInt(m['seq'], 0),
      turnDeadline: toInt(m['turnDeadline'], 0),
      phase: (m['phase'] ?? 'roll').toString(),
      event: (m['event'] ?? '').toString(),
      movable: asIntList(m['movable']),
      winner: m['winner'] is num ? (m['winner'] as num).toInt() : null,
      rolledBy: m['rolledBy'] is num ? (m['rolledBy'] as num).toInt() : null,
    );
  }
}

class Room {
  final String code, host, status;
  final int maxPlayers;
  final Map<String, RoomPlayer> players;
  final GameState? game;
  Room({
    required this.code,
    required this.host,
    required this.status,
    required this.maxPlayers,
    required this.players,
    required this.game,
  });

  factory Room.parse(String code, Object? raw) {
    final m = asMap(raw);
    final players = <String, RoomPlayer>{};
    asMap(m['players']).forEach((k, v) {
      players[k] = RoomPlayer.from(k, asMap(v));
    });
    return Room(
      code: code,
      host: (m['host'] ?? '').toString(),
      status: (m['status'] ?? 'lobby').toString(),
      maxPlayers: toInt(m['maxPlayers'], 4),
      players: players,
      game: m['game'] == null ? null : GameState.from(asMap(m['game'])),
    );
  }

  RoomPlayer? byColor(int c) {
    for (final p in players.values) {
      if (p.color == c) return p;
    }
    return null;
  }

  List<RoomPlayer> get sortedPlayers {
    final l = players.values.toList()..sort((a, b) => a.joinedAt.compareTo(b.joinedAt));
    return l;
  }
}
