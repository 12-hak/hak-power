import 'dart:typed_data';

const fridgeService = '00001234-0000-1000-8000-00805f9b34fb';
const fridgeTx = '00001235-0000-1000-8000-00805f9b34fb';
const fridgeRx = '00001236-0000-1000-8000-00805f9b34fb';
const fridgePrefixes = ['A1-', 'AK1-', 'AK2-', 'AK3-', 'WT-', 'BC', 'K25'];

const fridgeBind = 0x00;
const fridgeQuery = 0x01;
const fridgeSetOther = 0x02;
const fridgeSetLeft = 0x05;
const fridgeSetRight = 0x06;

int signed8(int n) => n > 127 ? n - 256 : n;

int toU8(int n) => n < 0 ? (n + 256) & 0xff : n & 0xff;

Uint8List fridgeFrame(int cmd, [List<int> data = const []]) {
  final len = 1 + data.length + 2;
  final f = Uint8List(3 + len);
  f[0] = 0xfe;
  f[1] = 0xfe;
  f[2] = len;
  f[3] = cmd;
  for (var i = 0; i < data.length; i++) {
    f[4 + i] = data[i];
  }
  var sum = 0;
  for (final b in f) {
    sum = (sum + b) & 0xffff;
  }
  f[f.length - 2] = (sum >> 8) & 0xff;
  f[f.length - 1] = sum & 0xff;
  return f;
}

class FridgeLive {
  FridgeLive({
    this.on = false,
    this.eco = false,
    this.locked = false,
    this.leftC,
    this.rightC,
    this.leftTarget,
    this.rightTarget,
    this.volts,
    this.batPct,
    this.unit = 'C',
    this.dual = false,
    this.status = 'idle',
    this.error,
    this.batSaver = 0,
    this.tempMax,
    this.tempMin,
    this.leftRetDiff,
    this.startDelay = 0,
    this.leftTCHot,
    this.leftTCMid,
    this.leftTCCold,
    this.leftTCHalt,
    this.rightRetDiff,
    this.rightTCHot,
    this.rightTCMid,
    this.rightTCCold,
    this.rightTCHalt,
  });

  final bool on;
  final bool eco;
  final bool locked;
  final int? leftC;
  final int? rightC;
  final int? leftTarget;
  final int? rightTarget;
  final double? volts;
  final int? batPct;
  final String unit;
  final bool dual;
  final String status;
  final String? error;
  final int batSaver;
  final int? tempMax;
  final int? tempMin;
  final int? leftRetDiff;
  final int startDelay;
  final int? leftTCHot;
  final int? leftTCMid;
  final int? leftTCCold;
  final int? leftTCHalt;
  final int? rightRetDiff;
  final int? rightTCHot;
  final int? rightTCMid;
  final int? rightTCCold;
  final int? rightTCHalt;

  int get minC => tempMin ?? -20;
  int get maxC => tempMax ?? 20;

  FridgeLive copyWith({
    bool? on,
    bool? eco,
    bool? locked,
    int? leftC,
    int? rightC,
    int? leftTarget,
    int? rightTarget,
    double? volts,
    int? batPct,
    String? unit,
    bool? dual,
    String? status,
    String? error,
  }) {
    return FridgeLive(
      on: on ?? this.on,
      eco: eco ?? this.eco,
      locked: locked ?? this.locked,
      leftC: leftC ?? this.leftC,
      rightC: rightC ?? this.rightC,
      leftTarget: leftTarget ?? this.leftTarget,
      rightTarget: rightTarget ?? this.rightTarget,
      volts: volts ?? this.volts,
      batPct: batPct ?? this.batPct,
      unit: unit ?? this.unit,
      dual: dual ?? this.dual,
      status: status ?? this.status,
      error: error,
      batSaver: batSaver,
      tempMax: tempMax,
      tempMin: tempMin,
      leftRetDiff: leftRetDiff,
      startDelay: startDelay,
      leftTCHot: leftTCHot,
      leftTCMid: leftTCMid,
      leftTCCold: leftTCCold,
      leftTCHalt: leftTCHalt,
      rightRetDiff: rightRetDiff,
      rightTCHot: rightTCHot,
      rightTCMid: rightTCMid,
      rightTCCold: rightTCCold,
      rightTCHalt: rightTCHalt,
    );
  }
}

FridgeLive? parseFridgeQuery(Uint8List p) {
  if (p.length < 18) return null;
  final dual = p.length >= 28;
  return FridgeLive(
    locked: p[0] == 1,
    on: p[1] == 1,
    eco: p[2] == 1,
    batSaver: p[3],
    leftTarget: signed8(p[4]),
    tempMax: signed8(p[5]),
    tempMin: signed8(p[6]),
    leftRetDiff: signed8(p[7]),
    startDelay: p[8],
    unit: p[9] == 1 ? 'F' : 'C',
    leftTCHot: signed8(p[10]),
    leftTCMid: signed8(p[11]),
    leftTCCold: signed8(p[12]),
    leftTCHalt: signed8(p[13]),
    leftC: signed8(p[14]),
    batPct: p[15] == 0x7f ? null : p[15],
    volts: p[16] + p[17] / 10,
    dual: dual,
    rightTarget: dual ? signed8(p[18]) : null,
    rightRetDiff: dual ? signed8(p[21]) : null,
    rightTCHot: dual ? signed8(p[22]) : null,
    rightTCMid: dual ? signed8(p[23]) : null,
    rightTCCold: dual ? signed8(p[24]) : null,
    rightTCHalt: dual ? signed8(p[25]) : null,
    rightC: dual ? signed8(p[26]) : null,
    status: 'live',
  );
}

List<int> buildSetOtherPayload(FridgeLive s) {
  final base = [
    s.locked ? 1 : 0,
    s.on ? 1 : 0,
    s.eco ? 1 : 0,
    s.batSaver,
    toU8(s.leftTarget ?? 0),
    toU8(s.tempMax ?? 20),
    toU8(s.tempMin ?? -20),
    toU8(s.leftRetDiff ?? 1),
    s.startDelay & 0xff,
    s.unit == 'F' ? 1 : 0,
    toU8(s.leftTCHot ?? 0),
    toU8(s.leftTCMid ?? 0),
    toU8(s.leftTCCold ?? 0),
    toU8(s.leftTCHalt ?? 0),
  ];
  if (!s.dual) return base;
  return [
    ...base,
    toU8(s.rightTarget ?? s.leftTarget ?? 0),
    0,
    0,
    toU8(s.rightRetDiff ?? s.leftRetDiff ?? 1),
    toU8(s.rightTCHot ?? 0),
    toU8(s.rightTCMid ?? 0),
    toU8(s.rightTCCold ?? 0),
    toU8(s.rightTCHalt ?? 0),
    0,
    0,
    0,
  ];
}

List<Uint8List> extractFridgeFrames(Uint8List buf) {
  final out = <Uint8List>[];
  var i = 0;
  while (i + 5 <= buf.length) {
    if (buf[i] != 0xfe || buf[i + 1] != 0xfe) {
      i += 1;
      continue;
    }
    final total = 3 + buf[i + 2];
    if (i + total > buf.length) break;
    out.add(buf.sublist(i, i + total));
    i += total;
  }
  return out;
}
