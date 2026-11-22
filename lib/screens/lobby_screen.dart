
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
  final String roomCode;

  const LobbyScreen({
    super.key,
    required this.roomCode,
  });

  @override
  State<LobbyScreen> createState() => _LobbyScreenState();
}

class _LobbyScreenState extends State<LobbyScreen> {
  bool _starting = false;
  bool _leaving = false;

  Future<void> _copyCode() async {
    await Clipboard.setData(
      ClipboardData(text: widget.roomCode),
    );

    if (mounted) {
      showMsg(context, 'Room code copied!');
    }
  }

  Future<void> _shareRoom() async {
    final link = inviteLink(widget.roomCode);

    await Share.share(
      inviteMessage(widget.roomCode) + '\n$link',
    );
  }

  Future<void> _startGame() async {
    if (_starting) return;

    setState(() => _starting = true);

    try {
      await Backend.startGame(widget.roomCode);

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => GameScreen(
            roomCode: widget.roomCode,
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        showMsg(context, 'Game start failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  Future<void> _leaveRoom() async {
    if (_leaving) return;

    setState(() => _leaving = true);

    try {
      await Backend.leaveRoom(widget.roomCode);

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        showMsg(context, 'Leave failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _leaving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Game Lobby'),
        foregroundColor: Colors.white,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            onPressed: _shareRoom,
            icon: const Icon(Icons.share),
          ),
        ],
      ),
      body: GradientBg(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  const LudoLogo(),
                  const SizedBox(height: 22),
                  const Text(
                    'ROOM CODE',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 30,
                      vertical: 18,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Text(
                      widget.roomCode,
                      style: const TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 5,
                        color: Colors.black,
                      ),
                    ),
                  ),
                  const SizedBox(height: 15),
                  OutlinedButton.icon(
                    onPressed: _copyCode,
                    icon: const Icon(Icons.copy),
                    label: const Text('COPY CODE'),
                  ),
                  const SizedBox(height: 15),
                  BigButton(
                    text: 'INVITE FRIENDS',
                    onPressed: _shareRoom,
                  ),
                  const SizedBox(height: 18),
                  BigButton(
                    text: _starting ? 'STARTING...' : 'START GAME',
                    onPressed: _starting ? null : _startGame,
                  ),
                  const SizedBox(height: 12),
                  BigButton(
                    text: _leaving ? 'LEAVING...' : 'LEAVE ROOM',
                    onPressed: _leaving ? null : _leaveRoom,
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
