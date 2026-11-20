import 'package:flutter/material.dart';

const List<String> colorNames = ['Red', 'Green', 'Yellow', 'Blue'];
const List<Color> colorValues = [
  Color(0xFFE53935),
  Color(0xFF43A047),
  Color(0xFFFDD835),
  Color(0xFF1E88E5),
];
const List<int> startOffset = [0, 13, 26, 39];
const Set<int> safeSquares = {0, 8, 13, 21, 26, 34, 39, 47};
const int finishPos = 56;

const List<List<int>> trackCells = [
  [6, 1], [6, 2], [6, 3], [6, 4], [6, 5],
  [5, 6], [4, 6], [3, 6], [2, 6], [1, 6], [0, 6],
  [0, 7], [0, 8],
  [1, 8], [2, 8], [3, 8], [4, 8], [5, 8],
  [6, 9], [6, 10], [6, 11], [6, 12], [6, 13], [6, 14],
  [7, 14], [8, 14],
  [8, 13], [8, 12], [8, 11], [8, 10], [8, 9],
  [9, 8], [10, 8], [11, 8], [12, 8], [13, 8], [14, 8],
  [14, 7], [14, 6],
  [13, 6], [12, 6], [11, 6], [10, 6], [9, 6],
  [8, 5], [8, 4], [8, 3], [8, 2], [8, 1], [8, 0],
  [7, 0], [6, 0],
];

const List<List<List<int>>> homeCells = [
  [[7, 1], [7, 2], [7, 3], [7, 4], [7, 5]],
  [[1, 7], [2, 7], [3, 7], [4, 7], [5, 7]],
  [[7, 13], [7, 12], [7, 11], [7, 10], [7, 9]],
  [[13, 7], [12, 7], [11, 7], [10, 7], [9, 7]],
];

const List<Offset> yardOrigin = [Offset(0, 0), Offset(9, 0), Offset(9, 9), Offset(0, 9)];
const List<Offset> homeCenter = [Offset(6.7, 7.5), Offset(7.5, 6.7), Offset(8.3, 7.5), Offset(7.5, 8.3)];
const List<Offset> _yardSlots = [Offset(2, 2), Offset(4, 2), Offset(2, 4), Offset(4, 4)];

Offset _stepPoint(int color, int k) {
  if (k <= 50) {
    final c = trackCells[(startOffset[color] + k) % 52];
    return Offset(c[1] + 0.5, c[0] + 0.5);
  }
  if (k <= 55) {
    final c = homeCells[color][k - 51];
    return Offset(c[1] + 0.5, c[0] + 0.5);
  }
  return homeCenter[color];
}

Offset tokenPoint(int color, int index, double p) {
  if (p < 0) return yardOrigin[color] + _yardSlots[index];
  final lo = p.floor();
  final hi = p.ceil();
  final a = _stepPoint(color, lo);
  if (lo == hi) return a;
  return Offset.lerp(a, _stepPoint(color, hi), p - lo)!;
}
