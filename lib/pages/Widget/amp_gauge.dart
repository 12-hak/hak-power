import 'dart:math' as math;

import 'package:flutter/material.dart';

double wattScaleFor(double? watts) {
  final w = (watts ?? 0).abs();
  if (w <= 40) return 50;
  if (w <= 80) return 100;
  if (w <= 160) return 200;
  if (w <= 400) return 500;
  if (w <= 800) return 1000;
  if (w <= 1600) return 2000;
  return 4000;
}

class AmpGauge extends StatelessWidget {
  const AmpGauge({super.key, this.watts, this.height = 58});

  final double? watts;
  final double height;

  @override
  Widget build(BuildContext context) {
    final known = watts != null;
    final value = watts ?? 0;
    final scale = wattScaleFor(watts);
    final idle = !known || value.abs() < 5;
    final charge = value > 5;
    final color = idle
        ? const Color(0xFF9AABB0)
        : (charge ? const Color(0xFF3DFF8A) : const Color(0xFFFF9F2E));
    final label = !known ? '— W' : '${value.abs().round()} W';
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Column(
        children: [
          Expanded(
            child: CustomPaint(
              painter: _WattmeterPainter(watts: known ? value : null, scale: scale, color: color),
              child: const SizedBox.expand(),
            ),
          ),
          Text(
            label,
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.4, height: 1),
          ),
        ],
      ),
    );
  }
}

class _WattmeterPainter extends CustomPainter {
  _WattmeterPainter({required this.watts, required this.scale, required this.color});

  final double? watts;
  final double scale;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final pivot = Offset(size.width / 2, size.height - 4);
    final radius = math.min(size.width / 2 - 12, size.height - 8);
    if (radius < 12) return;
    final rect = Rect.fromCircle(center: pivot, radius: radius);
    const start = math.pi;
    const sweep = math.pi;

    canvas.drawArc(
      rect,
      start,
      sweep / 2,
      false,
      Paint()
        ..color = const Color(0x55FF9F2E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      rect,
      start + sweep / 2,
      sweep / 2,
      false,
      Paint()
        ..color = const Color(0x553DFF8A)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 7
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawArc(
      rect,
      start,
      sweep,
      false,
      Paint()
        ..color = const Color(0xFF1A2A30)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );

    final tick = Paint()
      ..color = const Color(0xFF6A8088)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i <= 8; i++) {
      final t = i / 8;
      final ang = start + sweep * t;
      final long = i == 0 || i == 4 || i == 8;
      final outer = Offset(pivot.dx + math.cos(ang) * radius, pivot.dy + math.sin(ang) * radius);
      final inner = Offset(
        pivot.dx + math.cos(ang) * (radius - (long ? 7 : 4)),
        pivot.dy + math.sin(ang) * (radius - (long ? 7 : 4)),
      );
      canvas.drawLine(inner, outer, tick);
    }

    final caption = TextPainter(textDirection: TextDirection.ltr);
    void cap(String s, Offset o, Color c) {
      caption.text = TextSpan(
        text: s,
        style: TextStyle(color: c, fontSize: 8, fontWeight: FontWeight.w800, letterSpacing: 0.6),
      );
      caption.layout();
      caption.paint(canvas, Offset(o.dx - caption.width / 2, o.dy - caption.height / 2));
    }

    cap('DIS', Offset(pivot.dx - radius + 12, pivot.dy - 10), const Color(0xFFFF9F2E));
    cap('CHG', Offset(pivot.dx + radius - 12, pivot.dy - 10), const Color(0xFF3DFF8A));

    final t = ((watts ?? 0) / scale).clamp(-1.0, 1.0);
    final ang = start + sweep * ((t + 1) / 2);
    final tip = Offset(pivot.dx + math.cos(ang) * (radius - 9), pivot.dy + math.sin(ang) * (radius - 9));
    canvas.drawLine(
      pivot,
      tip,
      Paint()
        ..color = color
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(pivot, 2.4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_WattmeterPainter old) =>
      old.watts != watts || old.scale != scale || old.color != color;
}
