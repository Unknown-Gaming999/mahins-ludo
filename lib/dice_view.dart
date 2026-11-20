import 'dart:math';
import 'package:flutter/material.dart';

class DiceView extends StatefulWidget {
  final int value;
  final bool rolling;
  final bool active;
  final VoidCallback? onTap;
  const DiceView({super.key, required this.value, required this.rolling, required this.active, this.onTap});
  @override
  State<DiceView> createState() => _DiceViewState();
}

class _DiceViewState extends State<DiceView> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 600));

  @override
  void initState() {
    super.initState();
    if (widget.rolling) _c.repeat();
  }

  @override
  void didUpdateWidget(covariant DiceView old) {
    super.didUpdateWidget(old);
    if (widget.rolling && !_c.isAnimating) {
      _c.repeat();
    } else if (!widget.rolling && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) {
          final r = widget.rolling;
          final face = r ? ((_c.value * 10).floor() * 5 + 3) % 6 + 1 : (widget.value == 0 ? 1 : widget.value);
          final angle = r ? sin(_c.value * 4 * pi) * 0.4 : 0.0;
          return Transform.rotate(
            angle: angle,
            child: Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: widget.active ? const Color(0xFFFFC107) : Colors.black26, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: widget.active ? const Color(0xFFFFC107).withOpacity(0.8) : Colors.black38,
                    blurRadius: widget.active ? 18 : 8,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: CustomPaint(painter: _PipPainter(face)),
            ),
          );
        },
      ),
    );
  }
}

class _PipPainter extends CustomPainter {
  final int face;
  _PipPainter(this.face);

  static const Map<int, List<int>> _pips = {
    1: [4],
    2: [0, 8],
    3: [0, 4, 8],
    4: [0, 2, 6, 8],
    5: [0, 2, 4, 6, 8],
    6: [0, 2, 3, 5, 6, 8],
  };

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = const Color(0xFF28283C);
    final s = size.width;
    for (final i in _pips[face]!) {
      final row = i ~/ 3, col = i % 3;
      canvas.drawCircle(Offset(s * (0.25 + 0.25 * col), s * (0.25 + 0.25 * row)), s * 0.08, p);
    }
  }

  @override
  bool shouldRepaint(covariant _PipPainter old) => old.face != face;
}
