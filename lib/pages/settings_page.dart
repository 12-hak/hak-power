import 'package:flutter/material.dart';

import '../modules/common/utils/fridge_tool.dart';
import '../modules/common/utils/hak_sound.dart';
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
  final camp = HakCamp.instance;

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
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Night'),
            subtitle: const Text('Dim red camp palette'),
            value: camp.night,
            onChanged: (v) => _run(() => camp.setNight(v)),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Keep screen on'),
            subtitle: const Text('Don’t sleep while Hak Power is open'),
            value: camp.keepOn,
            onChanged: (v) => _run(() => camp.setKeepOn(v)),
          ),
          StreamBuilder(
            stream: FridgeTool.instance.stream,
            initialData: FridgeTool.instance.live,
            builder: (context, snap) {
              final f = snap.data ?? FridgeTool.instance.live;
              final ready = f.status == 'live';
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Fridge power'),
                    subtitle: Text(ready ? (f.on ? 'On' : 'Off') : 'Connect fridge first'),
                    value: f.on,
                    onChanged: !ready || busy ? null : (v) => _run(() => FridgeTool.instance.setPower(v)),
                  ),
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
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Temperature unit'),
                    subtitle: Text(ready ? (f.unit == 'F' ? 'Fahrenheit' : 'Celsius') : 'Connect fridge first'),
                    value: f.unit == 'F',
                    onChanged: !ready || busy ? null : (v) => _run(() => FridgeTool.instance.setUnit(v ? 'F' : 'C')),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Battery saver'),
                    subtitle: Text(ready ? ['Off', 'Mid', 'High'][f.batSaver.clamp(0, 2)] : 'Connect fridge first'),
                    trailing: Wrap(
                      spacing: 6,
                      children: [
                        for (final e in const [(0, 'Off'), (1, 'Mid'), (2, 'High')])
                          ChoiceChip(
                            label: Text(e.$2),
                            selected: f.batSaver == e.$1,
                            onSelected: !ready || busy ? null : (_) => _run(() => FridgeTool.instance.setBatSaver(e.$1)),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text('Presets', style: TextStyle(color: Color(0xFF8B9198))),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      FilledButton.tonal(
                        onPressed: !ready || busy ? null : () => _run(() => FridgeTool.instance.applyPreset(4, 4)),
                        child: const Text('Fridge +4'),
                      ),
                      FilledButton.tonal(
                        onPressed: !ready || busy ? null : () => _run(() => FridgeTool.instance.applyPreset(-18, -18)),
                        child: const Text('Freeze −18'),
                      ),
                      FilledButton.tonal(
                        onPressed: !ready || busy ? null : () => _run(() => FridgeTool.instance.applyPreset(2, 2)),
                        child: const Text('Drink +2'),
                      ),
                    ],
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 28),
          const Text('About', style: TextStyle(color: Color(0xFF8B9198))),
          const ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text('Hak Power'),
            subtitle: Text('Version 0.1.3'),
          ),
        ],
      ),
    );
  }
}
