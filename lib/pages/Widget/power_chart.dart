import 'package:flutter/material.dart';

import '../../modules/common/utils/pack_history.dart';

class PowerChartPage extends StatelessWidget {
  const PowerChartPage({super.key, required this.title, required this.unit, required this.local});

  final String title;
  final String unit;
  final List<HistPoint> local;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07080A),
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SizedBox(height: 220, child: CustomPaint(painter: _Bars(local), child: const SizedBox.expand())),
          const SizedBox(height: 8),
          Text(
            local.isEmpty ? 'No samples yet' : '${local.length} pts  last ${local.last.v.toStringAsFixed(1)} $unit',
            style: const TextStyle(color: Color(0xFF2EC7FF)),
          ),
        ],
      ),
    );
  }
}

class _Bars extends CustomPainter {
  _Bars(this.points);
  final List<HistPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF111417);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)), bg);
    if (points.isEmpty) return;
    final max = points.map((p) => p.v).reduce((a, b) => a > b ? a : b);
    final span = max <= 0 ? 1.0 : max;
    final w = size.width / points.length;
    final bar = Paint()..color = const Color(0xFF2EC7FF);
    for (var i = 0; i < points.length; i++) {
      final h = (points[i].v / span) * (size.height - 16);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * w + 1, size.height - 8 - h, w - 2, h),
          const Radius.circular(2),
        ),
        bar,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Bars old) => old.points != points;
}
