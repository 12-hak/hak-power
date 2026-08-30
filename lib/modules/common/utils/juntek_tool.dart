import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_tool.dart';
import 'fridge_tool.dart';

class JuntekHit {
  JuntekHit({
    required this.id,
    required this.name,
    required this.rssi,
    required this.likely,
    this.tag = '',
  });
  final String id;
  final String name;
  final int rssi;
  final bool likely;
  final String tag;
}

bool likelyJuntekName(String name) {
  final n = name.toUpperCase().trim();
  if (n.isEmpty) return false;
  return n.contains('JUNTEK') ||
      n.contains('JUNCTEK') ||
      n.contains('VAT') ||
      n.contains('KG-') ||
      n.contains('KL-') ||
      n.contains('KH-') ||
      n.contains('KF-') ||
      n.contains('KGF') ||
      n.contains('KLF') ||
      n.contains('KHF') ||
      n.startsWith('KG') ||
      n.startsWith('KL') ||
      n.startsWith('KH') ||
      n.contains('BTGEAR') ||
      n.contains('BTG');
}

bool _juntekUuids(Iterable<Guid> uuids) {
  return uuids.any((u) {
    final s = u.str128.toLowerCase();
    return s.contains('fff0') || s.contains('ffe0');
  });
}

bool _uartName(String name) {
  final n = name.toUpperCase();
  return n.contains('JDY') ||
      n.contains('HM-') ||
      n.contains('HMSOFT') ||
      n.contains('BT05') ||
      n.contains('BT-05') ||
      n.contains('AT-09') ||
      n.startsWith('MLT') ||
      n.contains('SH-HC') ||
      n.contains('BLE-');
}

bool _isPackOrFridge(String id, String name) {
  if (id == BleTool.instance.savedId) return true;
  if (id == FridgeTool.instance.savedId) return true;
  if (likelyPackName(name, id)) return true;
  if (likelyFridgeName(name)) return true;
  return false;
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
  if (f.length < 4 || f.first != 0xbb || f.last != 0xee) return {};
  final withCs = _parseBody(f.sublist(1, f.length - 2));
  if (withCs.isNotEmpty) return withCs;
  return _parseBody(f.sublist(1, f.length - 1));
}

