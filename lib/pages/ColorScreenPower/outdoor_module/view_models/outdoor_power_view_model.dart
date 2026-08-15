import '../../../../modules/common/utils/ble_tool.dart';

const packMac = 'AC:D9:29:37:9A:D3';
const packDevid = '360111505357363937187230';
const packType = 'HMD-N5';

class OutdoorPowerViewModel {
  OutdoorPowerViewModel();

  final ble = BleTool.instance;

  String timeLabel() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
  }

  String lightLabel(PackLive live) {
    final out = (live.dcOut ?? 0) + (live.acOut ?? 0);
    if (out <= 5) return '—';
    final soc = live.soc ?? 0;
    final hours = (2240 * (soc / 100)) / out;
    if (!hours.isFinite || hours <= 0) return '—';
    if (hours >= 100) return '99+';
    return hours.toStringAsFixed(1);
  }
}
