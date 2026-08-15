import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class HistPoint {
  HistPoint(this.t, this.v, {this.label});
  final int t;
  final double v;
  final String? label;
}

class SparkBuf {
  static const _max = 48;
  static final data = <String, List<double>>{};
  static final _at = <String, int>{};

  static void add(String key, double? value, {int max = _max, int gapMs = 0}) {
    if (value == null || !value.isFinite) return;
    final list = data.putIfAbsent(key, () => <double>[]);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (gapMs > 0 && list.isNotEmpty && _at[key] != null && now - _at[key]! < gapMs) {
      list[list.length - 1] = value;
      return;
    }
    _at[key] = now;
    list.add(value);
    if (list.length > max) list.removeRange(0, list.length - max);
  }

  static List<double> of(String key) => data[key] ?? const [];
}

class EnergyDay {
  static const _key = 's2200-energy-day';
  static String? day;
  static double inWh = 0;
  static double outWh = 0;
  static DateTime? _at;
  static bool _dirty = false;

  static Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) return;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      day = map['day'] as String?;
      inWh = (map['in'] as num?)?.toDouble() ?? 0;
      outWh = (map['out'] as num?)?.toDouble() ?? 0;
    } catch (_) {}
  }

  static void add(int? acIn, int? pvIn, int? acOut, int? dcOut) {
    final now = DateTime.now();
    final stamp = '${now.year}-${now.month}-${now.day}';
    if (day != stamp) {
      day = stamp;
      inWh = 0;
      outWh = 0;
    }
    if (_at != null) {
      final h = now.difference(_at!).inMilliseconds / 3600000.0;
      if (h > 0 && h < 0.08) {
        inWh += ((acIn ?? 0) + (pvIn ?? 0)) * h;
        outWh += ((acOut ?? 0) + (dcOut ?? 0)) * h;
        _dirty = true;
      }
    }
    _at = now;
  }

  static Future<void> flush() async {
    if (!_dirty) return;
    _dirty = false;
    final p = await SharedPreferences.getInstance();
    await p.setString(_key, jsonEncode({'day': day, 'in': inWh, 'out': outWh}));
  }

  static String hoursLeft(int? remainWh, int? acOut, int? dcOut) {
    final out = (acOut ?? 0) + (dcOut ?? 0);
    if (remainWh == null || out <= 5) return '—';
    final h = remainWh / out;
    if (!h.isFinite || h <= 0) return '—';
    if (h >= 100) return '99+ h';
    if (h >= 10) return '${h.toStringAsFixed(0)} h';
    return '${h.toStringAsFixed(1)} h';
  }

  static String source(int? acIn, int? pvIn) {
    final ac = (acIn ?? 0) > 30;
    final pv = (pvIn ?? 0) > 30;
    if (ac && pv) return 'AC+PV';
    if (ac) return 'AC';
    if (pv) return 'PV';
    return 'BATT';
  }
}

class PackHistory {
  static const _key = 's2200-hist-v1';
  static const _gapMs = 15000;
  static const _keepMs = 7 * 24 * 60 * 60 * 1000;

  static Map<String, List<HistPoint>>? _mem;
  static bool _dirty = false;
  static Timer? _flush;

  static Future<void> push(String series, double? value, {int sparkMax = 48, int sparkGapMs = 0}) async {
    SparkBuf.add(series, value, max: sparkMax, gapMs: sparkGapMs);
    if (value == null || !value.isFinite) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    final all = await _load();
    final prev = (all[series] ?? []).where((p) => now - p.t < _keepMs).toList();
    if (prev.isNotEmpty && now - prev.last.t < _gapMs) {
      prev[prev.length - 1] = HistPoint(now, value);
    } else {
      prev.add(HistPoint(now, value));
    }
    all[series] = prev;
    _dirty = true;
    _flush ??= Timer(const Duration(seconds: 15), () {
      _flush = null;
      unawaited(_persist());
    });
  }

  static Future<List<HistPoint>> series(String key) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    return ((await _load())[key] ?? []).where((p) => now - p.t < _keepMs).toList();
  }

  static List<HistPoint> fromCloud(dynamic data) {
    final rows = _rows(data);
    final out = <HistPoint>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final v = _num(row['day_power'] ?? row['day_pv'] ?? row['power'] ?? row['value'] ?? row['soc'] ?? row['pv']);
      if (v == null) continue;
      final label = (row['time_period'] ?? row['date'] ?? row['time'] ?? row['time_no'] ?? i).toString();
      out.add(HistPoint(i, v, label: label));
    }
    return out;
  }

  static List<Map<String, dynamic>> _rows(dynamic data) {
    if (data is List) {
      return data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      for (final key in ['chart', 'data', 'list', 'days', 'records']) {
        final inner = _rows(map[key]);
        if (inner.isNotEmpty) return inner;
      }
    }
    return [];
  }

  static double? _num(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }

  static Future<Map<String, List<HistPoint>>> _load() async {
    if (_mem != null) return _mem!;
    final p = await SharedPreferences.getInstance();
    final raw = p.getString(_key);
    if (raw == null) {
      _mem = {};
      return _mem!;
    }
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      _mem = map.map((k, v) {
        final list = (v as List).map((e) => HistPoint((e[0] as num).toInt(), (e[1] as num).toDouble())).toList();
        return MapEntry(k, list);
      });
    } catch (_) {
      _mem = {};
    }
    return _mem!;
  }

  static Future<void> _persist() async {
    if (!_dirty || _mem == null) return;
    _dirty = false;
    await EnergyDay.flush();
    final p = await SharedPreferences.getInstance();
    final map = _mem!.map((k, v) => MapEntry(k, v.map((e) => [e.t, e.v]).toList()));
    await p.setString(_key, jsonEncode(map));
  }
}
