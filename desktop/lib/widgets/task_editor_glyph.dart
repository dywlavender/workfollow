import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../theme/workfollow_theme.dart';

/// Thin, rounded 24-unit glyphs for the compact document popovers.
class TaskEditorGlyph extends StatelessWidget {
  const TaskEditorGlyph(this.kind,
      {super.key, required this.color, this.size = 18});
  final String kind;
  final Color color;
  final double size;
  @override
  Widget build(BuildContext context) => SizedBox.square(
      dimension: size, child: CustomPaint(painter: _Glyph(kind, color)));
}

class _Glyph extends CustomPainter {
  const _Glyph(this.kind, this.color);
  final String kind;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final extent = math.min(size.width, size.height);
    canvas.translate((size.width - extent) / 2, (size.height - extent) / 2);
    canvas.scale(extent / 24);
    final pen = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.65
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    void line(double a, double b, double c, double d) =>
        canvas.drawLine(Offset(a, b), Offset(c, d), pen);
    void label(String value, double x, double y, double fontSize,
        {FontWeight weight = WorkFollowMacWeight.regular}) {
      final painter = TextPainter(
          text: TextSpan(
              text: value,
              style: TextStyle(
                  fontFamily: WorkFollowMacTypeFamily.ui,
                  fontFamilyFallback: WorkFollowMacTypeFamily.fallback,
                  fontSize: fontSize,
                  height: 1,
                  fontWeight: weight,
                  color: color)),
          textDirection: TextDirection.ltr)
        ..layout();
      painter.paint(canvas, Offset(x, y));
    }

