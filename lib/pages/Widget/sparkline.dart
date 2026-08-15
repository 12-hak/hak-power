import 'package:flutter/material.dart';

class Sparkline extends StatelessWidget {
  const Sparkline({super.key, required this.values, this.color = const Color(0xFF7CFFB2)});

  final List<double> values;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _SparkPainter(values, color), child: const SizedBox.expand());
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    var min = values.first;
    var max = values.first;
    for (final v in values) {
      if (v < min) min = v;
      if (v > max) max = v;
    }
    final span = (max - min).abs() < 1 ? 1.0 : max - min;
    final path = Path();
    final fill = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - ((values[i] - min) / span) * (size.height * 0.82) - 4;
      if (i == 0) {
        path.moveTo(x, y);
        fill.moveTo(x, size.height);
        fill.lineTo(x, y);
      } else {
        path.lineTo(x, y);
        fill.lineTo(x, y);
      }
    }
    fill.lineTo(size.width, size.height);
    fill.close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.16));
    canvas.drawPath(
      path,
      Paint()
        ..color = color.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.values != values || old.color != color;
}

class TempSpark extends StatelessWidget {
  const TempSpark({super.key, required this.actual, required this.set});

  final List<double> actual;
  final List<double> set;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(painter: _TempSparkPainter(actual, set), child: const SizedBox.expand());
  }
}

class _TempSparkPainter extends CustomPainter {
  _TempSparkPainter(this.actual, this.set);
  final List<double> actual;
  final List<double> set;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 2 || size.height < 2) return;
    var center = 0.0;
    if (set.isNotEmpty) {
      center = set.last;
    } else if (actual.isNotEmpty) {
      center = actual.last;
    }
    var half = 5.0;
    void consider(List<double> vals) {
      for (final v in vals) {
        final d = (v - center).abs();
        if (d > half) half = d;
      }
    }

    consider(actual);
    consider(set);
    half = half < 5 ? 5.0 : half;
    final midY = size.height * 0.42;
    final amp = size.height * 0.34;

    canvas.drawLine(
      Offset(0, midY),
      Offset(size.width, midY),
      Paint()
        ..color = const Color(0x3344A0B0)
        ..strokeWidth = 1,
    );

    Path line(List<double> vals) {
      final path = Path();
      if (vals.isEmpty) return path;
      final count = vals.length < 2 ? 2 : vals.length;
      for (var i = 0; i < vals.length; i++) {
        final x = vals.length == 1 ? size.width / 2 : size.width * i / (count - 1);
        final y = midY - ((vals[i] - center) / half) * amp;
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      if (vals.length == 1) {
        path.moveTo(0, midY - ((vals.first - center) / half) * amp);
        path.lineTo(size.width, midY - ((vals.first - center) / half) * amp);
      }
      return path;
    }

    if (set.length >= 1) {
      canvas.drawPath(
        line(set),
        Paint()
          ..color = const Color(0xCC2EC7FF)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.8
          ..strokeJoin = StrokeJoin.round,
      );
    }
    if (actual.length >= 1) {
      final act = line(actual);
      final fill = Path.from(act)
        ..lineTo(size.width, midY)
        ..lineTo(0, midY)
        ..close();
      canvas.drawPath(fill, Paint()..color = const Color(0x227CFFB2));
      canvas.drawPath(
        act,
        Paint()
          ..color = const Color(0xDD7CFFB2)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..strokeJoin = StrokeJoin.round,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TempSparkPainter old) {
    return old.actual.length != actual.length ||
        old.set.length != set.length ||
        (actual.isNotEmpty && (old.actual.isEmpty || old.actual.last != actual.last)) ||
        (set.isNotEmpty && (old.set.isEmpty || old.set.last != set.last));
  }
}
