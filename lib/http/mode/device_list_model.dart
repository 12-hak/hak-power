class CloudDevice {
  CloudDevice({
    this.devid,
    this.name,
    this.type,
    this.sn,
    this.version,
    this.soc,
    this.isIllegal,
    this.reportTime,
    this.mac,
  });

  final String? devid;
  final String? name;
  final String? type;
  final String? sn;
  final String? version;
  final double? soc;
  final String? isIllegal;
  final String? reportTime;
  final String? mac;

  factory CloudDevice.fromJson(Map<String, dynamic> json) {
    double? soc;
    final raw = json['soc'] ?? json['pecentage'] ?? json['pe'];
    if (raw is num) soc = raw.toDouble();
    if (raw is String) soc = double.tryParse(raw);
    if (soc != null && soc > 100 && soc <= 1000) soc = soc / 10;
    return CloudDevice(
      devid: json['devid']?.toString(),
      name: json['name']?.toString(),
      type: json['type']?.toString(),
      sn: json['sn']?.toString(),
      version: json['version']?.toString(),
      soc: soc,
      isIllegal: json['is_illegal']?.toString(),
      reportTime: json['report_time']?.toString(),
      mac: json['mac']?.toString(),
    );
  }
}
