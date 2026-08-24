import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_tool.dart';

class JuntekHit {
  JuntekHit({required this.id, required this.name, required this.rssi, required this.likely});
  final String id;
  final String name;
  final int rssi;
  final bool likely;
}

bool likelyJuntekName(String name) {
  final n = name.toUpperCase();
  if (n.isEmpty) return false;
  return n.contains('JUNTEK') ||
      n.contains('JUNCTEK') ||
      n.contains('VAT') ||
      n.contains('KG-') ||
      n.contains('KL-') ||
      n.contains('KGF') ||
      n.contains('KLF') ||
      n.startsWith('KG') ||
      n.startsWith('KL') ||
      n.contains('BTGEAR');
}

class JuntekLive {
  JuntekLive({
    this.volts,
    this.amps,
    this.watts,
    this.ahRemain,
    this.capacityAh,
    this.minutesLeft,
    this.charging,
    this.status = 'idle',
    this.error,
  });

  final double? volts;
  final double? amps;
  final double? watts;
  final double? ahRemain;
  final double? capacityAh;
  final int? minutesLeft;
  final bool? charging;
  final String status;
  final String? error;

  double? get soc {
    final cap = capacityAh;
    final ah = ahRemain;
    if (cap == null || ah == null || cap <= 0) return null;
    return ((ah / cap) * 100).clamp(0, 100);
  }

  JuntekLive copyWith({
    double? volts,
    double? amps,
    double? watts,
    double? ahRemain,
    double? capacityAh,
    int? minutesLeft,
    bool? charging,
    String? status,
    String? error,
  }) {
    return JuntekLive(
      volts: volts ?? this.volts,
      amps: amps ?? this.amps,
      watts: watts ?? this.watts,
      ahRemain: ahRemain ?? this.ahRemain,
      capacityAh: capacityAh ?? this.capacityAh,
      minutesLeft: minutesLeft ?? this.minutesLeft,
      charging: charging ?? this.charging,
      status: status ?? this.status,
      error: error,
    );
  }
}

int _bcd(List<int> bytes) {
  var n = 0;
  for (final b in bytes) {
    n = n * 100 + ((b >> 4) & 0xf) * 10 + (b & 0xf);
  }
  return n;
}

Map<int, int> parseJuntekFrame(Uint8List f) {
  final out = <int, int>{};
  if (f.length < 5 || f.first != 0xbb || f.last != 0xee) return out;
  final body = f.sublist(1, f.length - 2);
  var i = 0;
  while (i < body.length) {
    var j = i;
    while (j < body.length && (body[j] < 0xb0 || body[j] > 0xf0)) {
      j += 1;
    }
    if (j >= body.length) break;
    if (j > i) out[body[j]] = _bcd(body.sublist(i, j));
    i = j + 1;
  }
  return out;
}

class JuntekTool {
  JuntekTool._();
  static final instance = JuntekTool._();

  BluetoothDevice? _dev;
  BluetoothCharacteristic? _tx;
  BluetoothCharacteristic? _rx;
  StreamSubscription<List<int>>? _notify;
  StreamSubscription<BluetoothConnectionState>? _conn;
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _poll;
  Timer? _resume;
  bool _busy = false;
  bool _manual = false;
  String? savedId;
  bool get wantsLink => !_manual && savedId != null;
  Uint8List _buf = Uint8List(0);
  JuntekLive live = JuntekLive();
  DateTime? lastRx;
  final _seen = <String, BluetoothDevice>{};
  final hits = <String, JuntekHit>{};
  final _ctrl = StreamController<JuntekLive>.broadcast();
  final _hitsCtrl = StreamController<List<JuntekHit>>.broadcast();
  Stream<JuntekLive> get stream => _ctrl.stream;
  Stream<List<JuntekHit>> get hitsStream => _hitsCtrl.stream;

  void _emit(JuntekLive next) {
    live = next;
    _ctrl.add(next);
  }

  void _emitHits() {
    final list = hits.values.toList()
      ..sort((a, b) {
        if (a.likely != b.likely) return a.likely ? -1 : 1;
        return b.rssi.compareTo(a.rssi);
      });
    _hitsCtrl.add(list);
  }

  Future<void> loadSaved() async {
    savedId = (await SharedPreferences.getInstance()).getString('hak-juntek-id');
  }

  Future<void> _remember(String id) async {
    savedId = id;
    await (await SharedPreferences.getInstance()).setString('hak-juntek-id', id);
  }

  Future<void> startScan() async {
    hits.clear();
    _seen.clear();
    _emitHits();
    _emit(JuntekLive(status: 'scan'));
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((list) {
      for (final r in list) {
        final name = r.device.platformName;
        final id = r.device.remoteId.str;
        _seen[id] = r.device;
        hits[id] = JuntekHit(id: id, name: name.isEmpty ? id : name, rssi: r.rssi, likely: likelyJuntekName(name));
      }
      _emitHits();
    });
    await FlutterBluePlus.startScan(timeout: const Duration(seconds: 10));
  }

