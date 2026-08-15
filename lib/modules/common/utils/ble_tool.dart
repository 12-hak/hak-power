import 'dart:async';
import 'dart:convert';
import 'dart:developer' as dev;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble_data_resolver.dart';

class PackLive {
  PackLive({
    this.bleOn = false,
    this.inputW = 0,
    this.outputW = 0,
    this.pvIn,
    this.acIn,
    this.dcOut,
    this.acOut,
    this.remainWh,
    this.soc,
    this.volts,
    this.tempC,
    this.wifi = false,
    this.mqtt = false,
    this.ssid,
    this.identity,
    this.status = 'idle',
  });

  final bool bleOn;
  final int inputW;
  final int outputW;
  final int? pvIn;
  final int? acIn;
  final int? dcOut;
  final int? acOut;
  final int? remainWh;
  final double? soc;
  final double? volts;
  final int? tempC;
  final bool wifi;
  final bool mqtt;
  final String? ssid;
  final DeviceInfo? identity;
  final String status;

  PackLive copyWith({
    bool? bleOn,
    int? inputW,
    int? outputW,
    int? pvIn,
    int? acIn,
    int? dcOut,
    int? acOut,
    int? remainWh,
    double? soc,
    double? volts,
    int? tempC,
    bool? wifi,
    bool? mqtt,
    String? ssid,
    DeviceInfo? identity,
    String? status,
  }) {
    return PackLive(
      bleOn: bleOn ?? this.bleOn,
      inputW: inputW ?? this.inputW,
      outputW: outputW ?? this.outputW,
      pvIn: pvIn ?? this.pvIn,
      acIn: acIn ?? this.acIn,
      dcOut: dcOut ?? this.dcOut,
      acOut: acOut ?? this.acOut,
      remainWh: remainWh ?? this.remainWh,
      soc: soc ?? this.soc,
      volts: volts ?? this.volts,
      tempC: tempC ?? this.tempC,
      wifi: wifi ?? this.wifi,
      mqtt: mqtt ?? this.mqtt,
      ssid: ssid ?? this.ssid,
      identity: identity ?? this.identity,
      status: status ?? this.status,
    );
  }
}

class PackHit {
  PackHit({required this.id, required this.name, required this.rssi, required this.likely});
  final String id;
  final String name;
  final int rssi;
  final bool likely;
}

bool likelyPackName(String name, String id, [String knownMac = '']) {
  final n = name.toUpperCase();
  final mac = id.replaceAll(':', '').toUpperCase();
  final known = knownMac.replaceAll(':', '').toUpperCase();
  if (known.isNotEmpty && mac == known) return true;
  return n.contains('HMD') ||
      n.contains('S2200') ||
      n.contains('MARSTEK') ||
      n.contains('MST') ||
      n.contains('HMG') ||
      n.contains('N5') ||
      n.contains('VOLTX') ||
      n.contains('B2500') ||
      n.contains('VENUS');
}

class BleTool {
  BleTool._();
  static final instance = BleTool._();

  BluetoothDevice? _device;
  BluetoothCharacteristic? _tx;
  BluetoothCharacteristic? _rx;
  StreamSubscription<List<int>>? _notify;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<BluetoothConnectionState>? _conn;
  Timer? _poll;
  Timer? _resume;
  bool _manual = false;
  bool _busy = false;
  String? savedId;
  bool get wantsLink => !_manual && savedId != null;
  Uint8List _buf = Uint8List(0);
  PackLive live = PackLive();
  final _seen = <String, BluetoothDevice>{};
  final hits = <String, PackHit>{};
  final _ctrl = StreamController<PackLive>.broadcast();
  final _hitsCtrl = StreamController<List<PackHit>>.broadcast();
  Stream<PackLive> get stream => _ctrl.stream;
  Stream<List<PackHit>> get hitsStream => _hitsCtrl.stream;
  DateTime? hushUntil;

  void hush([Duration d = const Duration(seconds: 2)]) {
    hushUntil = DateTime.now().add(d);
  }

