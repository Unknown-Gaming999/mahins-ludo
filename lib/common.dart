import 'package:flutter/material.dart';
import '../ludo_layout.dart';
import '../settings.dart';

const List<String> kAvatars = ['😎', '🦁', '🐯', '🦊', '🐼', '🐸', '🦄', '🐙', '🚀', '⚡', '🔥', '👑'];

class GradientBg extends StatelessWidget {
  final Widget child;
  const GradientBg({super.key, required this.child});
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B1A6E), Color(0xFF5B2BB5), Color(0xFF1E88E5)],
        ),
      ),
      child: child,
    );
  }
}

void showMsg(BuildContext c, String t) {
  ScaffoldMessenger.of(c)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(t)));
}

class BigButton extends StatefulWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final Color color;
  final bool busy;
  const BigButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.color = const Color(0xFFFF8F00),
    this.busy = false,
  });
  @override
  State<BigButton> createState() => _BigButtonState();
}

class _BigButtonState extends State<BigButton> {
  bool _down = false;
  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null && !widget.busy;
    return GestureDetector(
      onTapDown: enabled ? (_) => setState(() => _down = true) : null,
      onTapUp: enabled ? (_) => setState(() => _down = false) : null,
      onTapCancel: () => setState(() => _down = false),
      onTap: enabled
          ? () {
              AppSettings.tap();
              widget.onTap!();
            }
          : null,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 90),
        child: Opacity(
          opacity: (enabled || widget.busy) ? 1 : 0.5,
          child: Container(
            height: 60,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [widget.color, Color.lerp(widget.color, Colors.black, 0.25)!]),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white24, width: 2),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 10, offset: Offset(0, 5))],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                widget.busy
                    ? const SizedBox(
                        width: 24, height: 24,
                        child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
                    : Icon(widget.icon, color: Colors.white, size: 26),
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    widget.label,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 19, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AvatarBubble extends StatelessWidget {
  final int index;
  final double size;
  final Color? ring;
  const AvatarBubble({super.key, required this.index, this.size = 44, this.ring});
  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: ring ?? Colors.white54, width: 3),
      ),
      child: Text(kAvatars[index % kAvatars.length], style: TextStyle(fontSize: size * 0.55)),
    );
  }
}

class LudoLogo extends StatelessWidget {
  final double size;
  const LudoLogo({super.key, this.size = 120});
  @override
  Widget build(BuildContext context) =>
      SizedBox(width: size, height: size, child: CustomPaint(painter: _LogoPainter()));
}

class _LogoPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final gap = s * 0.04;
    final h = (s - gap * 3) / 2;
    final cols = [colorValues[0], colorValues[1], colorValues[3], colorValues[2]];
    final pos = [Offset(gap, gap), Offset(gap * 2 + h, gap), Offset(gap, gap * 2 + h), Offset(gap * 2 + h, gap * 2 + h)];
    final p = Paint();
    for (var i = 0; i < 4; i++) {
      final r = RRect.fromRectAndRadius(Rect.fromLTWH(pos[i].dx, pos[i].dy, h, h), Radius.circular(s * 0.12));
      canvas.drawRRect(r.shift(Offset(0, s * 0.02)), p..color = Colors.black26);
      canvas.drawRRect(r, p..color = cols[i]);
      canvas.drawRRect(r, Paint()..style = PaintingStyle.stroke..strokeWidth = s * 0.015..color = Colors.white);
    }
    final c = Offset(s / 2, s / 2);
    final die = RRect.fromRectAndRadius(Rect.fromCenter(center: c, width: s * 0.42, height: s * 0.42), Radius.circular(s * 0.09));
    canvas.drawRRect(die, p..color = Colors.white);
    final dot = Paint()..color = const Color(0xFF28283C);
    for (final d in const [Offset(-1, -1), Offset(1, -1), Offset(0, 0), Offset(-1, 1), Offset(1, 1)]) {
      canvas.drawCircle(c + d * (s * 0.1), s * 0.035, dot);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
