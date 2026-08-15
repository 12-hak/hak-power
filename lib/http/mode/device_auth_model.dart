class DeviceAuthModel {
  DeviceAuthModel({this.code, this.msg, this.data});

  final int? code;
  final String? msg;
  final Map<String, dynamic>? data;

  factory DeviceAuthModel.fromJson(Map<String, dynamic> json) {
    final inner = json['data'];
    return DeviceAuthModel(
      code: json['code'] is num ? (json['code'] as num).toInt() : int.tryParse('${json['code']}'),
      msg: json['msg']?.toString(),
      data: inner is Map<String, dynamic> ? inner : null,
    );
  }

  bool get ok => code == 1 || code == 0;
}
