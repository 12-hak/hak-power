import 'dart:async';

import 'package:flutter/material.dart';

import '../modules/common/utils/ble_tool.dart';
import '../modules/common/utils/fridge_protocol.dart';
import '../modules/common/utils/fridge_tool.dart';
import '../modules/common/utils/hak_sound.dart';
import '../modules/common/utils/juntek_tool.dart';
import '../modules/common/utils/pack_history.dart';
import 'ColorScreenPower/outdoor_module/view_models/outdoor_power_view_model.dart';
import 'Widget/base_device_home.dart';
import 'Widget/brass_monkey_face.dart';
import 'Widget/device_detail.dart';
import 'Widget/fridge_tile.dart';
import 'Widget/juntek_face.dart';
import 'Widget/power_chart.dart';
import 'Widget/soc_tile.dart';
import 'settings_page.dart';

class DashPage extends StatefulWidget {
  const DashPage({super.key});

  @override
  State<DashPage> createState() => _DashPageState();
}

class _DashPageState extends State<DashPage> {
  final vm = OutdoorPowerViewModel();
  final fridge = FridgeTool.instance;
  final juntek = JuntekTool.instance;
  StreamSubscription<PackLive>? _bleSub;
  StreamSubscription<FridgeLive>? _fridgeSub;
  StreamSubscription<JuntekLive>? _juntekSub;
  Timer? _fridgeBuzz;
  Timer? _fridgeWatch;
  bool _fridgeAlarm = false;
  bool _fridgeMuted = false;
  bool _socLowBeeped = false;
  DateTime? _driftSince;
  StreamSubscription<void>? _campSub;
  final camp = HakCamp.instance;
  final _started = DateTime.now();
  bool _fridgeBooted = false;

