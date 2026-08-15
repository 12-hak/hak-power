import 'dart:io';

const mqttHosts = [
  'a40nr6osvmmaw-ats.iot.eu-west-3.amazonaws.com',
  'a40nr6osvmmaw-ats.iot.eu-central-1.amazonaws.com',
];

Future<String> probeMqttHosts() async {
  final bits = <String>[];
  for (final host in mqttHosts) {
    try {
      final s = await SecureSocket.connect(host, 8883, timeout: const Duration(seconds: 8));
      bits.add('$host TLS ${s.selectedProtocol ?? 'ok'}');
      await s.close();
    } catch (e) {
      bits.add('$host $e');
    }
  }
  return bits.join(' | ');
}
