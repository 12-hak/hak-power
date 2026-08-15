const mqttClientPrefix = 'hm_appmqtt_';
const topicPrefixes = ['hame_energy/', 'marstek_energy/'];

List<String> pzSubscribeTopics(String type, String mac) {
  final id = mac.replaceAll(':', '').toLowerCase();
  return topicPrefixes.map((p) => '$p$type/device/$id/ctrl').toList();
}

String pzPublishTopic(String type, String mac) {
  final id = mac.replaceAll(':', '').toLowerCase();
  return 'hame_energy/$type/App/$id/ctrl';
}

const mqttPollBurst = [
  'cd=01',
  'cd=15,vs=',
  'cd=14',
  'cd=15',
  'cd=1',
  'cd=03,md=1',
  'cd=03,md=0',
  'cd=8,p1=',
];
