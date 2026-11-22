
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../backend.dart';
import '../deep_links.dart';
import '../common.dart';
import 'game_screen.dart';
import 'lobby_screen.dart';
import 'profile_settings.dart';

void openRoom(BuildContext context, String code, String status, {bool replace = false}) {
  final route = MaterialPageRoute(
    builder: (_) => status == 'playing'
        ? GameScreen(code: code)
        : LobbyScreen(code: code),
  );

  if (replace) {
    Navigator.pushReplacement(context, route);
  } else {
    Navigator.push(context, route);
  }
}

Widget _page(BuildContext context, String title, List<Widget> children) {
  return Scaffold(
    extendBodyBehindAppBar: true,
    appBar: AppBar(
      title: Text(title),
      backgroundColor: Colors.transparent,
      elevation: 0,
    ),
    body: GradientBg(
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: children,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class MainMenuScreen extends StatefulWidget {
  const MainMenuScreen({super.key});

  @override
  State<MainMenuScreen> createState() => _MainMenuScreenState();
}

class _MainMenuScreenState extends State<MainMenuScreen> {
  String? _resume;

  @override
  void initState() {
    super.initState();
    DeepLinks.onReturn = _refresh;
    _refresh();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      DeepLinks.consumePending();
    });
  }

  Future<void> _refresh() async {
    final c = await Backend.activeRoom();
    if (mounted) setState(() => _resume = c);
  }

  Future<void> _resumeGame() async {
    final code = _resume!;

    try {
      final r = await Backend.joinRoom(code);
      if (!mounted) return;

      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => r['status'] == 'playing'
              ? GameScreen(code: code)
              : LobbyScreen(code: code),
        ),
      );

      _refresh();
    } on BackendException catch (e) {
      if (mounted) showMsg(context, e.message);
      await Backend.forgetRoom();
      _refresh();
    }
  }

  Future<void> _go(Widget w) async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => w),
    );
    _refresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GradientBg(
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const LudoLogo(size: 130),
                    const SizedBox(height: 10),
                    const Text(
                      "Mahin's Ludo",
                      style: TextStyle(
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 22),
                    if (_resume != null) ...[
                      BigButton(
                        label: 'Resume game  ($_resume)',
                        icon: Icons.play_circle_fill,
                        color: const Color(0xFF2E7D32),
                        onTap: _resumeGame,
                      ),
                      const SizedBox(height: 14),
                    ],
                    BigButton(
                      label: 'Online Multiplayer',
                      icon: Icons.public,
                      onTap: () => _go(const OnlineScreen()),
                    ),
                    const SizedBox(height: 14),
                    BigButton(
                      label: 'Play With Friends',
                      icon: Icons.group,
                      color: const Color(0xFF1E88E5),
                      onTap: () => _go(const FriendsScreen()),
                    ),
                    const SizedBox(height: 14),
                    BigButton(
                      label: 'Player Profile',
                      icon: Icons.person,
                      color: const Color(0xFF8E24AA),
                      onTap: () => _go(const ProfileScreen()),
                    ),
                    const SizedBox(height: 14),
                    BigButton(
                      label: 'Settings',
                      icon: Icons.settings,
                      color: const Color(0xFF546E7A),
                      onTap: () => _go(const SettingsScreen()),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnlineScreen extends StatefulWidget {
  const OnlineScreen({super.key});

  @override
  State<OnlineScreen> createState() => _OnlineScreenState();
}

class _OnlineScreenState extends State<OnlineScreen> {
  bool _busy = false;

  Future<void> _quick() async {
    setState(() => _busy = true);

    try {
      final r = await Backend.quickMatch();
      if (!mounted) return;

      openRoom(
        context,
        r['code'] as String,
        r['status'] as String,
        replace: true,
      );
    } on BackendException catch (e) {
      if (mounted) showMsg(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _page(context, 'Online Multiplayer', [
      const Text('🌍', style: TextStyle(fontSize: 70)),
      const SizedBox(height: 12),
      const Text(
        'Quick Match puts you in an open room with other online players. '
        'The game starts automatically when 4 players have joined, or the room host can start with 2 or more.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, color: Colors.white70),
      ),
      const SizedBox(height: 26),
      BigButton(
        label: 'Quick Match',
        icon: Icons.bolt,
        busy: _busy,
        onTap: _quick,
      ),
      const SizedBox(height: 14),
      BigButton(
        label: 'Play With Friends',
        icon: Icons.group,
        color: const Color(0xFF1E88E5),
        onTap: () => Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => const FriendsScreen()),
        ),
      ),
    ]);
  }
}

class FriendsScreen extends StatelessWidget {
  const FriendsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return _page(context, 'Play With Friends', [
      const Text('👫', style: TextStyle(fontSize: 70)),
      const SizedBox(height: 12),
      const Text(
        'Create a private room and invite friends on WhatsApp, or join one with a code.',
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 16, color: Colors.white70),
      ),
      const SizedBox(height: 26),
      BigButton(
        label: 'Create Room',
        icon: Icons.add_circle,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const CreateRoomScreen()),
        ),
      ),
      const SizedBox(height: 14),
      BigButton(
        label: 'Join Room',
        icon: Icons.login,
        color: const Color(0xFF2E7D32),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const JoinRoomScreen()),
        ),
      ),
    ]);
  }
}

