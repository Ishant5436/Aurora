import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/tokens.dart';

/// The Florence cathedral illustration. Drop `florence.jpg` into
/// `assets/images/` to use the original artwork; until then a drawn silhouette
/// of the dome stands in, so the app never depends on the file being present.
class HeroArt extends StatelessWidget {
  const HeroArt({super.key, this.opacity = 0.15, this.alignment = Alignment.topCenter});

  final double opacity;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: opacity,
      child: Image.asset(
        'assets/images/florence.jpg',
        fit: BoxFit.cover,
        alignment: alignment,
        width: double.infinity,
        height: double.infinity,
        errorBuilder: (context, error, stack) => CustomPaint(
          size: Size.infinite,
          painter: _DuomoPainter(context.colors.primary),
        ),
      ),
    );
  }
}

class _DuomoPainter extends CustomPainter {
  const _DuomoPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;
    final base = h * 0.97;
    final line = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final fill = Paint()..color = color.withValues(alpha: 0.35);

    void block(Rect r) {
      canvas.drawRect(r, fill);
      canvas.drawRect(r, line);
    }

    block(Rect.fromLTWH(cx - w * 0.30, base - h * 0.2, w * 0.60, h * 0.2));
    block(Rect.fromLTWH(cx - w * 0.21, base - h * 0.32, w * 0.42, h * 0.12));

    final dome = Rect.fromCenter(center: Offset(cx, base - h * 0.32), width: w * 0.42, height: h * 0.34);
    canvas.drawArc(dome, math.pi, math.pi, true, fill);
    canvas.drawArc(dome, math.pi, math.pi, false, line);
    for (var i = -2; i <= 2; i++) {
      canvas.drawLine(Offset(cx + i * w * 0.08, base - h * 0.32), Offset(cx, base - h * 0.49), line);
    }

    block(Rect.fromLTWH(cx - w * 0.025, base - h * 0.57, w * 0.05, h * 0.08));
    canvas.drawLine(Offset(cx, base - h * 0.57), Offset(cx, base - h * 0.62), line);
    canvas.drawLine(Offset(cx - w * 0.012, base - h * 0.60), Offset(cx + w * 0.012, base - h * 0.60), line);

    for (final x in [0.1, 0.18, 0.82, 0.9]) {
      canvas.drawOval(
        Rect.fromCenter(center: Offset(w * x, base - h * 0.15), width: w * 0.07, height: h * 0.3),
        fill,
      );
    }
  }

  @override
  bool shouldRepaint(_DuomoPainter old) => old.color != color;
}
