import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const _roman = ['XII', 'I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI'];

/// The slowly turning dial with Roman numerals shown behind the ringing time.
class RomanDial extends StatelessWidget {
  const RomanDial({super.key, required this.size, required this.color, this.turns = 0});

  final double size;
  final Color color;

  /// Rotation in full turns (0..1), driven by an animation.
  final double turns;

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: turns * 2 * math.pi,
      child: CustomPaint(size: Size.square(size), painter: _DialPainter(color)),
    );
  }
}

class _DialPainter extends CustomPainter {
  const _DialPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 200; // the design is drawn on a 200 x 200 grid
    final center = size.center(Offset.zero);

    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6 * scale;
    canvas.drawCircle(center, 96 * scale, ring);

    // Dotted inner ring: 2-on, 4-off along the circumference.
    final dotted = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5 * scale;
    final inner = Rect.fromCircle(center: center, radius: 86 * scale);
    const dashes = 90;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(inner, i * 2 * math.pi / dashes, 2 * math.pi / dashes / 3, false, dotted);
    }

    for (var i = 0; i < _roman.length; i++) {
      final tp = TextPainter(
        text: TextSpan(text: _roman[i], style: Typo.display(9 * scale, color: color, letterSpacing: 0)),
        textDirection: TextDirection.ltr,
      )..layout();
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(i * math.pi / 6);
      tp.paint(canvas, Offset(-tp.width / 2, -78 * scale - tp.height * 0.8));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.color != color;
}

/// Tick marks around the microphone button on the voice screen.
class TickRing extends StatelessWidget {
  const TickRing({super.key, required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) => CustomPaint(size: Size.square(size), painter: _TickPainter(color));
}

class _TickPainter extends CustomPainter {
  const _TickPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final scale = size.width / 200;
    final center = size.center(Offset.zero);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.6 * scale;
    canvas.drawCircle(center, 96 * scale, paint);
    paint.strokeWidth = 1 * scale;
    for (var i = 0; i < 24; i++) {
      final angle = i * math.pi / 12;
      final outer = center + Offset(math.sin(angle), -math.cos(angle)) * (94 * scale);
      final innerLen = (i.isOdd ? 88 : 84) * scale;
      final inner = center + Offset(math.sin(angle), -math.cos(angle)) * innerLen;
      canvas.drawLine(outer, inner, paint);
    }
  }

  @override
  bool shouldRepaint(_TickPainter old) => old.color != color;
}
