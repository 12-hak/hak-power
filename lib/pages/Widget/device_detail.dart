import 'package:flutter/material.dart';

import '../../modules/common/utils/hak_sound.dart';

class DeviceDetailPage extends StatelessWidget {
  const DeviceDetailPage({super.key, required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final page = Scaffold(
      backgroundColor: const Color(0xFF05080A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(title),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
          child: SizedBox.expand(child: child),
        ),
      ),
    );
    if (!HakCamp.instance.night) return page;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.85, 0.05, 0.02, 0, 0,
        0.05, 0.12, 0.02, 0, 0,
        0.02, 0.02, 0.10, 0, 0,
        0, 0, 0, 1, 0,
      ]),
      child: page,
    );
  }
}
