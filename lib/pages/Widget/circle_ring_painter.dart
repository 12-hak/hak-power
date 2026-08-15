import 'dart:math' as math;

import 'package:flutter/material.dart';

Color socColor(double soc) {
  if (soc <= 20) return const Color(0xFFFF4D4D);
  if (soc <= 40) return const Color(0xFFFF9F2E);
  return const Color(0xFF3DFF8A);
}

class CircleRingPainter extends CustomPainter {
  CircleRingPainter({required this.progress, this.known = false, required this.color});

  final double progress;
  final bool known;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2 - 10;
    final rect = Rect.fromCircle(center: c, radius: r);
    const start = -math.pi / 2;
    final sweep = 2 * math.pi * (known ? progress.clamp(0.0, 1.0) : 0);

    canvas.drawCircle(
      c,
      r - 2,
      Paint()..color = const Color(0xFF071014),
    );
    canvas.drawArc(
      rect,
      0,
      2 * math.pi,
      false,
      Paint()
        ..color = const Color(0xFF1A2A30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 8
        ..strokeCap = StrokeCap.round,
    );
    if (sweep <= 0) return;
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..color = color.withValues(alpha: 0.28)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 16
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8),
    );
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(CircleRingPainter old) =>
      old.progress != progress || old.known != known || old.color != color;
}