  void _emit(PackLive next) {
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

  Future<void> startScan([String knownMac = '']) async {
    hits.clear();
    _seen.clear();
    _emitHits();
    _emit(live.copyWith(status: 'scanning'));
    await _scanSub?.cancel();
    _scanSub = FlutterBluePlus.scanResults.listen((list) {
      for (final r in list) {
        final name = r.device.platformName;
        final id = r.device.remoteId.str;
        _seen[id] = r.device;
        hits[id] = PackHit(
          id: id,
          name: name.isEmpty ? id : name,
          rssi: r.rssi,
          likely: likelyPackName(name, id, knownMac),
        );
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

  Future<void> loadSaved() async {
    savedId = (await SharedPreferences.getInstance()).getString('hak-pack-id');
  }

  Future<void> _remember(String id) async {
    savedId = id;
    await (await SharedPreferences.getInstance()).setString('hak-pack-id', id);
  }

  void _scheduleResume() {
    if (!wantsLink) return;
    _resume?.cancel();
    _resume = Timer(const Duration(seconds: 8), () {
      if (!wantsLink || _busy || live.status == 'live') return;
      unawaited(connectId(savedId!).catchError((_) => _scheduleResume()));
    });
  }

  Future<void> connect(String mac) async {
    try {
      await startScan(mac);
      await Future.any([
        FlutterBluePlus.isScanning.where((on) => !on).first,
        Future<void>.delayed(const Duration(seconds: 11)),
      ]);
      await stopScan();
      final want = mac.replaceAll(':', '').toUpperCase();
      final match = hits.values.where((h) => h.id.replaceAll(':', '').toUpperCase() == want);
      final id = match.isNotEmpty ? match.first.id : mac;
      await connectId(id);
    } catch (_) {
      await stopScan();
      await connectId(mac);
    }
  }

  Future<void> connectId(String id) async {
    _manual = false;
    _resume?.cancel();
    await _remember(id);
    if (_busy) return;
    _busy = true;
    await stopScan();
    final found = _seen[id] ?? BluetoothDevice.fromId(id);
    _emit(live.copyWith(status: 'connecting'));
    await _conn?.cancel();
    _conn = found.connectionState.listen((s) {
      if (s == BluetoothConnectionState.disconnected && !_manual && live.status == 'live') {
        _poll?.cancel();
        _emit(live.copyWith(bleOn: false, status: 'lost'));
        _scheduleResume();
      }
    });
    try {
      await found.connect(timeout: const Duration(seconds: 18), autoConnect: false);
      try {
        await found.requestMtu(247);
      } catch (_) {}
      _device = found;
      _tx = null;
      _rx = null;
      await _notify?.cancel();
      final services = await found.discoverServices();
      for (final s in services) {
        if (s.uuid.str.toLowerCase().contains('ff00')) {
          for (final c in s.characteristics) {
            final cid = c.uuid.str.toLowerCase();
            if (cid.contains('ff01')) _tx = c;
            if (cid.contains('ff02')) _rx = c;
          }
        }
      }
      if (_tx == null || _rx == null) throw Exception('missing ff01/ff02');
      await _rx!.setNotifyValue(true);
      _notify = _rx!.onValueReceived.listen(_onBytes);
      _emit(live.copyWith(bleOn: true, status: 'live'));
      await send(Cmd.deviceInfo, [0x01]);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await send(Cmd.wifiInfo, [0x01]);
      await send(Cmd.runtimeInfo, [0x01]);
      _poll?.cancel();
      _poll = Timer.periodic(const Duration(seconds: 2), (_) {
        if (hushUntil != null && DateTime.now().isBefore(hushUntil!)) return;
        send(Cmd.runtimeInfo, [0x01]);
      });
    } catch (e) {
      _emit(live.copyWith(bleOn: false, status: 'lost'));
      _scheduleResume();
      rethrow;
    } finally {
      _busy = false;
    }
  }

  Future<void> send(int cmd, [List<int> payload = const [0x01]]) async {
    final tx = _tx;
    if (tx == null) return;
    await tx.write(createCommand(cmd, payload), withoutResponse: true);
  }

  Future<void> pollLittleSun() async {
    for (final line in littleSunPoll) {
      final tx = _tx;
      if (tx == null) return;
      await tx.write(utf8.encode(line), withoutResponse: true);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    }
  }

  void _onBytes(List<int> value) {
    _buf = Uint8List.fromList([..._buf, ...value]);
    final text = utf8.decode(value, allowMalformed: true);
    final ascii = parseLittleSun(text);
    if (ascii != null) {
      _emit(live.copyWith(soc: ascii.soc, inputW: ascii.pvW?.round() ?? live.inputW, outputW: ascii.loadW?.round() ?? live.outputW));
    }
    if (text.contains('Hall') || text.contains('ssid')) {
      _emit(live.copyWith(ssid: text.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), ' ').trim()));
    }
    while (true) {
      final hit = extractFrame(_buf);
      if (hit == null) break;
      _buf = hit.rest;
      final frame = hit.frame;
      if (frame.length < 4) continue;
      final cmd = frame[3];
      final payload = frame.sublist(4, frame.length > 4 ? frame.length - 1 : 4);
      if (cmd == Cmd.deviceInfo) {
        _emit(live.copyWith(identity: parseDeviceInfo(payload)));
      } else if (cmd == Cmd.runtimeInfo) {
        final hex = frame.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
        final u16 = <String>[];
        for (var i = 0; i + 1 < payload.length; i += 2) {
          u16.add('$i=${payload[i] | (payload[i + 1] << 8)}');
        }
        debugPrint('[ble:03] ${frame.length}B hex=$hex u16=${u16.join(',')}');
        dev.log('[ble:03] $hex', name: 'BLE');
        final rt = parseRuntime(payload);
        if (rt != null) {
          _emit(live.copyWith(
            inputW: rt.inputW,
            outputW: rt.outputW,
            pvIn: rt.pvIn,
            acIn: rt.acIn,
            dcOut: rt.dcOut,
            acOut: rt.acOut,
            remainWh: rt.remainWh,
            soc: rt.soc ?? live.soc,
            tempC: rt.tempC,
            wifi: rt.wifi,
            mqtt: rt.mqtt,
          ));
        }
      }
    }
  }

  Future<void> disconnect() async {
    _manual = true;
    _resume?.cancel();
    _poll?.cancel();
    _poll = null;
    await stopScan();
    await _notify?.cancel();
    _notify = null;
    await _conn?.cancel();
    await _device?.disconnect();
    _device = null;
    _tx = null;
    _rx = null;
    _emit(PackLive(status: 'idle'));
  }
}
