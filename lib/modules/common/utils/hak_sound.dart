import 'package:flutter/services.dart';

class HakSound {
  static const _c = MethodChannel('hak/sound');
  static DateTime? _lastBuzz;
  static DateTime? _lastTick;

  static Future<void> buzz() async {
    final now = DateTime.now();
    if (_lastBuzz != null && now.difference(_lastBuzz!) < const Duration(seconds: 2)) return;
    _lastBuzz = now;
    try {
      await HapticFeedback.heavyImpact();
    } catch (_) {}
    try {
      await SystemSound.play(SystemSoundType.alert);
    } catch (_) {}
    try {
      await _c.invokeMethod<void>('buzz');
    } catch (_) {}
  }

  static Future<void> tick() async {
    final now = DateTime.now();
    if (_lastTick != null && now.difference(_lastTick!) < const Duration(seconds: 12)) return;
    _lastTick = now;
    try {
      await HapticFeedback.selectionClick();
    } catch (_) {}
    try {
      await _c.invokeMethod<void>('tick');
    } catch (_) {}
  }
}
