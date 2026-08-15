import 'dart:async';

import 'package:flutter/material.dart';

import '../modules/common/utils/ble_tool.dart';
import '../modules/common/utils/fridge_protocol.dart';
import '../modules/common/utils/fridge_tool.dart';
import '../modules/common/utils/hak_sound.dart';
import '../modules/common/utils/pack_history.dart';
import 'ColorScreenPower/outdoor_module/view_models/outdoor_power_view_model.dart';
import 'Widget/base_device_home.dart';
import 'Widget/brass_monkey_face.dart';
import 'Widget/power_chart.dart';
import 'settings_page.dart';

class DashPage extends StatefulWidget {
  const DashPage({super.key});

  @override
  State<DashPage> createState() => _DashPageState();
}

class _DashPageState extends State<DashPage> {
  final vm = OutdoorPowerViewModel();
  final fridge = FridgeTool.instance;
  StreamSubscription<PackLive>? _bleSub;
  StreamSubscription<FridgeLive>? _fridgeSub;
  Timer? _fridgeBuzz;
  Timer? _fridgeWatch;
  bool _fridgeAlarm = false;
  bool _fridgeMuted = false;
  bool _socLowBeeped = false;
  DateTime? _driftSince;
  StreamSubscription<void>? _campSub;
  final camp = HakCamp.instance;
  final _started = DateTime.now();

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
      _onFridgeStatus(live.status);
      _onFridgeTemp(live);
      if (mounted) setState(() {});
    });
    _fridgeBuzz = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_fridgeAlarm && !_fridgeMuted) unawaited(HakSound.buzz());
    });
    _fridgeWatch = Timer.periodic(const Duration(seconds: 2), (_) {
      if (mounted) setState(() {});
      final s = fridge.live.status;
      final waited = DateTime.now().difference(_started) > const Duration(seconds: 10);
      final stale = fridge.lastRx != null && DateTime.now().difference(fridge.lastRx!) > const Duration(seconds: 8);
      if (s == 'live' && !stale) {
        _clearFridgeAlarm();
        return;
      }
      if (!fridge.wantsLink) return;
      if (s == 'offline' || s == 'lost' || s == 'no fridge' || s == 'fail' || s == 'no gatt' || s == 'idle') {
        _armFridgeAlarm();
        return;
      }
      if (waited && s != 'live') _armFridgeAlarm();
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
    unawaited(vm.ble.connect(vm.ble.savedId ?? packMac).catchError((_) {}));
    if (fridge.savedId != null) {
      unawaited(fridge.connectId(fridge.savedId!).catchError((_) {}));
    }
  }

  void _clearFridgeAlarm() {
    if (!_fridgeAlarm && !_fridgeMuted) return;
    _fridgeAlarm = false;
    _fridgeMuted = false;
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

  void _onFridgeStatus(String status) {
    if (status == 'live') {
      _clearFridgeAlarm();
      return;
    }
    final down = status == 'no fridge' ||
        status == 'no gatt' ||
        status == 'lost' ||
        status == 'fail' ||
        status == 'idle' ||
        status == 'offline';
    if (down) _armFridgeAlarm();
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
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                  Expanded(
                    child: BaseDeviceHome(
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
                  const SizedBox(width: 10),
                  Expanded(
                    child: BrassMonkeyFace(
                      live: fridge.live,
                      heard: heardAgo(fridge.lastRx),
                      pendingLeft: fridge.pendingLeft,
                      pendingRight: fridge.pendingRight,
                      onLeft: () => _openChart('TEMP LEFT', '°', 'fridgeL'),
                      onRight: () => _openChart('TEMP RIGHT', '°', 'fridgeR'),
                      onNudgeLeft: (d) => unawaited(fridge.nudgeLeft(d).catchError((_) {})),
                      onNudgeRight: (d) => unawaited(fridge.nudgeRight(d).catchError((_) {})),
                    ),
                  ),
                ],
              ),
              ),
            ),
            if (_fridgeAlarm)
              Positioned(
                top: 8,
                left: 0,
                right: 48,
                child: Center(
                  child: GestureDetector(
                    onTap: () => setState(() => _fridgeMuted = !_fridgeMuted),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: _fridgeMuted ? const Color(0xFF2A3034) : const Color(0xE6C62828),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _fridgeMuted ? Icons.volume_off : Icons.volume_up,
                            size: 18,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _fridgeMuted ? 'FRIDGE OFFLINE — MUTED' : 'FRIDGE OFFLINE — TAP TO MUTE',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.6,
                            ),
                          ),
                        ],
                      ),
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
}
