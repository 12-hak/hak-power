import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_tool.dart';
import 'fridge_protocol.dart';

class FridgeHit {
  FridgeHit({required this.id, required this.name, required this.rssi, required this.likely});
  final String id;
  final String name;
  final int rssi;
  final bool likely;
}

bool likelyFridgeName(String name) {
  final n = name.toUpperCase();
  if (n.isEmpty) return false;
  return fridgePrefixes.any((p) => n.startsWith(p.toUpperCase())) ||
      n.contains('MONKEY') ||
      n.contains('ALPI') ||
      n.contains('ICE') ||
      n.contains('COOL') ||
      n.contains('FRIDGE') ||
      n.contains('LILY') ||
      n.contains('K25');
}

class FridgeTool {
  FridgeTool._();
  static final instance = FridgeTool._();

  BluetoothDevice? _dev;
  BluetoothCharacteristic? _tx;
  BluetoothCharacteristic? _rx;
  BluetoothCharacteristic? _writeChar;
  StreamSubscription<List<int>>? _notify;
  StreamSubscription<BluetoothConnectionState>? _conn;
  StreamSubscription<List<ScanResult>>? _scanSub;
  Timer? _poll;
  Timer? _resume;
  bool _busy = false;
  String? savedId;
  bool get wantsLink => !_manual && savedId != null;
  Uint8List _buf = Uint8List(0);
  FridgeLive live = FridgeLive();
  bool _manual = false;
  DateTime? lastRx;
  DateTime? _bindAt;
  Completer<FridgeLive>? _rxWait;
  bool _setting = false;
  int _leftPend = 0;
  int _rightPend = 0;
  Future<void>? _leftJob;
  Future<void>? _rightJob;
  int? pendingLeft;
  int? pendingRight;
  final _seen = <String, BluetoothDevice>{};
  final hits = <String, FridgeHit>{};
  final _ctrl = StreamController<FridgeLive>.broadcast();
  final _hitsCtrl = StreamController<List<FridgeHit>>.broadcast();
  Stream<FridgeLive> get stream => _ctrl.stream;
  Stream<List<FridgeHit>> get hitsStream => _hitsCtrl.stream;

