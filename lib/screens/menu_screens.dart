
import 'package:flutter/material.dart';
import '../backend.dart';
import '../deep_links.dart';
import '../models.dart';
import '../common.dart';
import 'game_screen.dart';
import 'lobby_screen.dart';
import 'profile_settings.dart';

class MenuScreen extends StatefulWidget {
  const MenuScreen({super.key});

  @override
  State<MenuScreen> createState() => _MenuScreenState();
}

class _MenuScreenState extends State<MenuScreen> {
  bool _loading = false;

  Future<void> _createRoom() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final room = await Backend.createRoom();
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LobbyScreen(roomCode: room.code),
        ),
      );
    } catch (e) {
      if (mounted) showMsg(context, 'রুম তৈরি করা যায়নি: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _quickMatch() async {
    if (_loading) return;
    setState(() => _loading = true);

    try {
      final room = await Backend.quickMatch();
      if (!mounted) return;

      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => LobbyScreen(roomCode: room.code),
        ),
      );
    } catch (e) {
      if (mounted) showMsg(context, 'Match পাওয়া যায়নি: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _joinRoom() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const JoinRoomScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const LudoLogo(),
                  const SizedBox(height: 18),
                  const Text(
                    'MAHINS LUDO',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 30,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 35),
                  BigButton(
                    text: 'CREATE ROOM',
                    onPressed: _loading ? null : _createRoom,
                  ),
                  const SizedBox(height: 14),
                  BigButton(
                    text: 'QUICK MATCH',
                    onPressed: _loading ? null : _quickMatch,
                  ),
                  const SizedBox(height: 14),
                  BigButton(
                    text: 'JOIN ROOM',
                    onPressed: _joinRoom,
                  ),
                  const SizedBox(height: 14),
                  BigButton(
                    text: 'PROFILE & SETTINGS',
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ProfileSettingsScreen(),
                        ),
                      );
                    },
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 20),
                    const CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class JoinRoomScreen extends StatefulWidget {
  final String? initialCode;
  final bool autoJoin;

  const JoinRoomScreen({
    super.key,
    this.initialCode,
    this.autoJoin = false,
  });

  @override
  State<JoinRoomScreen> createState() => _JoinRoomScreenState();
}

class _JoinRoomScreenState extends State<JoinRoomScreen> {
  final TextEditingController _controller = TextEditingController();
  bool _loading = false;

  @override
  void initState() {
    super.initState();

    if (widget.initialCode != null) {
      _controller.text = widget.initialCode!;
    }

    if (widget.autoJoin) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _join();
      });
    }
  }

  Future<void> _join() async {
    final code = _controller.text.trim().toUpperCase();

    if (code.isEmpty) {
      showMsg(context, 'Room code লিখুন');
      return;
    }

    if (_loading) return;
    setState(() => _loading = true);

    try {
      final room = await Backend.joinRoom(code);
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => LobbyScreen(roomCode: room.code),
        ),
      );
    } catch (e) {
      if (mounted) showMsg(context, 'Room-এ যোগ দেওয়া যায়নি: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Join Room'),
        backgroundColor: Colors.transparent,
      ),
      body: GradientBg(
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'ENTER ROOM CODE',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 22),
                  TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.characters,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      letterSpacing: 5,
                    ),
                    decoration: const InputDecoration(
                      hintText: 'ABC123',
                      hintStyle: TextStyle(color: Colors.white54),
                      counterStyle: TextStyle(color: Colors.white),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.yellow),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  BigButton(
                    text: _loading ? 'JOINING...' : 'JOIN ROOM',
                    onPressed: _loading ? null : _join,
                  ),
                  if (_loading) ...[
                    const SizedBox(height: 18),
                    const CircularProgressIndicator(
                      color: Colors.white,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