  Future<void> stopScan() async {
    await FlutterBluePlus.stopScan();
    await _scanSub?.cancel();
    _scanSub = null;
  }

  void _scheduleResume() {
    if (!wantsLink) return;
    _resume?.cancel();
    _resume = Timer(const Duration(seconds: 8), () {
      if (!wantsLink || _busy || live.status == 'live') return;
      unawaited(connectId(savedId!).catchError((_) => _scheduleResume()));
    });
  }

  bool _uuidHas(Guid u, String needle) => u.str128.toLowerCase().contains(needle);

  Future<void> connectId(String id) async {
    _manual = false;
    _resume?.cancel();
    await _remember(id);
    if (_busy) return;
    _busy = true;
    lastRx = null;
    await stopScan();
    final hit = _seen[id] ?? BluetoothDevice.fromId(id);
    _dev = hit;
    _emit(JuntekLive(status: 'connecting'));
    var up = false;
    await _conn?.cancel();
    _conn = hit.connectionState.listen((s) {
      if (s == BluetoothConnectionState.connected) up = true;
      if (s == BluetoothConnectionState.disconnected && up && !_manual) {
        _poll?.cancel();
        if (live.status == 'live') _emit(live.copyWith(status: 'lost', error: 'Disconnected'));
        _scheduleResume();
      }
    });
    try {
      if (!hit.isConnected) {
        await hit.connect(timeout: const Duration(seconds: 18), autoConnect: false);
      }
      final svcs = await hit.discoverServices();
      _tx = null;
      _rx = null;
      for (final s in svcs) {
        if (!_uuidHas(s.uuid, 'fff0') && !_uuidHas(s.uuid, 'ffe0') && !_uuidHas(s.uuid, 'ff00')) continue;
        for (final c in s.characteristics) {
          final u = c.uuid.str128.toLowerCase();
          if (u.contains('fff1') || u.contains('ffe1')) _rx = c;
          if (u.contains('fff2') || u.contains('ffe2')) _tx = c;
        }
      }
      if (_rx == null) {
        for (final s in svcs) {
          for (final c in s.characteristics) {
            if (c.properties.notify) _rx = c;
            if (c.properties.write || c.properties.writeWithoutResponse) _tx ??= c;
          }
        }
      }
      final rx = _rx;
      if (rx == null) {
        _emit(JuntekLive(status: 'no gatt', error: 'no notify char'));
        throw Exception('Juntek GATT missing notify');
      }
      if (_tx == null && (rx.properties.write || rx.properties.writeWithoutResponse)) _tx = rx;
      await rx.setNotifyValue(true);
      await _notify?.cancel();
      _notify = rx.onValueReceived.listen(_onRx);
      await _dump();
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 4), (_) => unawaited(_dump()));
    } catch (e) {
      _scheduleResume();
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> _dump() async {
    final tx = _tx;
    if (tx == null) return;
    try {
      await BleRadio.instance.enqueue(() async {
        await tx.write(
          [0xbb, 0x9a, 0xa9, 0x0c, 0xee],
          withoutResponse: tx.properties.writeWithoutResponse,
        );
      });
    } catch (_) {}
  }

  Future<void> disconnect() async {
    _manual = true;
    _resume?.cancel();
    _poll?.cancel();
    await stopScan();
    await _notify?.cancel();
    await _conn?.cancel();
    await _dev?.disconnect();
    _dev = null;
    _tx = null;
    _rx = null;
    lastRx = null;
    savedId = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('hak-juntek-id');
    _emit(JuntekLive());
  }

  void _onRx(List<int> data) {
    lastRx = DateTime.now();
    final n = Uint8List.fromList([..._buf, ...data]);
    final frames = <Uint8List>[];
    var i = 0;
    while (i < n.length) {
      if (n[i] != 0xbb) {
        i += 1;
        continue;
      }
      var j = i + 1;
      while (j < n.length && n[j] != 0xee) {
        j += 1;
      }
      if (j >= n.length) break;
      frames.add(n.sublist(i, j + 1));
      i = j + 1;
    }
    _buf = i < n.length ? n.sublist(i) : Uint8List(0);
    if (_buf.length > 256) _buf = _buf.sublist(_buf.length - 64);
    var next = live.copyWith(status: 'live', error: null);
    for (final f in frames) {
      final map = parseJuntekFrame(f);
      if (map.containsKey(0xc0)) next = next.copyWith(volts: map[0xc0]! / 100);
      if (map.containsKey(0xc1)) next = next.copyWith(amps: map[0xc1]! / 100);
      if (map.containsKey(0xd8)) next = next.copyWith(watts: map[0xd8]! / 100);
      if (map.containsKey(0xd2)) next = next.copyWith(ahRemain: map[0xd2]! / 1000);
      if (map.containsKey(0xb1)) next = next.copyWith(capacityAh: map[0xb1]!.toDouble());
      if (map.containsKey(0xd6)) next = next.copyWith(minutesLeft: map[0xd6]);
      if (map.containsKey(0xd1)) next = next.copyWith(charging: map[0xd1] == 1);
    }
    _emit(next);
  }
}
