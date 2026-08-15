import 'package:flutter/material.dart';

import '../modules/common/utils/fridge_tool.dart';
import 'ColorScreenPower/outdoor_module/view_models/outdoor_power_view_model.dart';
import 'Widget/fridge_pick.dart';
import 'Widget/pack_pick.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.vm});

  final OutdoorPowerViewModel vm;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool busy = false;
  String? err;

  Future<void> _run(Future<void> Function() fn) async {
    setState(() {
      busy = true;
      err = null;
    });
    try {
      await fn();
    } catch (e) {
      final raw = e.toString();
      err = raw.contains('WRITE_NO_RESPONSE') ? 'Fridge write failed' : raw;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF07080A),
      appBar: AppBar(backgroundColor: Colors.transparent, title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (err != null) Text(err!, style: const TextStyle(color: Color(0xFFFF6B6B))),
          StreamBuilder(
            stream: FridgeTool.instance.stream,
            initialData: FridgeTool.instance.live,
            builder: (context, snap) {
              final f = snap.data ?? FridgeTool.instance.live;
              final ready = f.status == 'live';
              return Column(
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fridge ECO'),
                    subtitle: Text(ready ? (f.eco ? 'Eco on' : 'Max') : 'Connect fridge first'),
                    value: f.eco,
                    onChanged: !ready || busy ? null : (v) => _run(() => FridgeTool.instance.setEco(v)),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fridge lock'),
                    subtitle: Text(ready ? (f.locked ? 'Controls locked' : 'Unlocked') : 'Connect fridge first'),
                    value: f.locked,
                    onChanged: !ready || busy ? null : (v) => _run(() => FridgeTool.instance.setLock(v)),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        await showDialog<bool>(
                          context: context,
                          builder: (_) => const PackPickDialog(),
                        );
                        if (mounted) setState(() {});
                      },
                child: const Text('Connect pack'),
              ),
              FilledButton(
                onPressed: busy
                    ? null
                    : () async {
                        await showDialog<bool>(
                          context: context,
                          builder: (_) => const FridgePickDialog(),
                        );
                        if (mounted) setState(() {});
                      },
                child: const Text('Connect fridge'),
              ),
              OutlinedButton(onPressed: () => _run(widget.vm.ble.disconnect), child: const Text('Disconnect pack')),
              OutlinedButton(onPressed: () => _run(FridgeTool.instance.disconnect), child: const Text('Disconnect fridge')),
            ],
          ),
        ],
      ),
    );
  }
}
