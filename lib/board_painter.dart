import 'dart:math';
import 'package:flutter/material.dart';
import '../ludo_layout.dart';

class TokenDraw {
  final int color, index;
  final Offset pos;
  final double scale;
  TokenDraw(this.color, this.index, this.pos, this.scale);
}

List<TokenDraw> layoutTokens(Map<int, List<double>> pos, double cell) {
  final groups = <String, List<List<int>>>{};
  final points = <String, Offset>{};
  pos.forEach((c, list) {
    for (var i = 0; i < list.length; i++) {
      final pt = tokenPoint(c, i, list[i]);
      final key = '${(pt.dx * 100).round()}_${(pt.dy * 100).round()}';
      (groups[key] ??= []).add([c, i]);
      points[key] = pt;
    }
  });
  final out = <TokenDraw>[];
  groups.forEach((key, items) {
    final base = points[key]!;
    final n = items.length;
    for (var k = 0; k < n; k++) {
      var off = Offset.zero;
      var sc = 1.0;
      if (n > 1) {
        sc = n == 2 ? 0.8 : 0.7;
        final a = 2 * pi * k / n;
        off = Offset(cos(a), sin(a)) * 0.2;
      }
      out.add(TokenDraw(items[k][0], items[k][1], (base + off) * cell, sc));
    }
  });
  return out;
}

class BoardPainter extends CustomPainter {
  final Map<int, List<double>> from, to;
  final Animation<double> move, pulse;
  final Set<int> highlight;
  final int? highlightColor;

  BoardPainter({
    required this.from,
    required this.to,
    required this.move,
    required this.pulse,
    required this.highlight,
    required this.highlightColor,
  }) : super(repaint: Listenable.merge([move, pulse]));

  static Map<int, List<double>> positions(
      Map<int, List<double>> from, Map<int, List<double>> to, double t) {
    final out = <int, List<double>>{};
    to.forEach((c, list) {
      final f = from[c] ?? list;
      out[c] = List.generate(list.length, (i) {
        final a = i < f.length ? f[i] : list[i];
        final b = list[i];
        if (a == b) return b;
        if (a >= 0 && b > a) return a + (b - a) * Curves.easeInOut.transform(t);
        if (b < 0) return t < 0.85 ? a : b;
        return b;
      });
    });
    return out;
  }

  Path _star(Offset c, double r) {
    final p = Path();
    for (var i = 0; i < 10; i++) {
      final rad = i.isEven ? r : r * 0.45;
      final a = -pi / 2 + i * pi / 5;
      final pt = c + Offset(cos(a) * rad, sin(a) * rad);
      if (i == 0) {
        p.moveTo(pt.dx, pt.dy);
      } else {
        p.lineTo(pt.dx, pt.dy);
      }
    }
    p.close();
    return p;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final cell = size.width / 15;
    final p = Paint();
    final bg = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(cell * 0.6));
    canvas.save();
    canvas.clipRRect(bg);
    canvas.drawRect(Offset.zero & size, p..color = Colors.white);

    for (var c = 0; c < 4; c++) {
      final o = yardOrigin[c];
      canvas.drawRect(Rect.fromLTWH(o.dx * cell, o.dy * cell, 6 * cell, 6 * cell), p..color = colorValues[c]);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH((o.dx + 1) * cell, (o.dy + 1) * cell, 4 * cell, 4 * cell), Radius.circular(cell * 0.7)),
          p..color = Colors.white);
      for (var i = 0; i < 4; i++) {
        canvas.drawCircle(tokenPoint(c, i, -1) * cell, cell * 0.46, p..color = colorValues[c].withOpacity(0.28));
      }
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8
      ..color = const Color(0xFF9E9E9E);
    Rect cellRect(int r, int c) => Rect.fromLTWH(c * cell, r * cell, cell, cell);

    for (var i = 0; i < 52; i++) {
      final t = trackCells[i];
      final r = cellRect(t[0], t[1]);
      var fill = Colors.white;
      var isStart = false;
      for (var c = 0; c < 4; c++) {
        if (startOffset[c] == i) {
          fill = colorValues[c];
          isStart = true;
        }
      }
      canvas.drawRect(r, Paint()..style = PaintingStyle.fill..color = fill);
      canvas.drawRect(r, line);
      if (safeSquares.contains(i)) {
        canvas.drawPath(_star(r.center, cell * 0.34),
            Paint()..color = isStart ? Colors.white70 : const Color(0xFF8D8D8D));
      }
    }

    for (var c = 0; c < 4; c++) {
      for (final h in homeCells[c]) {
        final r = cellRect(h[0], h[1]);
        canvas.drawRect(r, Paint()..color = colorValues[c]);
        canvas.drawRect(r, line);
      }
    }

    Offset g(double x, double y) => Offset(x * cell, y * cell);
    final tri = [
      [g(6, 6), g(6, 9), g(7.5, 7.5)],
      [g(6, 6), g(9, 6), g(7.5, 7.5)],
      [g(9, 6), g(9, 9), g(7.5, 7.5)],
      [g(6, 9), g(9, 9), g(7.5, 7.5)],
    ];
    for (var c = 0; c < 4; c++) {
      final path = Path()
        ..moveTo(tri[c][0].dx, tri[c][0].dy)
        ..lineTo(tri[c][1].dx, tri[c][1].dy)
        ..lineTo(tri[c][2].dx, tri[c][2].dy)
        ..close();
      canvas.drawPath(path, Paint()..color = colorValues[c]);
      canvas.drawPath(path, Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = Colors.white54);
    }
    canvas.restore();
    canvas.drawRRect(bg, Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = Colors.white70);

    final pos = positions(from, to, move.value);
    final draws = layoutTokens(pos, cell);
    for (final d in draws) {
      final r = cell * 0.38 * d.scale;
      var hop = 0.0;
      final fl = from[d.color];
      final tl = to[d.color];
      if (fl != null && tl != null && d.index < fl.length && d.index < tl.length) {
        final a = fl[d.index], b = tl[d.index];
        if (a >= 0 && b > a && move.value < 1) {
          hop = sin(move.value * (b - a) * pi).abs() * cell * 0.3;
        }
      }
      final center = d.pos - Offset(0, hop);
      canvas.drawCircle(d.pos + Offset(0, cell * 0.1), r, Paint()..color = Colors.black38);
      canvas.drawCircle(center, r, Paint()..color = colorValues[d.color]);
      canvas.drawCircle(
          center, r, Paint()..style = PaintingStyle.stroke..strokeWidth = 2.6..color = Colors.white);
      canvas.drawCircle(center, r * 0.62,
          Paint()..style = PaintingStyle.stroke..strokeWidth = 1.5..color = Colors.black26);
      canvas.drawCircle(center - Offset(r * 0.3, r * 0.3), r * 0.28, Paint()..color = Colors.white38);
      if (highlightColor == d.color && highlight.contains(d.index)) {
        canvas.drawCircle(
            center,
            r * (1.3 + 0.2 * pulse.value),
            Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3.2
              ..color = Colors.white);
      }
    }
  }

  @override
  bool shouldRepaint(covariant BoardPainter old) => true;
}