  void _emit(FridgeLive next) {
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

  Future<void> startScan() async {
    hits.clear();
    _seen.clear();
    _emitHits();
    _emit(FridgeLive(status: 'scan'));
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((list) {
      for (final r in list) {
        final name = r.device.platformName;
        final id = r.device.remoteId.str;
        _seen[id] = r.device;
        hits[id] = FridgeHit(id: id, name: name.isEmpty ? id : name, rssi: r.rssi, likely: likelyFridgeName(name));
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

  Future<void> connect() async {
    _manual = false;
    try {
      await startScan();
      await Future.any([
        FlutterBluePlus.isScanning.where((on) => !on).first,
        Future<void>.delayed(const Duration(seconds: 11)),
      ]);
      await stopScan();
      final pick = hits.values.where((h) => h.likely).toList();
      if (pick.isEmpty) {
        _emit(FridgeLive(status: 'no fridge'));
        return;
      }
      await connectId(pick.first.id);
    } catch (_) {
      await stopScan();
      _emit(FridgeLive(status: 'fail'));
    }
  }

  bool _uuidHas(Guid u, String needle) => u.str128.toLowerCase().contains(needle);

  Future<void> loadSaved() async {
    savedId = (await SharedPreferences.getInstance()).getString('hak-fridge-id');
  }

  Future<void> _remember(String id) async {
    savedId = id;
    await (await SharedPreferences.getInstance()).setString('hak-fridge-id', id);
  }

  void _scheduleResume() {
    if (!wantsLink) return;
    _resume?.cancel();
    _resume = Timer(const Duration(seconds: 6), () {
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
    _bindAt = null;
    _writeChar = null;
    await stopScan();
    final hit = _seen[id] ?? BluetoothDevice.fromId(id);
    _dev = hit;
    _emit(FridgeLive(status: 'connecting'));
    var up = false;
    await _conn?.cancel();
    _conn = hit.connectionState.listen((s) {
      if (s == BluetoothConnectionState.connected) up = true;
      if (s == BluetoothConnectionState.disconnected && up && !_manual) {
        _poll?.cancel();
        if (live.status == 'live' || live.status.startsWith('bind')) {
          _emit(FridgeLive(status: 'lost', error: 'Disconnected'));
        }
        _scheduleResume();
      }
    });

    try {
    Object? err;
    for (var i = 0; i < 3; i++) {
      try {
        if (i > 0) {
          try {
            await hit.disconnect();
          } catch (_) {}
          await Future<void>.delayed(Duration(milliseconds: 700 * i));
        }
        if (!hit.isConnected) {
          await hit.connect(timeout: const Duration(seconds: 18), autoConnect: false);
        }
        err = null;
        break;
      } catch (e) {
        err = e;
      }
    }
    if (err != null) {
      _emit(FridgeLive(status: 'fail', error: err.toString()));
      _scheduleResume();
      throw err;
    }

    await Future<void>.delayed(const Duration(milliseconds: 450));
    try {
      await hit.requestConnectionPriority(connectionPriorityRequest: ConnectionPriority.high);
    } catch (_) {}

    var svcs = await hit.discoverServices();
    _tx = null;
    _rx = null;
    void pick(List<BluetoothService> list) {
      for (final s in list) {
        if (!_uuidHas(s.uuid, '1234')) continue;
        for (final c in s.characteristics) {
          if (_uuidHas(c.uuid, '1235')) _tx = c;
          if (_uuidHas(c.uuid, '1236')) _rx = c;
        }
      }
    }

    pick(svcs);
    if (_tx == null || _rx == null) {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      svcs = await hit.discoverServices();
      pick(svcs);
    }
    if (_tx == null || _rx == null) {
      try {
        await hit.clearGattCache();
      } catch (_) {}
      svcs = await hit.discoverServices();
      pick(svcs);
    }
    final txCanWrite = _tx != null && (_tx!.properties.write || _tx!.properties.writeWithoutResponse);
    final rxCanWrite = _rx != null && (_rx!.properties.write || _rx!.properties.writeWithoutResponse);
    if (!txCanWrite && rxCanWrite) {
      final swap = _tx;
      _tx = _rx;
      _rx = swap;
    }
    final rx = _rx;
    if (rx == null || _tx == null) {
      final ids = svcs.map((s) => s.uuid.str128).join(',');
      _emit(FridgeLive(status: 'no gatt', error: 'no 1234/1235/1236 ($ids)'));
      throw Exception('Fridge GATT missing 1234 service');
    }
    try {
      await rx.setNotifyValue(true);
    } catch (_) {}
    await _notify?.cancel();
    _notify = rx.onValueReceived.listen(_onRx);
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _bindAt = DateTime.now();
    _emit(FridgeLive(status: 'connecting'));
    await query();
    _poll?.cancel();
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
    } catch (e) {
      _scheduleResume();
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> _tick() async {
    if (_setting) return;
    final stale = lastRx == null || DateTime.now().difference(lastRx!) > const Duration(seconds: 2);
    if (stale) {
      try {
        await query();
      } catch (_) {}
    }
    if (live.status == 'live' && lastRx != null && DateTime.now().difference(lastRx!) > const Duration(seconds: 8)) {
      _emit(live.copyWith(status: 'offline'));
      _scheduleResume();
    }
    if ((live.status == 'connecting' || live.status.startsWith('bind')) &&
        lastRx == null &&
        _bindAt != null &&
        DateTime.now().difference(_bindAt!) > const Duration(seconds: 12)) {
      _emit(FridgeLive(status: 'offline', error: 'No BLE reply from fridge'));
      _scheduleResume();
    }
  }

  Future<void> query() async {
    await _write(fridgeFrame(fridgeQuery));
  }

  Future<FridgeLive?> _nextParsed([Duration timeout = const Duration(milliseconds: 1200)]) async {
    final c = Completer<FridgeLive>();
    _rxWait = c;
    try {
      return await c.future.timeout(timeout);
    } on TimeoutException {
      return null;
    } finally {
      if (identical(_rxWait, c)) _rxWait = null;
    }
  }

  Future<bool> _readBack(bool Function(FridgeLive s) ok) async {
    for (var i = 0; i < 4; i++) {
      if (i > 0) await Future<void>.delayed(Duration(milliseconds: 150 * i));
      final pending = _nextParsed(const Duration(milliseconds: 1500));
      try {
        await query();
      } catch (_) {
        return false;
      }
      final got = await pending;
      if (got != null && ok(got)) return true;
    }
    return false;
  }

  void _touch() => _ctrl.add(live);

  Future<void> setLeftTemp(int temp) async {
    if (_tx == null && _writeChar == null) return;
    final next = temp.clamp(live.minC, live.maxC).toInt();
    pendingLeft = next;
    _touch();
    if (live.leftTarget == next) {
      pendingLeft = null;
      _touch();
      return;
    }
    _setting = true;
    BleRadio.instance.hush(const Duration(seconds: 5));
    try {
      for (var i = 0; i < 2; i++) {
        await _write(fridgeFrame(fridgeSetLeft, [toU8(next)]));
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (await _readBack((s) => s.leftTarget == next)) return;
      }
    } finally {
      _setting = false;
      if (_leftPend == 0) {
        pendingLeft = null;
        _touch();
      }
    }
  }

  Future<void> setRightTemp(int temp) async {
    if (_tx == null && _writeChar == null) return;
    final next = temp.clamp(live.minC, live.maxC).toInt();
    pendingRight = next;
    _touch();
    if (live.rightTarget == next) {
      pendingRight = null;
      _touch();
      return;
    }
    _setting = true;
    BleRadio.instance.hush(const Duration(seconds: 5));
    try {
      for (var i = 0; i < 2; i++) {
        await _write(fridgeFrame(fridgeSetRight, [toU8(next)]));
        await Future<void>.delayed(const Duration(milliseconds: 120));
        if (await _readBack((s) => s.rightTarget == next)) return;
      }
    } finally {
      _setting = false;
      if (_rightPend == 0) {
        pendingRight = null;
        _touch();
      }
    }
  }

  Future<void> nudgeLeft(int delta) {
    _leftPend += delta;
    pendingLeft = ((live.leftTarget ?? live.leftC ?? 0) + _leftPend).clamp(live.minC, live.maxC).toInt();
    _touch();
    return _leftJob ??= _flushLeft();
  }

  Future<void> nudgeRight(int delta) {
    _rightPend += delta;
    pendingRight = ((live.rightTarget ?? live.rightC ?? 0) + _rightPend).clamp(live.minC, live.maxC).toInt();
    _touch();
    return _rightJob ??= _flushRight();
  }

  Future<void> _flushLeft() async {
    try {
      while (_leftPend != 0) {
        final d = _leftPend;
        _leftPend = 0;
        await setLeftTemp((live.leftTarget ?? live.leftC ?? 0) + d);
      }
    } finally {
      _leftJob = null;
      if (_leftPend != 0) _leftJob = _flushLeft();
    }
  }

  Future<void> _flushRight() async {
    try {
      while (_rightPend != 0) {
        final d = _rightPend;
        _rightPend = 0;
        await setRightTemp((live.rightTarget ?? live.rightC ?? 0) + d);
      }
    } finally {
      _rightJob = null;
      if (_rightPend != 0) _rightJob = _flushRight();
    }
  }

  Future<void> _patchOther(FridgeLive next, bool Function(FridgeLive) ok) async {
    if (live.status != 'live') return;
    _setting = true;
    BleRadio.instance.hush(const Duration(seconds: 5));
    try {
      await _write(fridgeFrame(fridgeSetOther, buildSetOtherPayload(next)));
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await _readBack(ok);
    } finally {
      _setting = false;
    }
  }

  Future<void> setEco(bool on) => _patchOther(live.copyWith(eco: on), (s) => s.eco == on);

  Future<void> setLock(bool on) => _patchOther(live.copyWith(locked: on), (s) => s.locked == on);

  Future<void> setPower(bool on) => _patchOther(live.copyWith(on: on), (s) => s.on == on);

  Future<void> setUnit(String unit) => _patchOther(live.copyWith(unit: unit), (s) => s.unit == unit);

  Future<void> setBatSaver(int level) =>
      _patchOther(live.copyWith(batSaver: level.clamp(0, 2)), (s) => s.batSaver == level.clamp(0, 2));

  Future<void> applyPreset(int left, [int? right]) async {
    await setLeftTemp(left);
    if (live.dual && right != null) await setRightTemp(right);
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
    _writeChar = null;
    lastRx = null;
    _emit(FridgeLive());
  }

  Future<void> _write(Uint8List data) {
    return BleRadio.instance.enqueue(() async {
      final chars = <BluetoothCharacteristic>[
        if (_writeChar != null) _writeChar!,
        if (_tx != null && _tx != _writeChar) _tx!,
        if (_rx != null && _rx != _writeChar && _rx != _tx) _rx!,
      ];
      if (chars.isEmpty) throw Exception('Fridge write failed');
      for (final c in chars) {
        try {
          await c.write(data, withoutResponse: false);
          _writeChar = c;
          _tx = c;
          return;
        } catch (e) {
          if (e.toString().contains('WRITE_NO_RESPONSE')) continue;
        }
      }
      throw Exception('Fridge write failed');
    });
  }

  void _onRx(List<int> data) {
    lastRx = DateTime.now();
    final n = Uint8List.fromList([..._buf, ...data]);
    final frames = extractFridgeFrames(n);
    if (frames.isEmpty) {
      _buf = n.length > 256 ? n.sublist(n.length - 64) : n;
      return;
    }
    _buf = Uint8List(0);
    for (final f in frames) {
      if (f.length < 6) continue;
      final cmd = f[3];
      final payload = f.sublist(4, f.length - 2);
      if (cmd == fridgeBind) {
        _emit(live.copyWith(status: 'live', error: null));
        unawaited(query());
        continue;
      }
      if (cmd != fridgeQuery) continue;
      final parsed = parseFridgeQuery(payload);
      if (parsed != null) {
        _emit(parsed);
        final wait = _rxWait;
        if (wait != null && !wait.isCompleted) wait.complete(parsed);
      }
    }
  }
}
