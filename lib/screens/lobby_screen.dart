
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../backend.dart';
import '../config.dart';
import '../models.dart';
import '../common.dart';
import 'game_screen.dart';

class LobbyScreen extends StatefulWidget {
  final String code;

  const LobbyScreen({super.key, required this.code});

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  StreamSubscription<Room?>? _sub;
  Room? _room;
  bool _starting = false, _navigated = false;

  @override
  void initState() {
    super.initState();
    Backend.attachPresence(widget.code);
    _sub = Backend.watchRoom(widget.code).listen(_onRoom, onError: (_) {});
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  void _gone(String msg) {
    if (_navigated) return;
    _navigated = true;
    Backend.forgetRoom();
    final m = ScaffoldMessenger.of(context);
    m.showSnackBar(SnackBar(content: Text(msg)));
    Navigator.of(context).popUntil((r) => r.isFirst);
  }

  void _onRoom(Room? r) {
    if (!mounted || _navigated) return;
    if (r == null) return _gone('The room was closed.');
    if (r.players[Backend.uid] == null) {
      return _gone('You are no longer in this room.');
    }

    if (r.status == 'playing') {
      _navigated = true;
      _sub?.cancel();
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => GameScreen(code: widget.code),
        ),
      );
      return;
    }

    setState(() => _room = r);
  }

  Future<void> _share() async {
    try {
      await Share.share(
        inviteMessage(widget.code),
        subject: "Join my Mahin's Ludo game",
      );
    } catch (_) {
      if (mounted) showMsg(context, 'Could not open the share menu.');
    }
  }

  Future<void> _whatsapp() async {
    final uri = Uri.parse(
      'https://wa.me/?text=${Uri.encodeComponent(inviteMessage(widget.code))}',
    );

    try {
      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!ok) await _share();
    } catch (_) {
      await _share();
    }
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.code));
    if (mounted) {
      showMsg(context, 'Room code copied: ${widget.code}');
    }
  }

  Future<void> _copyLink() async {
    await Clipboard.setData(
      ClipboardData(text: inviteLink(widget.code)),
    );
    if (mounted) showMsg(context, 'Invite link copied');
  }

  Future<void> _start() async {
    setState(() => _starting = true);

    try {
      await Backend.startGame(widget.code);
    } on BackendException catch (e) {
      if (mounted) showMsg(context, e.message);
    } finally {
      if (mounted) setState(() => _starting = false);
    }
  }

  Future<void> _leave() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Leave room?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Stay'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Leave'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    _navigated = true;

    try {
      await Backend.leaveRoom(widget.code);
    } catch (_) {}

    if (mounted) {
      Navigator.of(context).popUntil((r) => r.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = _room;
    final isHost = room != null && room.host == Backend.uid;
    final players = room?.sortedPlayers ?? <RoomPlayer>[];
    final max = room?.maxPlayers ?? 4;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Room Lobby'),
          backgroundColor: Colors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: _leave,
          ),
        ),
        extendBodyBehindAppBar: true,
        body: GradientBg(
          child: SafeArea(
            child: room == null
                ? const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                : Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(20),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          children: [
                            const SizedBox(height: 40),
                            const Text(
                              'ROOM CODE',
                              style: TextStyle(
                                color: Colors.white70,
                                letterSpacing: 3,
                              ),
                            ),
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 20,
                                vertical: 10,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white12,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.code,
                                    style: const TextStyle(
                                      fontSize: 42,
                                      fontWeight: FontWeight.w900,
                                      letterSpacing: 8,
                                    ),
                                  ),
                                  IconButton(
                                    onPressed: _copy,
                                    icon: const Icon(Icons.copy),
                                    tooltip: 'Copy code',
                                  ),
                                ],
                              ),
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: BigButton(
                                    label: 'Invite',
                                    icon: Icons.share,
                                    color: const Color(0xFF1E88E5),
                                    onTap: _share,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: BigButton(
                                    label: 'WhatsApp',
                                    icon: Icons.chat,
                                    color: const Color(0xFF25D366),
                                    onTap: _whatsapp,
                                  ),
                                ),
                              ],
                            ),
                            TextButton.icon(
                              onPressed: _copyLink,
                              icon: const Icon(Icons.link),
                              label: const Text('Copy invite link'),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Players ${players.length}/$max',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            for (var i = 0; i < max; i++)
                              i < players.length
                                  ? _playerTile(players[i], room.host)
                                  : _emptyTile(),
                            const SizedBox(height: 20),
                            if (isHost)
                              BigButton(
                                label: 'Start Game',
                                icon: Icons.play_arrow,
                                busy: _starting,
                                color: const Color(0xFF2E7D32),
                                onTap: players.length >= 2 ? _start : null,
                              )
                            else
                              const Text(
                                'Waiting for the host to start the game…',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 16,
                                ),
                              ),
                            if (isHost && players.length < 2)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Invite at least one friend to start.',
                                  style: TextStyle(color: Colors.white70),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Widget _playerTile(RoomPlayer p, String host) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white12,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          AvatarBubble(index: p.avatar, size: 44),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              p.name + (p.uid == Backend.uid ? ' (You)' : ''),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (p.uid == host)
            const Text(
              '👑 HOST  ',
              style: TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.w800,
              ),
            ),
          Icon(
            Icons.circle,
            size: 12,
            color: p.connected ? Colors.greenAccent : Colors.grey,
          ),
        ],
      ),
    );
  }

  Widget _emptyTile() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 5),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.white24),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Row(
        children: [
          Icon(Icons.hourglass_empty, color: Colors.white38),
          SizedBox(width: 14),
          Text(
            'Waiting for player…',
            style: TextStyle(color: Colors.white38, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
