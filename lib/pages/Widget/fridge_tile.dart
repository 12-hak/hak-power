import 'package:flutter/material.dart';

class FridgeTile extends StatelessWidget {
  const FridgeTile({
    super.key,
    required this.leftC,
    required this.rightC,
    required this.unit,
    this.onTap,
    this.online = true,
  });

  final int? leftC;
  final int? rightC;
  final String unit;
  final bool online;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
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
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            children: [
              const Text(
                'BRASS MONKEY',
                style: TextStyle(color: Color(0xFFD4E2E8), fontSize: 12, letterSpacing: 1.3, fontWeight: FontWeight.w700),
              ),
              Expanded(
                child: Row(
                  children: [
                    _temp('L', leftC),
                    const SizedBox(width: 8),
                    _temp('R', rightC),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _temp(String side, int? temp) {
    return Expanded(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(side, style: const TextStyle(color: Color(0xFF6A8088), fontSize: 12, letterSpacing: 1.2)),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              temp != null ? '$temp°$unit' : '—°$unit',
              style: TextStyle(
                color: temp != null ? Colors.white : const Color(0xFF3A4A50),
                fontSize: 40,
                fontWeight: FontWeight.w300,
                height: 1,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
