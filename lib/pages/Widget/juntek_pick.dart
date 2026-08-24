import 'dart:async';

import 'package:flutter/material.dart';

import '../../modules/common/utils/juntek_tool.dart';

class JuntekPickDialog extends StatefulWidget {
  const JuntekPickDialog({super.key});

  @override
  State<JuntekPickDialog> createState() => _JuntekPickDialogState();
}

class _JuntekPickDialogState extends State<JuntekPickDialog> {
  List<JuntekHit> hits = [];
  StreamSubscription<List<JuntekHit>>? _sub;
  StreamSubscription<JuntekLive>? _liveSub;
  String? err;
  bool linking = false;

  @override
  void initState() {
    super.initState();
    _sub = JuntekTool.instance.hitsStream.listen((list) {
      if (mounted) setState(() => hits = list);
    });
    _liveSub = JuntekTool.instance.stream.listen((live) {
      if (!mounted) return;
      if (live.status == 'live') Navigator.of(context).pop(true);
      if (live.error != null) setState(() => err = live.error);
    });
    unawaited(JuntekTool.instance.startScan().catchError((e) {
      if (mounted) setState(() => err = e.toString());
    }));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _liveSub?.cancel();
    unawaited(JuntekTool.instance.stopScan());
    super.dispose();
  }

  Future<void> _pick(JuntekHit hit) async {
    setState(() {
      linking = true;
      err = null;
    });
    try {
      await JuntekTool.instance.connectId(hit.id);
      if (mounted && JuntekTool.instance.live.status != 'live') {
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
      title: const Text('Connect Juntek VA'),
      content: SizedBox(
        width: 420,
        height: 260,
        child: linking
            ? const Center(child: CircularProgressIndicator())
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    err ?? (hits.isEmpty ? 'Scanning nearby Bluetooth…' : 'Tap a VAT / KG / KL meter'),
                    style: const TextStyle(color: Color(0xFF8B9198), fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView(
                      children: [
                        for (final h in hits)
                          ListTile(
                            dense: true,
                            title: Text(h.name),
                            subtitle: Text(h.id),
                            trailing: Text('${h.rssi}'),
                            onTap: () => _pick(h),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}