Map<int, int> _parseBody(List<int> body) {
  final out = <int, int>{};
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

JuntekLive? parseJuntekAscii(String raw) {
  final m = RegExp(r':r50=\s*([0-9,\s]+)', caseSensitive: false).firstMatch(raw);
  if (m == null) return null;
  final parts = m.group(1)!.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (parts.length < 5) return null;
  final nums = parts.map(int.tryParse).toList();
  if (nums.any((n) => n == null)) return null;
  final v = nums[2]!;
  final a = nums[3]!;
  final ah = nums[4]!;
  bool? charging;
  if (nums.length > 11) charging = nums[11] == 1;
  return JuntekLive(
    status: 'live',
    volts: v / 100,
    amps: a / 100,
    watts: (v / 100) * (a / 100),
    ahRemain: ah / 1000,
    charging: charging,
  );
}

double? parseJuntekR51Cap(String raw) {
  final m = RegExp(r':r51=\s*([0-9,\s]+)', caseSensitive: false).firstMatch(raw);
  if (m == null) return null;
  final parts = m.group(1)!.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  if (parts.length < 11) return null;
  final n = int.tryParse(parts[10]);
  if (n == null || n <= 0) return null;
  return n / 10;
}

class JuntekTool {
  JuntekTool._();
  static final instance = JuntekTool._();

  BluetoothDevice? _dev;
  final _txs = <BluetoothCharacteristic>[];
  final _notifies = <StreamSubscription<List<int>>>[];
  StreamSubscription<BluetoothConnectionState>? _conn;
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _poll;
  Timer? _resume;
  bool _busy = false;
  bool _manual = false;
  String? savedId;
  double? _capAh;
  bool get wantsLink => !_manual && savedId != null;
  Uint8List _buf = Uint8List(0);
  JuntekLive live = JuntekLive();
  DateTime? lastRx;
  final _seen = <String, BluetoothDevice>{};
  final hits = <String, JuntekHit>{};
  int _scanGen = 0;
  final _ctrl = StreamController<JuntekLive>.broadcast();
  final _hitsCtrl = StreamController<List<JuntekHit>>.broadcast();
  Stream<JuntekLive> get stream => _ctrl.stream;
  Stream<List<JuntekHit>> get hitsStream => _hitsCtrl.stream;

  void _emit(JuntekLive next) {
    if (_capAh != null && next.capacityAh == null) {
      next = next.copyWith(capacityAh: _capAh);
    }
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
    final p = await SharedPreferences.getInstance();
    savedId = p.getString('hak-juntek-id');
    await p.remove('hak-juntek-cap');
    _capAh = p.getDouble('hak-juntek-ah');
  }

  Future<void> _saveCap(double ah) async {
    if (ah <= 0) return;
    _capAh = ah;
    await (await SharedPreferences.getInstance()).setDouble('hak-juntek-ah', ah);
    _emit(live.copyWith(capacityAh: ah));
  }

  Future<void> setCapacityAh(double ah) => _saveCap(ah);

  Future<void> _remember(String id) async {
    savedId = id;
    await (await SharedPreferences.getInstance()).setString('hak-juntek-id', id);
  }

  Future<void> startScan() async {
    _scanGen++;
    hits.clear();
    _seen.clear();
    _emitHits();
    _emit(JuntekLive(status: 'scan'));
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((list) {
      for (final r in list) {
        _ingest(r);
      }
      _emitHits();
    });
    await FlutterBluePlus.startScan(
      timeout: const Duration(seconds: 12),
      androidScanMode: AndroidScanMode.lowLatency,
    );
  }

  String _nameOf(ScanResult r) {
    final a = r.device.platformName.trim();
    if (a.isNotEmpty) return a;
    final b = r.advertisementData.advName.trim();
    if (b.isNotEmpty) return b;
    return r.device.remoteId.str;
  }

  bool _msdLooksJuntek(Map<int, List<int>> msd) {
    for (final bytes in msd.values) {
      final s = String.fromCharCodes(bytes.where((b) => b >= 32 && b < 127));
      if (likelyJuntekName(s)) return true;
    }
    return false;
  }

  void _ingest(ScanResult r) {
    final id = r.device.remoteId.str;
    final name = _nameOf(r);
    if (_isPackOrFridge(id, name)) return;
    _seen[id] = r.device;
    final byName = likelyJuntekName(name);
    final byUuid = _juntekUuids(r.advertisementData.serviceUuids) || _juntekUuids(r.advertisementData.serviceData.keys);
    final byMsd = _msdLooksJuntek(r.advertisementData.manufacturerData);
    final likely = byName || byUuid || byMsd;
    final tag = byUuid
        ? 'Juntek fff0'
        : byMsd
            ? 'Juntek advert'
            : byName
                ? 'Juntek name'
                : (_uartName(name) ? 'possible meter' : '');
    final prev = hits[id];
    hits[id] = JuntekHit(
      id: id,
      name: name,
      rssi: r.rssi,
      likely: likely || (prev?.likely ?? false),
      tag: (prev != null && prev.likely && prev.tag.startsWith('Juntek GATT')) ? prev.tag : tag,
    );
  }

  Future<void> stopScan() async {
    _scanGen++;
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

  Future<void> connectId(String id) async {
    _manual = false;
    _resume?.cancel();
    await _remember(id);
    if (_busy) return;
    _busy = true;
    lastRx = null;
    await stopScan();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    BleRadio.instance.hush(const Duration(seconds: 15));
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
      Object? err;
      for (var i = 0; i < 2; i++) {
        try {
          if (i > 0) {
            try {
              await hit.disconnect();
            } catch (_) {}
            await Future<void>.delayed(Duration(milliseconds: 900 * i));
          }
          if (!hit.isConnected) {
            await hit.connect(timeout: const Duration(seconds: 20), autoConnect: false, mtu: null);
          }
          err = null;
          break;
        } catch (e) {
          err = e;
        }
      }
      if (err != null) {
        _emit(JuntekLive(status: 'fail', error: err.toString()));
        throw err;
      }
      await Future<void>.delayed(const Duration(milliseconds: 600));
      var svcs = <BluetoothService>[];
      try {
        svcs = await hit.discoverServices().timeout(const Duration(seconds: 8));
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        svcs = await hit.discoverServices().timeout(const Duration(seconds: 8));
      }
      _txs.clear();
      await _cancelNotifies();
      for (final s in svcs) {
        for (final c in s.characteristics) {
          if (c.properties.write || c.properties.writeWithoutResponse) {
            final u = c.uuid.str128.toLowerCase();
            if (u.contains('ffe') || u.contains('fff')) _txs.add(c);
          }
          if (c.properties.notify || c.properties.indicate) {
            try {
              await c.setNotifyValue(true);
              _notifies.add(c.onValueReceived.listen(_onRx));
            } catch (_) {}
          }
        }
      }
      if (_notifies.isEmpty) {
        final ids = svcs.map((s) => s.uuid.str128).join(',');
        _emit(JuntekLive(status: 'no gatt', error: 'no notify ($ids)'));
        throw Exception('Juntek GATT missing notify');
      }
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 3), (_) {
        if (lastRx == null || DateTime.now().difference(lastRx!) > const Duration(seconds: 5)) {
          unawaited(_dump());
        }
      });
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await _dump();
    } catch (e) {
      _scheduleResume();
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> _cancelNotifies() async {
    for (final s in _notifies) {
      await s.cancel();
    }
    _notifies.clear();
  }

  Future<void> _dump() async {
    final chars = [..._txs];
    for (final tx in chars) {
      try {
        await BleRadio.instance.enqueue(() async {
          final noRsp = tx.properties.writeWithoutResponse;
          await tx.write(utf8.encode(':R50=1,2,1,'), withoutResponse: noRsp).timeout(const Duration(seconds: 2));
          await Future<void>.delayed(const Duration(milliseconds: 80));
          await tx.write(utf8.encode(':R51=1,2,1,'), withoutResponse: noRsp).timeout(const Duration(seconds: 2));
          await Future<void>.delayed(const Duration(milliseconds: 80));
          await tx.write(
            [0xbb, 0x9a, 0xa9, 0x0c, 0xee],
            withoutResponse: noRsp,
          ).timeout(const Duration(seconds: 2));
        });
      } catch (_) {}
    }
  }

  Future<void> disconnect() async {
    _manual = true;
    _resume?.cancel();
    _poll?.cancel();
    await stopScan();
    await _cancelNotifies();
    await _conn?.cancel();
    await _dev?.disconnect();
    _dev = null;
    _txs.clear();
    lastRx = null;
    savedId = null;
    final p = await SharedPreferences.getInstance();
    await p.remove('hak-juntek-id');
    _emit(JuntekLive());
  }

  void _onRx(List<int> data) {
    if (data.isEmpty) return;
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
    var next = live;
    var got = false;
    for (final f in frames) {
      final map = parseJuntekFrame(f);
      if (map.isEmpty) continue;
      got = true;
      if (map.containsKey(0xc0)) next = next.copyWith(volts: map[0xc0]! / 100);
      if (map.containsKey(0xc1)) next = next.copyWith(amps: map[0xc1]! / 100);
      if (map.containsKey(0xd8)) next = next.copyWith(watts: map[0xd8]! / 100);
      if (map.containsKey(0xd2)) next = next.copyWith(ahRemain: map[0xd2]! / 1000);
      if (map.containsKey(0xb0)) {
        final cap = map[0xb0]! / 10;
        if (cap > 1) {
          next = next.copyWith(capacityAh: cap);
          unawaited(_saveCap(cap));
        }
      }
      if (map.containsKey(0xd6)) next = next.copyWith(minutesLeft: map[0xd6]);
      if (map.containsKey(0xd1)) next = next.copyWith(charging: map[0xd1] == 1);
    }
    final text = utf8.decode(data, allowMalformed: true);
    final ascii = parseJuntekAscii(text);
    if (ascii != null) {
      got = true;
      next = next.copyWith(
        volts: ascii.volts,
        amps: ascii.amps,
        watts: ascii.watts,
        ahRemain: ascii.ahRemain,
        charging: ascii.charging,
      );
    }
    final r51 = parseJuntekR51Cap(text);
    if (r51 != null) {
      got = true;
      next = next.copyWith(capacityAh: r51);
      unawaited(_saveCap(r51));
    }
    if (!got) return;
    _emit(next.copyWith(status: 'live', error: null));
  }
}