    switch (kind) {
      case 'search':
        canvas.drawCircle(const Offset(10, 10), 7, pen);
        line(15, 15, 21, 21);
      case 'inbox':
        canvas.drawPath(
            Path()
              ..moveTo(3, 12)
              ..lineTo(6, 5)
              ..quadraticBezierTo(6.5, 4, 8, 4)
              ..lineTo(16, 4)
              ..quadraticBezierTo(17.5, 4, 18, 5)
              ..lineTo(21, 12)
              ..lineTo(21, 19)
              ..quadraticBezierTo(21, 21, 19, 21)
              ..lineTo(5, 21)
              ..quadraticBezierTo(3, 21, 3, 19)
              ..close(),
            pen);
        canvas.drawPath(
            Path()
              ..moveTo(3, 13)
              ..lineTo(8, 13)
              ..lineTo(9.5, 16)
              ..lineTo(14.5, 16)
              ..lineTo(16, 13)
              ..lineTo(21, 13),
            pen);
      case 'menu':
        for (final y in [5.0, 12.0, 19.0]) line(3, y, 21, y);
      case 'check':
        line(4, 13, 10, 19);
        line(10, 19, 21, 4);
      case 'clock':
      case 'alarm':
      case 'time':
        if (kind == 'time') {
          canvas.drawArc(const Rect.fromLTWH(4, 3, 18, 18), -math.pi * .8,
              math.pi * 1.7, false, pen);
          line(2, 6, 2, 11);
          line(2, 11, 7, 11);
        } else {
          canvas.drawCircle(const Offset(12, 12), 8, pen);
          if (kind == 'alarm') {
            line(3, 5, 6, 2);
            line(18, 2, 21, 5);
            line(6, 20, 4, 22);
            line(18, 20, 20, 22);
          }
        }
        line(12, 7, 12, 13);
        line(12, 13, 16, 13);
      case 'next-7':
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(3, 3, 18, 19), const Radius.circular(4)),
            pen);
        line(3, 7, 21, 7);
        line(7, 13, 11, 13);
        line(9, 11, 9, 15);
        line(13, 11, 17, 11);
        line(17, 11, 14, 18);
      case 'repeat-end':
        canvas.drawArc(
            const Rect.fromLTWH(3, 3, 16, 16), -math.pi, math.pi, false, pen);
        line(19, 3, 19, 8);
        line(19, 8, 14, 8);
        canvas.drawArc(const Rect.fromLTWH(3, 3, 16, 16), math.pi / 2,
            math.pi / 2, false, pen);
        line(3, 19, 3, 14);
        line(3, 14, 8, 14);
        line(16, 16, 21, 21);
        line(21, 16, 16, 21);
      case 'repeat':
        canvas.drawArc(
            const Rect.fromLTWH(4, 4, 16, 16), -math.pi, math.pi, false, pen);
        line(20, 4, 20, 9);
        line(20, 9, 15, 9);
        canvas.drawArc(
            const Rect.fromLTWH(4, 4, 16, 16), 0, math.pi, false, pen);
        line(4, 20, 4, 15);
        line(4, 15, 9, 15);
      case 'moon':
        canvas.drawPath(
            Path()
              ..moveTo(10, 2)
              ..cubicTo(8, 10, 14, 17, 22, 15)
              ..cubicTo(18, 27, 1, 23, 2, 12)
              ..cubicTo(2, 7, 5, 3, 10, 2),
            pen);
      case 'bold':
        label('B', 5, 1, 22, weight: WorkFollowMacWeight.semibold);
      case 'italic':
        line(10, 3, 18, 3);
        line(6, 21, 14, 21);
        line(14, 3, 10, 21);
      case 'underline':
        canvas.drawPath(
            Path()
              ..moveTo(6, 3)
              ..lineTo(6, 13)
              ..cubicTo(6, 21, 18, 21, 18, 13)
              ..lineTo(18, 3),
            pen);
        line(4, 22, 20, 22);
      case 'strike':
        canvas.drawPath(
            Path()
              ..moveTo(18, 6)
              ..cubicTo(15, 1, 6, 2, 6, 7)
              ..cubicTo(6, 10, 10, 10, 13, 12)
              ..moveTo(17, 15)
              ..cubicTo(23, 24, 6, 26, 5, 18),
            pen);
        line(2, 12, 22, 12);
      case 'checklist':
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(3, 3, 18, 18), const Radius.circular(4)),
            pen);
        line(7, 12, 10, 15);
        line(10, 15, 17, 8);
      case 'bullet':
      case 'ordered':
        for (var i = 0; i < 3; i++) {
          final y = 5.0 + i * 7;
          if (kind == 'bullet')
            canvas.drawCircle(Offset(3, y), 1.2, Paint()..color = color);
          else
            label('${i + 1}', 0, y - 4, 8);
          line(8, y, 22, y);
        }
      case 'divider':
        line(3, 12, 21, 12);
        for (final y in [5.0, 19.0])
          for (final x in [3.0, 10.0, 17.0]) line(x, y, x + 3, y);
      case 'link':
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(-math.pi / 4);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(-11, -4, 12, 8), const Radius.circular(4)),
            pen);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(-1, -4, 12, 8), const Radius.circular(4)),
            pen);
        canvas.restore();
      case 'code':
        line(7, 6, 2, 12);
        line(2, 12, 7, 18);
        line(17, 6, 22, 12);
        line(22, 12, 17, 18);
        line(14, 3, 10, 21);
      case 'quote':
        for (final x in [3.0, 8.0]) {
          canvas.drawPath(
              Path()
                ..moveTo(x + 3, 4)
                ..quadraticBezierTo(x, 5, x, 9)
                ..lineTo(x + 3, 9)
                ..lineTo(x + 3, 6),
              pen);
        }
        for (final x in [15.0, 20.0]) {
          canvas.drawPath(
              Path()
                ..moveTo(x, 20)
                ..quadraticBezierTo(x + 3, 19, x + 3, 15)
                ..lineTo(x, 15)
                ..lineTo(x, 18),
              pen);
        }
      case 'attachment':
        canvas.save();
        canvas.translate(12, 12);
        canvas.rotate(math.pi / 4);
        canvas.translate(-12, -12);
        canvas.drawPath(
            Path()
              ..moveTo(18, 9)
              ..lineTo(18, 16)
              ..cubicTo(18, 26, 4, 26, 4, 16)
              ..lineTo(4, 7)
              ..cubicTo(4, -1, 15, -1, 15, 7)
              ..lineTo(15, 16)
              ..cubicTo(15, 20, 9, 20, 9, 16)
              ..lineTo(9, 7),
            pen);
        canvas.restore();
      case 'chevron':
        line(9, 6, 15, 12);
        line(15, 12, 9, 18);
    }
  }

  @override
  bool shouldRepaint(covariant _Glyph oldDelegate) =>
      kind != oldDelegate.kind || color != oldDelegate.color;
}
