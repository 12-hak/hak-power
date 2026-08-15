import 'dart:convert';
import 'dart:typed_data';

const serviceUuid = '0000ff00-0000-1000-8000-00805f9b34fb';
const txCharUuid = '0000ff01-0000-1000-8000-00805f9b34fb';
const rxCharUuid = '0000ff02-0000-1000-8000-00805f9b34fb';

const startByte = 0x73;
const identifierByte = 0x23;

class Cmd {
  static const setRegion = 0x02;
  static const runtimeInfo = 0x03;
  static const deviceInfo = 0x04;
  static const setWifi = 0x05;
  static const wifiInfo = 0x08;
  static const resetMqtt = 0x21;
}

const littleSunPoll = [
  'cd=01',
  'cd=15,vs=',
  'cd=14',
  'cd=15',
  'cd=1',
  'cd=03,md=1',
  'cd=03,md=0',
  'cd=8,p1=',
];

Uint8List createCommand(int cmd, [List<int> payload = const []]) {
  final header = [startByte, 0, identifierByte, cmd];
  header[1] = header.length + payload.length + 1;
  final message = [...header, ...payload];
  var xor = 0;
  for (final b in message) {
    xor ^= b;
  }
  message.add(xor);
  return Uint8List.fromList(message);
}

({Uint8List frame, Uint8List rest})? extractFrame(Uint8List buffer) {
  final start = buffer.indexOf(startByte);
  if (start < 0 || buffer.length < start + 2) return null;
  final len = buffer[start + 1];
  if (len < 5) return null;
  if (buffer.length > start + 3 &&
      buffer[start + 2] == identifierByte &&
      buffer[start + 3] == Cmd.runtimeInfo &&
      len == 0x10 &&
      buffer.length >= start + 48) {
    return (frame: buffer.sublist(start, start + 48), rest: buffer.sublist(start + 48));
  }
  if (buffer.length < start + len) return null;
  return (frame: buffer.sublist(start, start + len), rest: buffer.sublist(start + len));
}

int _u16(Uint8List p, int i) {
  if (i + 1 >= p.length) return 0;
  return p[i] | (p[i + 1] << 8);
}

class RuntimeInfo {
  RuntimeInfo({
    required this.inputW,
    required this.outputW,
    this.pvIn,
    this.acIn,
    this.dcOut,
    this.acOut,
    this.remainWh,
    this.soc,
    this.tempC,
    this.wifi = false,
    this.mqtt = false,
    this.hour,
    this.minute,
  });
  final int inputW;
  final int outputW;
  final int? pvIn;
  final int? acIn;
  final int? dcOut;
  final int? acOut;
  final int? remainWh;
  final double? soc;
  final int? tempC;
  final bool wifi;
  final bool mqtt;
  final int? hour;
  final int? minute;
}

RuntimeInfo? parseRuntime(Uint8List payload) {
  if (payload.length < 23) return null;
  final remainWh = _u16(payload, 11);
  final socRaw = _u16(payload, 13);
  double? soc;
  if (socRaw > 100 && socRaw <= 10000) {
    soc = socRaw / 100;
  } else if (socRaw > 0 && socRaw <= 100) {
    soc = socRaw.toDouble();
  }
  final acIn = _u16(payload, 15);
  final pvIn = _u16(payload, 17);
  final acOut = _u16(payload, 19);
  final dcOut = _u16(payload, 21);
  return RuntimeInfo(
    inputW: acIn + pvIn,
    outputW: acOut + dcOut,
    acIn: acIn,
    acOut: acOut,
    pvIn: pvIn,
    dcOut: dcOut,
    remainWh: remainWh > 0 && remainWh < 4000 ? remainWh : null,
    soc: soc,
  );
}

class DeviceInfo {
  DeviceInfo({this.type, this.id, this.mac, this.raw = ''});
  final String? type;
  final String? id;
  final String? mac;
  final String raw;
}

DeviceInfo parseDeviceInfo(Uint8List payload) {
  final decoded = utf8.decode(payload, allowMalformed: true).replaceAll('\u0000', '');
  final start = decoded.indexOf(RegExp(r'[A-Za-z]'));
  final text = (start >= 0 ? decoded.substring(start) : decoded).trim();
  final fields = <String, String>{};
  for (final part in text.split(RegExp(r'[\n,;]+'))) {
    final m = RegExp(r'^([a-zA-Z_][a-zA-Z0-9_]*)\s*[:=]\s*(.+)$').firstMatch(part.trim());
    if (m != null) fields[m.group(1)!.toLowerCase()] = m.group(2)!.trim();
  }
  return DeviceInfo(
    type: fields['type'] ?? fields['model'],
    id: fields['id'] ?? fields['sn'] ?? fields['devid'],
    mac: fields['mac'],
    raw: text,
  );
}

class LittleSunNow {
  LittleSunNow({this.soc, this.pvW, this.loadW});
  final double? soc;
  final double? pvW;
  final double? loadW;
}

double? _normSoc(num? v) {
  if (v == null) return null;
  final n = v.toDouble();
  if (n > 100 && n <= 1000) return n / 10;
  if (n > 0 && n <= 100) return n;
  return null;
}

LittleSunNow? parseLittleSun(String text) {
  final fields = <String, double>{};
  for (final part in text.split(RegExp(r'[,\n;]+'))) {
    final m = RegExp(r'^([A-Za-z0-9_]+)\s*[:=]\s*(-?\d+(?:\.\d+)?)').firstMatch(part.trim());
    if (m != null) fields[m.group(1)!.toLowerCase()] = double.parse(m.group(2)!);
  }
  final soc = _normSoc(fields['soc']) ?? _normSoc(fields['pe']) ?? _normSoc(fields['pecentage']);
  if (soc == null && fields['mb_pv_ttal_pwr'] == null && !text.contains('cd=')) return null;
  return LittleSunNow(
    soc: soc,
    pvW: fields['mb_pv_ttal_pwr'] ?? fields['w1'],
    loadW: fields['mb_ttal_lad_s_ratd_at'] ?? fields['g1'],
  );
}
