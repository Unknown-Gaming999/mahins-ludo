import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import '../backend.dart';
import '../ludo_layout.dart';
import '../models.dart';
import '../settings.dart';
import '../widgets/board_painter.dart';
import '../widgets/common.dart';
import '../widgets/dice_view.dart';

class GameScreen extends StatefulWidget {
  final String code;
  const GameScreen({super.key, required this.code});
  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> with TickerProviderStateMixin, WidgetsBindingObserver {
  late final AnimationController _move =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
  late final AnimationController _pulse =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);

  StreamSubscription<Room?>? _sub;
  Timer? _ticker, _settleTimer;
  Room? _room;
  Map<int, List<double>> _from = {}, _to = {};
  int _lastDiceSeq = -1;
  bool _rollPending = false, _settling = false, _busy = false, _overShown = false, _exiting = false;
  int _remaining = 0, _skipSeq = -1;
  DateTime _skipAt = DateTime.fromMillisecondsSinceEpoch(0);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Backend.attachPresence(widget.code);
    _sub = Backend.watchRoom(widget.code).listen(_onRoom, onError: (_) {});
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _ticker?.cancel();
    _settleTimer?.cancel();
    _move.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      try {
        Backend.db.goOnline();
      } catch (_) {}
    }
  }

  void _exit(String? message) {
    if (_exiting || !mounted) return;
    _exiting = true;
    Backend.forgetRoom();
    final m = ScaffoldMessenger.of(context);
    if (message != null) m.showSnackBar(SnackBar(content: Text(message)));
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Map<int, List<double>> _dbl(Map<int, List<int>> t) =>
      t.map((k, v) => MapEntry(k, v.map((e) => e.toDouble()).toList()));

  void _onRoom(Room? r) {
    if (!mounted || _exiting) return;
    if (r == null) return _exit('The room was closed.');
    final me = r.players[Backend.uid];
    if (me == null || me.left) return _exit('You are no longer in this game.');
    final g = r.game;
    if (g != null) {
      final nt = _dbl(g.tokens);
      if (_to.isEmpty) {
        _from = nt;
        _to = nt;
      } else if (!_same(_to, nt)) {
        final cur = BoardPainter.positions(_from, _to, _move.value);
        var steps = 1.0;
        nt.forEach((c, list) {
          for (var i = 0; i < list.length; i++) {
            final old = (_to[c] != null && i < _to[c]!.length) ? _to[c]![i] : list[i];
            if (old >= 0 && list[i] > old) steps = max(steps, list[i] - old);
          }
        });
        _from = cur;
        _to = nt;
        _move.duration = Duration(milliseconds: (steps * 170).clamp(400, 1200).toInt());
        _move.forward(from: 0);
        AppSettings.tap();
      }
      if (g.diceSeq != _lastDiceSeq) {
        if (_lastDiceSeq != -1) {
          _settling = true;
          _settleTimer?.cancel();
          _settleTimer = Timer(const Duration(milliseconds: 650), () {
            if (mounted) setState(() => _settling = false);
          });
        }
        _lastDiceSeq = g.diceSeq;
        _rollPending = false;
      }
    }
    _busy = false;
    setState(() => _room = r);
    if (r.status == 'finished' && !_overShown) {
      _overShown = true;
      Future.delayed(const Duration(milliseconds: 1400), _showWinner);
    }
  }

  bool _same(Map<int, List<double>> a, Map<int, List<double>> b) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      final x = a[k], y = b[k];
      if (y == null || x!.length != y.length) return false;
      for (var i = 0; i < x.length; i++) {
        if (x[i] != y[i]) return false;
      }
    }
    return true;
  }

  void _tick() {
    final r = _room;
    final g = r?.game;
    if (r == null || g == null || r.status != 'playing' || !mounted) return;
    final left = (g.turnDeadline - Backend.now()) / 1000;
    setState(() => _remaining = max(0, left.ceil()));
    final cur = r.byColor(g.turn);
    if (cur == null) return;
    final expired = Backend.now() > g.turnDeadline + 1500;
    final dropped = !cur.connected && cur.lastSeen > 0 && Backend.now() - cur.lastSeen > 11000;
    if (!(expired || dropped)) return;
    if (_skipSeq == g.seq && DateTime.now().difference(_skipAt).inSeconds < 4) return;
    _skipSeq = g.seq;
    _skipAt = DateTime.now();
    Future.delayed(Duration(milliseconds: Random().nextInt(1200)), () {
      Backend.skipTurn(widget.code).catchError((_) {});
    });
  }

  Future<void> _roll() async {
    final r = _room;
    final g = r?.game;
    final me = r?.players[Backend.uid];
    if (g == null || me == null || g.turn != me.color || g.phase != 'roll' || _rollPending) return;
    setState(() => _rollPending = true);
    AppSettings.tap();
    try {
      await Backend.rollDice(widget.code);
    } on BackendException catch (e) {
      if (mounted) showMsg(context, e.message);
    } finally {
      if (mounted) setState(() => _rollPending = false);
    }
  }

  Future<void> _moveToken(int i) async {
    setState(() => _busy = true);
    try {
      await Backend.moveToken(widget.code, i);
    } on BackendException catch (e) {
      if (mounted) showMsg(context, e.message);
      if (mounted) setState(() => _busy = false);
    }
  }

  void _onBoardTap(Offset local, double size) {
    final g = _room?.game;
    final me = _room?.players[Backend.uid];
    if (g == null || me == null || me.color == null) return;
    if (g.turn != me.color || g.phase != 'move' || _busy) return;
    final cell = size / 15;
    int? best;
    var bd = double.infinity;
    for (final d in layoutTokens(_to, cell)) {
      if (d.color != me.color || !g.movable.contains(d.index)) continue;
      final dist = (d.pos - local).distance;
      if (dist < bd) {
        bd = dist;
        best = d.index;
      }
    }
    if (best != null && bd < cell * 0.9) _moveToken(best);
  }

  void _showWinner() {
    final r = _room;
    if (r == null || !mounted || _exiting) return;
    final w = r.game?.winner;
    final p = w == null ? null : r.byColor(w);
    final mine = p != null && p.uid == Backend.uid;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (c) => AlertDialog(
        title: Text(mine ? '🏆 You won!' : 'Game over'),
        content: Text(p == null
            ? 'The game has ended.'
            : '${p.name} (${colorNames[w!]}) brought all four tokens home!'),
        actions: [
          FilledButton(
              onPressed: () {
                Navigator.pop(c);
                _exit(null);
              },
              child: const Text('Back to menu')),
        ],
      ),
    );
  }

  Future<void> _confirmLeave() async {
    final r = _room;
    if (r == null || r.status == 'finished') return _exit(null);
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Leave game?'),
        content: const Text('If you leave you cannot rejoin this game. To pause, just close the app instead — you can resume from the menu.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Stay')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Leave')),
        ],
      ),
    );
    if (ok == true) {
      try {
        await Backend.leaveRoom(widget.code);
      } catch (_) {}
      _exit(null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = _room;
    final g = r?.game;
    final me = r?.players[Backend.uid];
    final isMyTurn = r != null && g != null && me != null && r.status == 'playing' && g.turn == me.color;
    final canRoll = isMyTurn && g!.phase == 'roll';
    final canMove = isMyTurn && g!.phase == 'move';

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmLeave();
      },
      child: Scaffold(
        body: GradientBg(
          child: SafeArea(
            child: (r == null || g == null)
                ? const Center(child: CircularProgressIndicator(color: Colors.white))
                : Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                        child: Row(
                          children: [
                            IconButton(onPressed: _confirmLeave, icon: const Icon(Icons.exit_to_app)),
                            Expanded(
                                child: Text("Mahin's Ludo  •  ${widget.code}",
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800))),
                            const SizedBox(width: 48),
                          ],
                        ),
                      ),
                      _chips(r, g),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: LayoutBuilder(builder: (context, c) {
                            final s = min(c.maxWidth, c.maxHeight);
                            return Center(
                              child: SizedBox(
                                width: s,
                                height: s,
                                child: GestureDetector(
                                  onTapUp: (d) => _onBoardTap(d.localPosition, s),
                                  child: CustomPaint(
                                    painter: BoardPainter(
                                      from: _from,
                                      to: _to,
                                      move: _move,
                                      pulse: _pulse,
                                      highlight: canMove ? g.movable.toSet() : <int>{},
                                      highlightColor: canMove ? me.color : null,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }),
                        ),
                      ),
                      _bottom(r, g, me, canRoll, canMove),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _chips(Room r, GameState g) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: Row(
        children: [
          for (final c in g.order)
            Expanded(
              child: Builder(builder: (context) {
                final p = r.byColor(c);
                final turn = g.turn == c && r.status == 'playing';
                final home = (g.tokens[c] ?? []).where((x) => x == finishPos).length;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  margin: const EdgeInsets.all(3),
                  padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                  decoration: BoxDecoration(
                    color: colorValues[c].withOpacity(turn ? 0.9 : 0.35),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: turn ? Colors.white : Colors.white24, width: turn ? 3 : 1),
                    boxShadow: turn ? [BoxShadow(color: colorValues[c], blurRadius: 14)] : null,
                  ),
                  child: Column(
                    children: [
                      AvatarBubble(index: p?.avatar ?? 0, size: 34, ring: colorValues[c]),
                      const SizedBox(height: 2),
                      Text(p?.name ?? '-',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: c == 2 ? Colors.black87 : Colors.white)),
                      Text(
                          p == null
                              ? ''
                              : p.left
                                  ? 'LEFT'
                                  : (!p.connected ? 'OFFLINE' : 'Home $home/4'),
                          style: TextStyle(fontSize: 11, color: c == 2 ? Colors.black87 : Colors.white70)),
                    ],
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }

  Widget _bottom(Room r, GameState g, RoomPlayer? me, bool canRoll, bool canMove) {
    final cur = r.byColor(g.turn);
    String status;
    if (r.status == 'finished') {
      status = 'Game over';
    } else if (canRoll) {
      status = 'Your turn — tap the dice!';
    } else if (canMove) {
      status = 'Tap a glowing token to move';
    } else {
      status = "${cur?.name ?? '…'}'s turn (${colorNames[g.turn]})${cur != null && !cur.connected ? ' - disconnected' : ''}";
    }
    final roller = g.rolledBy == null ? null : r.byColor(g.rolledBy!);
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: const BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          DiceView(
            value: g.dice,
            rolling: _rollPending || _settling,
            active: canRoll,
            onTap: canRoll ? _roll : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(status, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
                if (g.dice > 0 && roller != null)
                  Text('${roller.name} rolled ${g.dice}', style: const TextStyle(color: Colors.white70)),
                if (g.event.isNotEmpty)
                  Text(g.event, style: const TextStyle(color: Colors.amber, fontWeight: FontWeight.w700)),
                if (r.status == 'playing')
                  Text('⏱ ${_remaining}s', style: const TextStyle(color: Colors.white54)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
