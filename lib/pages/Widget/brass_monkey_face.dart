import 'dart:ui';

import 'package:flutter/material.dart';

import '../../modules/common/utils/fridge_protocol.dart';
import '../../modules/common/utils/pack_history.dart';
import 'sparkline.dart';

class BrassMonkeyFace extends StatelessWidget {
  const BrassMonkeyFace({
    super.key,
    required this.live,
    this.onLeft,
    this.onRight,
    this.onNudgeLeft,
    this.onNudgeRight,
  });

  final FridgeLive live;
  final VoidCallback? onLeft;
  final VoidCallback? onRight;
  final ValueChanged<int>? onNudgeLeft;
  final ValueChanged<int>? onNudgeRight;

  @override
  Widget build(BuildContext context) {
    final ok = live.status == 'live';
    final down = !ok && live.status != 'scan' && live.status != 'connecting' && !live.status.startsWith('bind');
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF081014),
        border: Border.all(color: down ? const Color(0xFFFF4D4D) : const Color(0xFF163038)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _pill(live.status == 'live' ? 'FRIDGE' : live.status.toUpperCase(), live.status == 'live'),
              if (live.on) ...[
                const SizedBox(width: 6),
                const Text(
                  'ON',
                  style: TextStyle(color: Color(0xFF7CFFB2), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.6),
                ),
              ],
              const Spacer(),
              Text(
                live.volts != null ? '${live.volts!.toStringAsFixed(1)} V' : 'BRASS MONKEY',
                style: const TextStyle(color: Color(0xFF6A8088), fontSize: 11, letterSpacing: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: _zone(
                    'TEMP LEFT',
                    live.leftC,
                    live.leftTarget,
                    live.unit,
                    SparkBuf.of('fridgeL'),
                    SparkBuf.of('fridgeLSet'),
                    onLeft,
                    onNudgeLeft,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _zone(
                    'TEMP RIGHT',
                    live.rightC,
                    live.rightTarget,
                    live.unit,
                    SparkBuf.of('fridgeR'),
                    SparkBuf.of('fridgeRSet'),
                    onRight,
                    onNudgeRight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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

  Widget _zone(
    String side,
    int? temp,
    int? target,
    String unit,
    List<double> actual,
    List<double> set,
    VoidCallback? onTap,
    ValueChanged<int>? onNudge,
  ) {
    final known = temp != null;
    final drift = known && target != null ? (temp - target).abs() : 0;
    final tempColor = drift > 10
        ? const Color(0xFFFF4D4D)
        : drift > 5
            ? const Color(0xFFFFB45A)
            : Colors.white;
    final shown = known ? '${temp.toString().padLeft(3)}°$unit' : '  —°$unit';
    final setText = target == null ? 'SET  --°' : 'SET ${target.toString().padLeft(3)}°';
    const tempStyle = TextStyle(
      fontSize: 36,
      fontWeight: FontWeight.w700,
      height: 1,
      fontFamily: 'monospace',
      fontFeatures: [FontFeature.tabularFigures()],
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const ColoredBox(color: Color(0xFF0E1A1E)),
          Positioned.fill(
            child: TempSpark(
              actual: List<double>.from(actual),
              set: List<double>.from(set),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                child: Row(
                  children: [
                    Text(
                      side,
                      style: const TextStyle(color: Color(0xFF7AA8B0), fontSize: 10, letterSpacing: 1.2),
                    ),
                    const Spacer(),
                    const Text(
                      '1H',
                      style: TextStyle(color: Color(0xFF3A4A50), fontSize: 9, letterSpacing: 0.8),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 76,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
                  child: Column(
                    children: [
                      GestureDetector(
                        onTap: onTap,
                        child: SizedBox(
                          height: 40,
                          width: double.infinity,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(shown, style: tempStyle.copyWith(color: tempColor)),
                          ),
                        ),
                      ),
                      SizedBox(
                        height: 30,
                        child: Row(
                          children: [
                            _step('-', onNudge == null ? null : () => onNudge(-1)),
                            Expanded(
                              child: Text(
                                setText,
                                textAlign: TextAlign.center,
                                maxLines: 1,
                                overflow: TextOverflow.clip,
                                style: const TextStyle(
                                  color: Color(0xFF2EC7FF),
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  height: 1,
                                  fontFamily: 'monospace',
                                  fontFeatures: [FontFeature.tabularFigures()],
                                ),
                              ),
                            ),
                            _step('+', onNudge == null ? null : () => onNudge(1)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _step(String label, VoidCallback? onTap) {
    return Material(
      color: onTap == null ? const Color(0x22182024) : const Color(0x332EC7FF),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 32,
          height: 30,
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: onTap == null ? const Color(0xFF3A4A50) : Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                height: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
