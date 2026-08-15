import 'package:flutter/material.dart';

import '../../modules/common/utils/ble_tool.dart';
import '../../modules/common/utils/pack_history.dart';
import 'circle_ring_painter.dart';
import 'sparkline.dart';

class BaseDeviceHome extends StatelessWidget {
  const BaseDeviceHome({
    super.key,
    required this.live,
    required this.timeLabel,
    required this.lightLabel,
    this.heard,
    this.source,
    this.today,
    this.onSoc,
    this.onPvIn,
    this.onAcIn,
    this.onDcOut,
    this.onAcOut,
    this.online = true,
  });

  final PackLive live;
  final bool online;
  final String timeLabel;
  final String lightLabel;
  final String? heard;
  final String? source;
  final String? today;
  final VoidCallback? onSoc;
  final VoidCallback? onPvIn;
  final VoidCallback? onAcIn;
  final VoidCallback? onDcOut;
  final VoidCallback? onAcOut;

  @override
  Widget build(BuildContext context) {
    final socKnown = live.soc != null;
    final soc = live.soc ?? 0;
    final ring = online ? socColor(soc) : const Color(0xFF5A656A);
    final face = Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF081014),
        border: Border.all(color: online ? const Color(0xFF163038) : const Color(0xFF2A3034)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _pill(online ? 'LIVE' : 'OFFLINE', online),
              if (heard != null) ...[
                const SizedBox(width: 6),
                Text(heard!, style: const TextStyle(color: Color(0xFF4A5A60), fontSize: 10)),
              ],
              if (source != null) ...[
                const SizedBox(width: 6),
                Text(source!, style: const TextStyle(color: Color(0xFF6A8088), fontSize: 10, letterSpacing: 0.6)),
              ],
              const Spacer(),
              Text(
                timeLabel,
                style: const TextStyle(color: Color(0xFF6A8088), fontSize: 11, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      _watt('AC IN', live.acIn, 'acIn', onAcIn, _inTint),
                      const SizedBox(height: 8),
                      _watt('PV / CAR IN', live.pvIn, 'pvIn', onPvIn, _inTint),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 168,
                  child: Column(
                    children: [
                      const Spacer(),
                      GestureDetector(
                        onTap: onSoc,
                        child: SizedBox(
                          width: 148,
                          height: 148,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              CustomPaint(
                                size: const Size(148, 148),
                                painter: CircleRingPainter(progress: soc / 100, known: socKnown, color: ring),
                              ),
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    socKnown ? soc.toStringAsFixed(0) : '—',
                                    style: TextStyle(
                                      fontSize: 44,
                                      fontWeight: FontWeight.w300,
                                      height: 1,
                                      letterSpacing: -1.2,
                                      color: socKnown ? Colors.white : const Color(0xFF3A4A50),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '%',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      letterSpacing: 1.4,
                                      color: socKnown ? ring : const Color(0xFF3A4A50),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        live.remainWh != null ? '${live.remainWh} Wh' : '— Wh',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.4,
                        ),
                      ),
                      if (lightLabel != '—')
                        Text(
                          lightLabel,
                          style: const TextStyle(
                            color: Color(0xFF2EC7FF),
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.3,
                          ),
                        ),
                      if (today != null)
                        Text(
                          today!,
                          style: const TextStyle(color: Color(0xFF4A5A60), fontSize: 10),
                        ),
                      const Spacer(),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      _watt('AC OUT', live.acOut, 'acOut', onAcOut, _outTint),
                      const SizedBox(height: 8),
                      _watt('DC OUT', live.dcOut, 'dcOut', onDcOut, _outTint),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    if (online) return face;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.21, 0.72, 0.07, 0, 0,
        0.21, 0.72, 0.07, 0, 0,
        0.21, 0.72, 0.07, 0, 0,
        0, 0, 0, 0.62, 0,
      ]),
      child: face,
    );
  }

  Widget _pill(String text, bool on) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: on ? const Color(0x332EC7FF) : const Color(0x221A2A30),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: on ? const Color(0xFF2EC7FF) : const Color(0xFF4A5A60),
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
    );
  }

  static const _inTint = Color(0xFF2EC7FF);
  static const _outTint = Color(0xFFFF9A3C);

  Widget _watt(String label, int? watts, String series, VoidCallback? onTap, Color tint) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: Color.alphaBlend(tint.withValues(alpha: 0.08), const Color(0xFF0E1A1E)))),
              Positioned.fill(child: Sparkline(values: SparkBuf.of(series), color: tint)),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 3,
                          height: 3,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(color: tint.withValues(alpha: 0.8), shape: BoxShape.circle),
                        ),
                        Flexible(
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: tint.withValues(alpha: 0.85), fontSize: 10, letterSpacing: 0.6),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: '${watts ?? 0}',
                            style: TextStyle(
                              color: Color.alphaBlend(tint.withValues(alpha: 0.35), Colors.white),
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              height: 1,
                            ),
                          ),
                          TextSpan(
                            text: ' W',
                            style: TextStyle(color: tint.withValues(alpha: 0.7), fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
