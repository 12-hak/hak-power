import 'dart:async';

import 'package:flutter/material.dart';

import '../../modules/common/utils/ble_tool.dart';
import '../ColorScreenPower/outdoor_module/view_models/outdoor_power_view_model.dart';

class PackPickDialog extends StatefulWidget {
  const PackPickDialog({super.key});

  @override
  State<PackPickDialog> createState() => _PackPickDialogState();
}

class _PackPickDialogState extends State<PackPickDialog> {
  List<PackHit> hits = [];
  StreamSubscription<List<PackHit>>? _sub;
  String? err;
  bool linking = false;

  @override
  void initState() {
    super.initState();
    _sub = BleTool.instance.hitsStream.listen((list) {
      if (mounted) setState(() => hits = list);
    });
    unawaited(BleTool.instance.startScan(packMac).catchError((e) {
      if (mounted) setState(() => err = e.toString());
    }));
  }

  @override
  void dispose() {
    _sub?.cancel();
    unawaited(BleTool.instance.stopScan());
    super.dispose();
  }

  Future<void> _pick(PackHit hit) async {
    setState(() => linking = true);
    try {
      await BleTool.instance.connectId(hit.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          err = e.toString();
          linking = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF101418),
      title: const Text('Connect pack'),
      content: SizedBox(
        width: 420,
        height: 260,
        child: linking
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    err ?? (hits.isEmpty ? 'Scanning nearby Bluetooth…' : 'Tap a device'),
                    style: const TextStyle(color: Color(0xFF8B9198), fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: hits.length,
                      itemBuilder: (context, i) {
                        final h = hits[i];
                        return ListTile(
                          dense: true,
                          title: Text(h.name),
                          subtitle: Text(h.likely ? 'likely pack  ${h.rssi} dBm' : '${h.rssi} dBm'),
                          leading: Icon(
                            h.likely ? Icons.battery_charging_full : Icons.bluetooth,
                            color: h.likely ? const Color(0xFF2EC7FF) : const Color(0xFF6A767C),
                          ),
                          onTap: () => _pick(h),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
      ],
    );
  }
}
