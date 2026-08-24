import 'package:flutter/material.dart';

import '../../modules/common/utils/juntek_tool.dart';

class JuntekFace extends StatelessWidget {
  const JuntekFace({super.key, required this.live, this.heard});

  final JuntekLive live;
  final String? heard;

  @override
  Widget build(BuildContext context) {
    final ok = live.status == 'live';
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: const Color(0xFF081014),
        border: Border.all(color: ok ? const Color(0xFF163038) : const Color(0xFF2A3034)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _pill(ok ? 'JUNTEK' : live.status.toUpperCase(), ok),
              if (heard != null) ...[
                const SizedBox(width: 6),
                Text(heard!, style: const TextStyle(color: Color(0xFF4A5A60), fontSize: 10)),
              ],
              const Spacer(),
              Text(
                live.charging == true ? 'CHG' : (live.charging == false ? 'DIS' : 'VA'),
                style: const TextStyle(color: Color(0xFF6A8088), fontSize: 11, letterSpacing: 0.8),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Expanded(
            child: Column(
              children: [
                Text(
                  live.volts != null ? live.volts!.toStringAsFixed(2) : '—',
                  style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.w300, height: 1),
                ),
                const Text('V', style: TextStyle(color: Color(0xFF2EC7FF), fontSize: 13, letterSpacing: 1.2)),
                const Spacer(),
                Row(
                  children: [
                    _kv('A', live.amps?.toStringAsFixed(2) ?? '—'),
                    _kv('W', live.watts?.toStringAsFixed(0) ?? '—'),
                    _kv('%', live.soc?.toStringAsFixed(0) ?? '—'),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  live.ahRemain != null ? '${live.ahRemain!.toStringAsFixed(1)} Ah' : '— Ah',
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w600),
                ),
                if (live.minutesLeft != null)
                  Text(
                    live.minutesLeft! >= 60
                        ? '${(live.minutesLeft! / 60).toStringAsFixed(1)} h left'
                        : '${live.minutesLeft} min left',
                    style: const TextStyle(color: Color(0xFF6A8088), fontSize: 11),
                  ),
                const Spacer(),
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

  Widget _kv(String k, String v) {
    return Expanded(
      child: Column(
        children: [
          Text(v, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700, height: 1)),
          const SizedBox(height: 2),
          Text(k, style: const TextStyle(color: Color(0xFF6A8088), fontSize: 10, letterSpacing: 0.8)),
        ],
      ),
    );
  }
}