class CreateRoomScreen extends StatefulWidget {
  const CreateRoomScreen({super.key});

  @override
  State<CreateRoomScreen> createState() => _CreateRoomScreenState();
}

class _CreateRoomScreenState extends State<CreateRoomScreen> {
  int _max = 4;
  bool _busy = false;

  Future<void> _create() async {
    setState(() => _busy = true);

    try {
      final r = await Backend.createRoom(_max);
      if (!mounted) return;

      openRoom(context, r['code'] as String, 'lobby', replace: true);
    } on BackendException catch (e) {
      if (mounted) showMsg(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _page(context, 'Create Room', [
      const Text(
        'How many players?',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 14),
      Wrap(
        spacing: 12,
        children: [
          for (final n in [2, 3, 4])
            ChoiceChip(
              label: Text('$n players', style: const TextStyle(fontSize: 16)),
              selected: _max == n,
              onSelected: (_) => setState(() => _max = n),
            ),
        ],
      ),
      const SizedBox(height: 28),
      BigButton(
        label: 'Create Room',
        icon: Icons.meeting_room,
        busy: _busy,
        onTap: _create,
      ),
    ]);
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
  late final TextEditingController _ctl =
      TextEditingController(text: widget.initialCode ?? '');

  bool _busy = false;

  @override
  void initState() {
    super.initState();

    if (widget.autoJoin && (widget.initialCode ?? '').length == 6) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _join());
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  Future<void> _join() async {
    final code = _ctl.text.trim().toUpperCase();

    if (code.length != 6) {
      showMsg(context, 'Enter the 6-character room code.');
      return;
    }

    setState(() => _busy = true);

    try {
      final r = await Backend.joinRoom(code);
      if (!mounted) return;

      openRoom(context, code, r['status'] as String, replace: true);
    } on BackendException catch (e) {
      if (mounted) showMsg(context, e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _page(context, 'Join Room', [
      const Text(
        'Enter the room code',
        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
      ),
      const SizedBox(height: 16),
      TextField(
        controller: _ctl,
        textAlign: TextAlign.center,
        textCapitalization: TextCapitalization.characters,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp('[A-Za-z0-9]')),
          LengthLimitingTextInputFormatter(6),
        ],
        style: const TextStyle(
          fontSize: 34,
          fontWeight: FontWeight.w900,
          letterSpacing: 8,
        ),
        decoration: InputDecoration(
          hintText: 'K7M2QX',
          filled: true,
          fillColor: Colors.white12,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
        onSubmitted: (_) => _join(),
      ),
      const SizedBox(height: 24),
      BigButton(
        label: 'Join Room',
        icon: Icons.login,
        busy: _busy,
        color: const Color(0xFF2E7D32),
        onTap: _join,
      ),
    ]);
  }
}
