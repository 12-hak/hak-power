import 'package:flutter/material.dart';

import '../../modules/common/utils/pack_history.dart';

class PowerChartPage extends StatefulWidget {
  const PowerChartPage({super.key, required this.title, required this.unit, required this.local});

  final String title;
  final String unit;
  final List<HistPoint> local;

  @override
  State<PowerChartPage> createState() => _PowerChartPageState();
}

class _PowerChartPageState extends State<PowerChartPage> {
  Duration range = const Duration(hours: 6);

  List<HistPoint> get _cut {
    final now = DateTime.now().millisecondsSinceEpoch;
    return widget.local.where((p) => now - p.t <= range.inMilliseconds).toList();
  }

  String _clock(int ms) {
    final t = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final pts = _cut;
    final vals = pts.map((p) => p.v);
    final minV = vals.isEmpty ? 0.0 : vals.reduce((a, b) => a < b ? a : b);
    final maxV = vals.isEmpty ? 0.0 : vals.reduce((a, b) => a > b ? a : b);
    return Scaffold(
      backgroundColor: const Color(0xFF07080A),
      appBar: AppBar(backgroundColor: Colors.transparent, title: Text(widget.title)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Row(
            children: [
              for (final d in const [Duration(hours: 1), Duration(hours: 6), Duration(hours: 24)])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text('${d.inHours}h'),
                    selected: range == d,
                    onSelected: (_) => setState(() => range = d),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(height: 240, child: CustomPaint(painter: _Line(pts), child: const SizedBox.expand())),
          const SizedBox(height: 8),
          if (pts.isEmpty)
            const Text('No samples yet', style: TextStyle(color: Color(0xFF2EC7FF)))
          else
            Text(
              'min ${minV.toStringAsFixed(1)}  max ${maxV.toStringAsFixed(1)}  last ${pts.last.v.toStringAsFixed(1)} ${widget.unit}'
              '   ${_clock(pts.first.t)}–${_clock(pts.last.t)}',
              style: const TextStyle(color: Color(0xFF2EC7FF)),
            ),
        ],
      ),
    );
  }
}

class _Line extends CustomPainter {
  _Line(this.points);
  final List<HistPoint> points;

  @override
  void paint(Canvas canvas, Size size) {
    final bg = Paint()..color = const Color(0xFF111417);
    canvas.drawRRect(RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(12)), bg);
    if (points.isEmpty) return;
    final minV = points.map((p) => p.v).reduce((a, b) => a < b ? a : b);
    final maxV = points.map((p) => p.v).reduce((a, b) => a > b ? a : b);
    final span = (maxV - minV).abs() < 0.01 ? 1.0 : maxV - minV;
    final pad = 16.0;
    final inner = Rect.fromLTWH(pad, 12, size.width - pad * 2, size.height - 28);
    Offset at(int i) {
      final x = points.length == 1 ? inner.center.dx : inner.left + inner.width * i / (points.length - 1);
      final y = inner.bottom - ((points[i].v - minV) / span) * inner.height;
      return Offset(x, y);
    }

    final grid = Paint()
      ..color = const Color(0x22FFFFFF)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(inner.left, inner.top), Offset(inner.right, inner.top), grid);
    canvas.drawLine(Offset(inner.left, inner.bottom), Offset(inner.right, inner.bottom), grid);

    final path = Path()..moveTo(at(0).dx, at(0).dy);
    for (var i = 1; i < points.length; i++) {
      path.lineTo(at(i).dx, at(i).dy);
    }
    final line = Paint()
      ..color = const Color(0xFF2EC7FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeJoin = StrokeJoin.round;
    canvas.drawPath(path, line);

    final tp = TextPainter(textDirection: TextDirection.ltr);
    void label(String s, Offset o, {Alignment align = Alignment.centerLeft}) {
      tp.text = TextSpan(text: s, style: const TextStyle(color: Color(0xFF6A8088), fontSize: 10));
      tp.layout();
      final dx = align == Alignment.centerRight ? o.dx - tp.width : o.dx;
      tp.paint(canvas, Offset(dx, o.dy));
    }

    label(maxV.toStringAsFixed(0), Offset(inner.left, 0));
    label(minV.toStringAsFixed(0), Offset(inner.left, inner.bottom - 2));
    final first = DateTime.fromMillisecondsSinceEpoch(points.first.t);
    final last = DateTime.fromMillisecondsSinceEpoch(points.last.t);
    String hh(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    label(hh(first), Offset(inner.left, size.height - 14));
    label(hh(last), Offset(inner.right, size.height - 14), align: Alignment.centerRight);
  }

  @override
  bool shouldRepaint(covariant _Line old) => old.points != points;
}
