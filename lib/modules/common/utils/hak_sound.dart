import 'dart:async';

import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

class HakCamp {
  HakCamp._();
  static final instance = HakCamp._();
  bool night = false;
  bool keepOn = false;
  final _ctrl = StreamController<void>.broadcast();
  Stream<void> get stream => _ctrl.stream;

  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    night = p.getBool('hak-night') ?? false;
    keepOn = p.getBool('hak-keep-on') ?? false;
    await HakSound.keepOn(keepOn);
    _ctrl.add(null);
  }

  Future<void> setNight(bool v) async {
    night = v;
    await (await SharedPreferences.getInstance()).setBool('hak-night', v);
    _ctrl.add(null);
  }

  Future<void> setKeepOn(bool v) async {
    keepOn = v;
    await (await SharedPreferences.getInstance()).setBool('hak-keep-on', v);
    await HakSound.keepOn(v);
    _ctrl.add(null);
  }
}

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

  static Future<void> keepOn(bool on) async {
    try {
      await _c.invokeMethod<void>('keepOn', {'on': on});
    } catch (_) {}
  }

  static Future<void> watchFridge({required bool on, DateTime? heard}) async {
    try {
      await _c.invokeMethod<void>('watchFridge', {
        'on': on,
        'heard': heard?.millisecondsSinceEpoch ?? 0,
      });
    } catch (_) {}
  }

  static Future<void> fridgeHeard([DateTime? t]) async {
    try {
      await _c.invokeMethod<void>('fridgeHeard', {
        'at': (t ?? DateTime.now()).millisecondsSinceEpoch,
      });
    } catch (_) {}
  }

  static Future<void> muteFridge(bool on) async {
    try {
      await _c.invokeMethod<void>('muteFridge', {'on': on});
    } catch (_) {}
  }

  static Future<void> exitApp() async {
    try {
      await _c.invokeMethod<void>('exitApp');
    } catch (_) {
      await SystemNavigator.pop();
    }
  }
}
