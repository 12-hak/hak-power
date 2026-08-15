import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

typedef CloudRegion = String;

const regionHost = {
  'eu': 'https://eu.hamedata.com',
  'www': 'https://www.hamedata.com',
};

String md5Hex(String input) => md5.convert(utf8.encode(input)).toString();

class HameJson {
  HameJson({required this.status, required this.data, required this.raw});
  final int status;
  final dynamic data;
  final String raw;
}

class DioInstance {
  DioInstance._();
  static final instance = DioInstance._();

  static const _ua = 'Dart/2.19 (dart:io)';

  Future<HameJson> request(
    String path, {
    String method = 'GET',
    CloudRegion region = 'eu',
    String? body,
  }) async {
    final base = regionHost[region] ?? regionHost['eu']!;
    final uri = Uri.parse('$base$path');
    final headers = {
      'Accept': 'application/json, text/plain, */*',
      'User-Agent': _ua,
      if (body != null) 'Content-Type': 'application/x-www-form-urlencoded',
    };
    http.Response res;
    if (method.toUpperCase() == 'POST') {
      res = await http.post(uri, headers: headers, body: body ?? '');
    } else {
      res = await http.get(uri, headers: headers);
    }
    dynamic data = res.body;
    try {
      data = jsonDecode(res.body);
    } catch (_) {
      data = {'msg': res.body};
    }
    return HameJson(status: res.statusCode, data: data, raw: res.body);
  }
}
