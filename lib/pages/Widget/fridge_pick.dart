import 'dart:async';

import 'package:flutter/material.dart';

import '../../modules/common/utils/fridge_protocol.dart';
import '../../modules/common/utils/fridge_tool.dart';

class FridgePickDialog extends StatefulWidget {
  const FridgePickDialog({super.key});

  @override
  State<FridgePickDialog> createState() => _FridgePickDialogState();
}

class _FridgePickDialogState extends State<FridgePickDialog> {
  List<FridgeHit> hits = [];
  StreamSubscription<List<FridgeHit>>? _sub;
  StreamSubscription<FridgeLive>? _liveSub;
  String? err;
  bool linking = false;

  @override
  void initState() {
    super.initState();
    _sub = FridgeTool.instance.hitsStream.listen((list) {
      if (mounted) setState(() => hits = list);
    });
    _liveSub = FridgeTool.instance.stream.listen((live) {
      if (!mounted) return;
      if (live.status == 'live') Navigator.of(context).pop(true);
      if (live.error != null) setState(() => err = live.error);
    });
    unawaited(FridgeTool.instance.startScan().catchError((e) {
      if (mounted) setState(() => err = e.toString());
    }));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _liveSub?.cancel();
    unawaited(FridgeTool.instance.stopScan());
    super.dispose();
  }

  Future<void> _pick(FridgeHit hit) async {
    setState(() {
      linking = true;
      err = null;
    });
    try {
      await FridgeTool.instance.connectId(hit.id);
      if (mounted && FridgeTool.instance.live.status != 'live') {
        setState(() => linking = false);
      }
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
      title: const Text('Connect fridge'),
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
                          subtitle: Text(h.likely ? 'likely fridge  ${h.rssi} dBm' : '${h.rssi} dBm'),
                          leading: Icon(
                            h.likely ? Icons.kitchen : Icons.bluetooth,
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