  @override
  void initState() {
    super.initState();
    _bleSub = vm.ble.stream.listen((ble) {
      EnergyDay.add(ble.acIn, ble.pvIn, ble.acOut, ble.dcOut);
      unawaited(PackHistory.push('pvIn', ble.pvIn?.toDouble()));
      unawaited(PackHistory.push('acIn', ble.acIn?.toDouble()));
      unawaited(PackHistory.push('dcOut', ble.dcOut?.toDouble()));
      unawaited(PackHistory.push('acOut', ble.acOut?.toDouble()));
      unawaited(PackHistory.push('soc', ble.soc));
      if (ble.soc != null) {
        if (ble.soc! <= 20 && !_socLowBeeped) {
          _socLowBeeped = true;
          unawaited(HakSound.tick());
        }
        if (ble.soc! > 22) _socLowBeeped = false;
      }
      if (mounted) setState(() {});
    });
    _fridgeSub = fridge.stream.listen((live) {
      unawaited(PackHistory.push('fridgeL', live.leftC?.toDouble(), sparkMax: 720, sparkGapMs: 120000));
      unawaited(PackHistory.push('fridgeR', live.rightC?.toDouble(), sparkMax: 720, sparkGapMs: 120000));
      unawaited(PackHistory.push('fridgeLSet', live.leftTarget?.toDouble(), sparkMax: 720, sparkGapMs: 120000));
      unawaited(PackHistory.push('fridgeRSet', live.rightTarget?.toDouble(), sparkMax: 720, sparkGapMs: 120000));
      _checkFridgeAlarm();
      _onFridgeTemp(live);
      if (mounted) setState(() {});
    });
    _juntekSub = juntek.stream.listen((_) {
      if (mounted) setState(() {});
    });
    _fridgeBuzz = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_fridgeAlarm && !_fridgeMuted) unawaited(HakSound.buzz());
    });
    _fridgeWatch = Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_tickWatch());
    });
    _campSub = camp.stream.listen((_) {
      if (mounted) setState(() {});
    });
    unawaited(_boot());
  }

  Future<void> _boot() async {
    await camp.load();
    await EnergyDay.load();
    await vm.ble.loadSaved();
    await fridge.loadSaved();
    await juntek.loadSaved();
    _fridgeBooted = true;
    unawaited(vm.ble.connect(vm.ble.savedId ?? packMac).catchError((_) {}));
    if (fridge.savedId != null) {
      unawaited(fridge.connectId(fridge.savedId!).catchError((_) {}));
    }
    if (juntek.savedId != null) {
      unawaited(juntek.connectId(juntek.savedId!).catchError((_) {}));
    }
  }

  Future<void> _tickWatch() async {
    final nativeMuted = await HakSound.fridgeMuted();
    if (!mounted) return;
    if (nativeMuted && !_fridgeMuted) _fridgeMuted = true;
    _checkFridgeAlarm();
    if (mounted) setState(() {});
  }

  bool get _fridgeLive {
    final last = fridge.lastRx;
    return fridge.live.status == 'live' && last != null && DateTime.now().difference(last) < const Duration(seconds: 20);
  }

  void _clearFridgeAlarm() {
    if (!_fridgeAlarm && !_fridgeMuted) return;
    _fridgeAlarm = false;
    _fridgeMuted = false;
    unawaited(HakSound.muteFridge(false));
    if (mounted) setState(() {});
  }

  void _armFridgeAlarm() {
    if (!fridge.wantsLink) return;
    if (_fridgeAlarm) {
      if (!_fridgeMuted) unawaited(HakSound.buzz());
      return;
    }
    _fridgeAlarm = true;
    if (!_fridgeMuted) unawaited(HakSound.buzz());
    if (mounted) setState(() {});
  }

  void _muteFridgeUntilReconnect() {
    if (_fridgeMuted) return;
    _fridgeMuted = true;
    unawaited(HakSound.muteFridge(true));
    if (mounted) setState(() {});
  }

  void _checkFridgeAlarm() {
    if (!_fridgeBooted) return;
    if (!fridge.wantsLink) {
      _clearFridgeAlarm();
      return;
    }
    if (_fridgeLive) {
      _clearFridgeAlarm();
      return;
    }
    final last = fridge.lastRx;
    final unseen = DateTime.now().difference(last ?? _started);
    if (unseen >= const Duration(minutes: 10)) _armFridgeAlarm();
  }

  void _onFridgeTemp(FridgeLive live) {
    if (live.status != 'live') {
      _driftSince = null;
      return;
    }
    bool off(int? temp, int? set) => temp != null && set != null && (temp - set).abs() >= 5;
    if (off(live.leftC, live.leftTarget) || off(live.rightC, live.rightTarget)) {
      _driftSince ??= DateTime.now();
      if (DateTime.now().difference(_driftSince!) >= const Duration(minutes: 3)) {
        unawaited(HakSound.tick());
      }
    } else {
      _driftSince = null;
    }
  }

  @override
  void dispose() {
    _bleSub?.cancel();
    _fridgeSub?.cancel();
    _juntekSub?.cancel();
    _campSub?.cancel();
    _fridgeBuzz?.cancel();
    _fridgeWatch?.cancel();
    super.dispose();
  }

  Future<void> _openChart(String title, String unit, String series) async {
    final local = await PackHistory.series(series);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PowerChartPage(title: title, unit: unit, local: local)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dash = Scaffold(
      backgroundColor: const Color(0xFF05080A),
      body: SafeArea(
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 44, 8),
                child: _faces(),
              ),
            ),
            if (_fridgeAlarm)
              Positioned(
                top: 8,
                left: 8,
                right: 52,
                child: GestureDetector(
                  onTap: _muteFridgeUntilReconnect,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _fridgeMuted ? const Color(0xFF2A3034) : const Color(0xE6C62828),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _fridgeMuted ? Icons.volume_off : Icons.volume_up,
                          size: 18,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _fridgeMuted ? 'FRIDGE MUTED UNTIL RECONNECT' : 'FRIDGE OFFLINE — TAP TO MUTE',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 4,
              right: 4,
              child: IconButton(
                icon: const Icon(Icons.settings, color: Color(0xFF6A767C)),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SettingsPage(vm: vm),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (!camp.night) return dash;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.85, 0.05, 0.02, 0, 0,
        0.05, 0.12, 0.02, 0, 0,
        0.02, 0.02, 0.10, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: dash,
    );
  }

  Future<void> _openPack() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeviceDetailPage(
          title: 'VoltX',
          child: StreamBuilder(
            stream: vm.ble.stream,
            initialData: vm.ble.live,
            builder: (_, __) => BaseDeviceHome(
              live: vm.ble.live,
              online: vm.ble.readingsLive,
              timeLabel: vm.timeLabel(),
              lightLabel: EnergyDay.hoursLeft(vm.ble.live.remainWh, vm.ble.live.acOut, vm.ble.live.dcOut),
              heard: heardAgo(vm.ble.lastRx),
              source: EnergyDay.source(vm.ble.live.acIn, vm.ble.live.pvIn),
              today: '${EnergyDay.inWh.toStringAsFixed(0)} in · ${EnergyDay.outWh.toStringAsFixed(0)} out',
              onSoc: () => _openChart('SOC', '%', 'soc'),
              onPvIn: () => _openChart('PV / CAR IN', 'W', 'pvIn'),
              onAcIn: () => _openChart('AC IN', 'W', 'acIn'),
              onDcOut: () => _openChart('DC OUT', 'W', 'dcOut'),
              onAcOut: () => _openChart('AC OUT', 'W', 'acOut'),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openFridge() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeviceDetailPage(
          title: 'Brass Monkey',
          child: StreamBuilder(
            stream: fridge.stream,
            initialData: fridge.live,
            builder: (_, __) => BrassMonkeyFace(
              live: fridge.live,
              heard: heardAgo(fridge.lastRx),
              setLeft: fridge.wantLeft ?? fridge.live.leftTarget,
              setRight: fridge.wantRight ?? fridge.live.rightTarget,
              updatingLeft: fridge.leftBusy,
              updatingRight: fridge.rightBusy,
              onLeft: () => _openChart('TEMP LEFT', '°', 'fridgeL'),
              onRight: () => _openChart('TEMP RIGHT', '°', 'fridgeR'),
              onNudgeLeft: (d) => unawaited(fridge.nudgeLeft(d).catchError((_) {})),
              onNudgeRight: (d) => unawaited(fridge.nudgeRight(d).catchError((_) {})),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openJuntek() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DeviceDetailPage(
          title: 'Juntek',
          child: StreamBuilder(
            stream: juntek.stream,
            initialData: juntek.live,
            builder: (_, __) => JuntekFace(live: juntek.live, heard: heardAgo(juntek.lastRx)),
          ),
        ),
      ),
    );
  }

  bool get _packOn => vm.ble.readingsLive || vm.ble.live.status == 'live';
  bool get _fridgeOn => fridge.live.status == 'live';
  bool get _juntekOn => juntek.live.status == 'live';

  double? _packWatts(PackLive live) {
    return (live.inputW - live.outputW).toDouble();
  }

  double? _juntekWatts(JuntekLive live) {
    final w = live.watts;
    if (w == null) return null;
    if (live.charging == false) return -w.abs();
    if (live.charging == true) return w.abs();
    return w;
  }

  Widget _faces() {
    final portrait = MediaQuery.orientationOf(context) == Orientation.portrait;
    final tiles = <Widget>[
      if (_packOn)
        SocTile(
          label: 'VOLTX',
          soc: vm.ble.live.soc,
          online: vm.ble.readingsLive,
          watts: _packWatts(vm.ble.live),
          subtitle: vm.ble.live.remainWh != null ? '${vm.ble.live.remainWh} Wh' : null,
          onTap: () => unawaited(_openPack()),
        ),
      if (_fridgeOn)
        FridgeTile(
          leftC: fridge.live.leftC,
          rightC: fridge.live.rightC,
          unit: fridge.live.unit,
          onTap: () => unawaited(_openFridge()),
        ),
      if (_juntekOn)
        SocTile(
          label: 'JUNTEK',
          soc: juntek.live.soc,
          watts: _juntekWatts(juntek.live),
          subtitle: juntek.live.ahRemain != null ? '${juntek.live.ahRemain!.toStringAsFixed(1)} Ah' : null,
          onTap: () => unawaited(_openJuntek()),
        ),
    ];
    if (tiles.isEmpty) {
      return const Center(
        child: Text(
          'Connect pack, fridge or Juntek in Settings',
          style: TextStyle(color: Color(0xFF6A8088), fontSize: 13),
        ),
      );
    }
    return Flex(
      direction: portrait ? Axis.vertical : Axis.horizontal,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) SizedBox(width: portrait ? 0 : 10, height: portrait ? 10 : 0),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }
}
