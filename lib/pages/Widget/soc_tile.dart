import 'package:flutter/material.dart';

import 'amp_gauge.dart';
import 'circle_ring_painter.dart';

class SocTile extends StatelessWidget {
  const SocTile({
    super.key,
    required this.label,
    required this.soc,
    this.onTap,
    this.subtitle,
    this.watts,
    this.online = true,
  });

  final String label;
  final double? soc;
  final String? subtitle;
  final double? watts;
  final bool online;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final known = soc != null;
    final value = soc ?? 0;
    final ring = online ? socColor(value) : const Color(0xFF5A656A);
    return Material(
      color: const Color(0xFF081014),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(width: 1, color: online ? const Color(0xFF7A9AA4) : const Color(0xFF2A3438)),
          ),
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(color: Color(0xFFD4E2E8), fontSize: 12, letterSpacing: 1.3, fontWeight: FontWeight.w700),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, c) {
                    final side = (c.maxWidth < c.maxHeight ? c.maxWidth : c.maxHeight).clamp(64.0, 156.0);
                    return Center(
                      child: SizedBox(
                        width: side,
                        height: side,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            CustomPaint(
                              size: Size(side, side),
                              painter: CircleRingPainter(progress: value / 100, known: known, color: ring),
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  known ? value.toStringAsFixed(0) : '—',
                                  style: TextStyle(
                                    fontSize: side * 0.28,
                                    fontWeight: FontWeight.w300,
                                    height: 1,
                                    letterSpacing: -1.2,
                                    color: known ? Colors.white : const Color(0xFF3A4A50),
                                  ),
                                ),
                                Text(
                                  '%',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                    letterSpacing: 1.4,
                                    color: known ? ring : const Color(0xFF3A4A50),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              AmpGauge(watts: watts),
              if (subtitle != null)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(subtitle!, style: const TextStyle(color: Color(0xFF8A9AA0), fontSize: 11)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
