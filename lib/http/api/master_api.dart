import '../dio_instance.dart';
import '../mode/device_auth_model.dart';
import '../mode/device_list_model.dart';

class CloudSession {
  CloudSession({required this.email, required this.token, this.region = 'eu'});
  final String email;
  final String token;
  final CloudRegion region;
}

class MasterApi {
  MasterApi._();
  static final instance = MasterApi._();
  final _http = DioInstance.instance;

  Future<CloudSession> login(String email, String password, {CloudRegion region = 'eu'}) async {
    final pwd = md5Hex(password);
    final qs = Uri(queryParameters: {'mailbox': email, 'pwd': pwd}).query;
    final res = await _http.request('/app/Solar/v2_get_device.php?$qs', method: 'POST', region: region);
    final map = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    final token = _pickToken(map);
    if (token == null) {
      throw Exception(map['msg']?.toString() ?? 'login failed ${res.raw}');
    }
    return CloudSession(email: email, token: token, region: region);
  }

  Future<List<CloudDevice>> getDeviceList(CloudSession s) async {
    final res = await _http.request(
      '/ems/api/v1/getDeviceList?token=${Uri.encodeQueryComponent(s.token)}',
      region: s.region,
    );
    final map = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    final list = map['data'] ?? map['device_list'];
    if (list is List) {
      return list.whereType<Map>().map((e) => CloudDevice.fromJson(Map<String, dynamic>.from(e))).toList();
    }
    return [];
  }

  Future<HameJson> checkDeviceSn(CloudSession s, {required String devid, required String mac, String type = 'HMD-N5'}) {
    final qs = _qs(s, {'sn': devid, 'devid': devid, 'mac': mac.replaceAll(':', '').toLowerCase(), 'type': type});
    return _http.request('/ems/api/v1/checkDeviceSn?$qs', method: 'POST', region: s.region);
  }

  Future<DeviceAuthModel> checkDeviceAuthInfo(
    CloudSession s, {
    required String devid,
    required String mac,
    String type = 'HMD-N5',
  }) async {
    final qs = _qs(s, {'devid': devid, 'mac': mac.replaceAll(':', '').toLowerCase(), 'type': type, 'sn': devid});
    final res = await _http.request('/ems/api/v1/checkDeviceAuthInfo?$qs', region: s.region);
    final map = res.data is Map ? Map<String, dynamic>.from(res.data as Map) : <String, dynamic>{};
    return DeviceAuthModel.fromJson(map);
  }

  Future<HameJson> checkAuth(CloudSession s, {required String devid, required String mac, String type = 'HMD-N5'}) {
    final qs = _qs(s, {'devid': devid, 'mac': mac.replaceAll(':', '').toLowerCase(), 'type': type});
    return _http.request('/ems/api/v1/checkAuth?$qs', region: s.region);
  }

  Future<HameJson> deviceBound(CloudSession s, String devid) async {
    final qs = _qs(s, {});
    return _http.request('/ems/api/v1/deviceBound/$devid?$qs', region: s.region);
  }

  Future<HameJson> getDeviceMqttStatus(CloudSession s, String devid) {
    final qs = _qs(s, {'devid': devid});
    return _http.request('/ems/api/v1/getDeviceMqttStatus?$qs', region: s.region);
  }

  Future<HameJson> getDevMsStatus(CloudSession s, String devid) => getDeviceMqttStatus(s, devid);

  Future<HameJson> getMqttCrvCfg(CloudSession s, String devid) {
    final qs = _qs(s, {'devid': devid});
    return _http.request('/ems/api/v1/getMqttCrvCfg?$qs', region: s.region);
  }

  Future<HameJson> getIsStatus(CloudSession s, String devid) {
    final qs = _qs(s, {'devid': devid});
    return _http.request('/ems/api/v1/getIsStatus?$qs', region: s.region);
  }

  Future<HameJson> getRealtimeSoc(CloudSession s, String devid) {
    final qs = _qs(s, {'devid': devid});
    return _http.request('/ems/api/v1/getRealtimeSoc?$qs', region: s.region);
  }

  Future<HameJson> checkMqtt(CloudSession s, {required String devid, required String mac, String type = 'HMD-N5'}) {
    final qs = _qs(s, {'devid': devid, 'mac': mac.replaceAll(':', '').toLowerCase(), 'type': type});
    return _http.request('/app/neng/v2_check_mqtt.php?$qs', method: 'POST', region: s.region);
  }

  Future<HameJson> history(CloudSession s, String path, {required String devid, String? date, String? mac}) {
    final extra = <String, String>{'devid': devid};
    if (date != null) extra['date'] = date;
    if (mac != null) extra['mac'] = mac.replaceAll(':', '').toLowerCase();
    return _http.request('$path?${_qs(s, extra)}', region: s.region);
  }

  String _qs(CloudSession s, Map<String, String> extra) {
    return Uri(queryParameters: {'token': s.token, ...extra}).query;
  }

  String? _pickToken(Map<String, dynamic> data) {
    for (final key in ['token', 'access_token']) {
      final v = data[key];
      if (v is String && v.trim().length > 8) return v.trim();
    }
    final inner = data['data'];
    if (inner is String && inner.length > 8) return inner.trim();
    if (inner is Map) {
      final nested = Map<String, dynamic>.from(inner);
      for (final key in ['token', 'access_token']) {
        final v = nested[key];
        if (v is String && v.trim().length > 8) return v.trim();
      }
    }
    return null;
  }
}
