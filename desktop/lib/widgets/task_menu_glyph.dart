import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/workfollow_theme.dart';

/// Small vector glyphs sharing the same 24-unit grid and rounded stroke.
class TaskMenuGlyph extends StatelessWidget {
  const TaskMenuGlyph(this.kind,
      {super.key, required this.color, this.size = 20, this.filled = false});
  final String kind;
  final Color color;
  final double size;
  final bool filled;
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _MenuGlyphPainter(kind, color, filled)));
}

class _MenuGlyphPainter extends CustomPainter {
  const _MenuGlyphPainter(this.kind, this.color, this.filled);
  final String kind;
  final Color color;
  final bool filled;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double x1, double y1, double x2, double y2) =>
        canvas.drawLine(Offset(x1, y1), Offset(x2, y2), pen);
    void box(Rect rect, [double radius = 4]) => canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)), pen);
    void cross(double x, double y, double width) {
      line(x, y, x + width, y + width);
      line(x + width, y, x, y + width);
    }

    switch (kind) {
      case 'today':
      case 'tomorrow':
        final rising = kind == 'tomorrow';
        if (rising) {
          canvas.drawArc(
              const Rect.fromLTWH(6, 9, 12, 12), math.pi, math.pi, false, pen);
          line(3, 20, 21, 20);
          line(12, 2, 12, 6);
          line(9, 5, 12, 2);
          line(12, 2, 15, 5);
        } else {
          canvas.drawCircle(const Offset(12, 12), 6, pen);
        }
        for (var n = 0; n < 8; n++) {
          if (rising && (n < 4 || n == 6)) continue;
          final angle = n * math.pi / 4;
          final origin = rising ? const Offset(12, 15) : const Offset(12, 12);
          canvas.drawLine(origin + Offset(math.cos(angle), math.sin(angle)) * 9,
              origin + Offset(math.cos(angle), math.sin(angle)) * 11, pen);
        }
      case 'next-7':
      case 'date':
      case 'clear-date':
        box(const Rect.fromLTWH(2.5, 3, 19, 19));
        line(3, 7, 21, 7);
        if (kind == 'clear-date') {
          cross(9, 11, 6);
        } else if (kind == 'next-7') {
          final label = TextPainter(
              text: TextSpan(
                  text: '+7',
                  style: TextStyle(
                      fontFamily: WorkFollowMacTypeFamily.ui,
                      fontSize: WorkFollowMacTypography.caption,
                      fontWeight: WorkFollowMacWeight.semibold,
                      color: color)),
              textDirection: TextDirection.ltr)
            ..layout();
          label.paint(canvas, Offset((24 - label.width) / 2, 8.8));
        } else {
          for (final y in [11.5, 16.5]) {
            for (final x in [7.0, 12.0, 17.0]) {
              line(x - .6, y, x + .6, y);
            }
          }
        }
      case 'flag':
        line(4, 2, 4, 22);
        final flag = Path()
          ..moveTo(4, 3)
          ..lineTo(21, 3)
          ..lineTo(17, 9)
          ..lineTo(21, 15)
          ..lineTo(4, 15)
          ..close();
        canvas.drawPath(flag, filled ? (Paint()..color = color) : pen);
      case 'add-subtask':
        canvas.drawPath(
            Path()
              ..moveTo(4, 3)
              ..lineTo(4, 14)
              ..quadraticBezierTo(4, 18, 8, 18)
              ..lineTo(16, 18),
            pen);
        line(4, 7, 16, 7);
        canvas.drawCircle(const Offset(20, 7), 1.6, Paint()..color = color);
        canvas.drawCircle(const Offset(20, 18), 1.6, Paint()..color = color);
      case 'pin':
        line(3, 2, 21, 2);
        canvas.drawPath(
            Path()
              ..moveTo(12, 5)
              ..lineTo(20, 13)
              ..lineTo(15.5, 13)
              ..lineTo(15.5, 21)
              ..lineTo(8.5, 21)
              ..lineTo(8.5, 13)
              ..lineTo(4, 13)
              ..close(),
            pen);
      case 'abandon':
        box(const Rect.fromLTWH(3, 3, 18, 18));
        cross(8, 8, 8);
      case 'list':
        box(const Rect.fromLTWH(2, 6, 20, 15));
        line(6, 3, 18, 3);
        line(7, 13, 17, 13);
        line(14, 10, 17, 13);
        line(17, 13, 14, 16);
      case 'tags':
        canvas.drawPath(
            Path()
              ..moveTo(3, 3)
              ..lineTo(12, 3)
              ..lineTo(22, 13)
              ..quadraticBezierTo(23, 14, 22, 15)
              ..lineTo(15, 22)
              ..quadraticBezierTo(14, 23, 13, 22)
              ..lineTo(3, 12)
              ..close(),
            pen);
        canvas.drawCircle(const Offset(8, 8), 1.6, pen);
      case 'convert-note':
        box(const Rect.fromLTWH(4, 2, 16, 20), 3);
        canvas.drawPath(
            Path()
              ..moveTo(9, 2)
              ..lineTo(9, 10)
              ..lineTo(12, 8)
              ..lineTo(15, 10)
              ..lineTo(15, 2),
            pen);
        line(8, 17, 16, 17);
      case 'delete':
        line(2, 6, 22, 6);
        box(const Rect.fromLTWH(8, 2, 8, 4), 1.5);
        canvas.drawPath(
            Path()
              ..moveTo(5, 6)
              ..lineTo(6, 20)
              ..quadraticBezierTo(6, 22, 8, 22)
              ..lineTo(16, 22)
              ..quadraticBezierTo(18, 22, 18, 20)
              ..lineTo(19, 6),
            pen);
        line(10, 10, 10, 18);
        line(14, 10, 14, 18);
    }
  }

  @override
  bool shouldRepaint(covariant _MenuGlyphPainter old) =>
      kind != old.kind || color != old.color || filled != old.filled;
}
