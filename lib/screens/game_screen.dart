
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../backend.dart';
import '../ludo_layout.dart';
import '../models.dart';
import '../settings.dart';
import '../board_painter.dart';
import '../common.dart';
import '../dice_view.dart';

class GameScreen extends StatefulWidget {
  final String roomCode;

  const GameScreen({
    super.key,
    required this.roomCode,
  });

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  int diceValue = 1;
  bool rolling = false;
  int? selectedToken;
  Timer? rollTimer;

  final Random random = Random();

  @override
  void dispose() {
    rollTimer?.cancel();
    super.dispose();
  }

  Future<void> rollDice() async {
    if (rolling) return;

    setState(() {
      rolling = true;
      selectedToken = null;
    });

    for (int i = 0; i < 10; i++) {
      await Future.delayed(const Duration(milliseconds: 70));
      if (!mounted) return;

      setState(() {
        diceValue = random.nextInt(6) + 1;
      });
    }

    if (!mounted) return;

    setState(() {
      rolling = false;
    });
  }

  void selectToken(int index) {
    if (rolling) return;

    setState(() {
      selectedToken = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Ludo Room ${widget.roomCode}'),
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
      ),
      body: GradientBg(
        child: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 12),
              const Text(
                'LUDO MATCH',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Center(
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      margin: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black38,
                            blurRadius: 12,
                            offset: Offset(0, 5),
                          ),
                        ],
                      ),
                      child: CustomPaint(
                        painter: BoardPainter(),
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _playerBox('RED', Colors.red),
                  _playerBox('GREEN', Colors.green),
                  _playerBox('YELLOW', Colors.amber),
                  _playerBox('BLUE', Colors.blue),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  GestureDetector(
                    onTap: rollDice,
                    child: Container(
                      width: 72,
                      height: 72,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 8,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: rolling
                          ? const CircularProgressIndicator()
                          : Text(
                              '$diceValue',
                              style: const TextStyle(
                                fontSize: 42,
                                fontWeight: FontWeight.bold,
                                color: Colors.black,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 24),
                  ElevatedButton(
                    onPressed: rolling ? null : rollDice,
                    child: const Text('ROLL DICE'),
                  ),
                ],
              ),
              const SizedBox(height: 22),
            ],
          ),
        ),
      ),
    );
  }

  Widget _playerBox(String name, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        name,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 11,
        ),
      ),
    );
  }
}
