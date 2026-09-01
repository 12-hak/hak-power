import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../../../pages/Widget/fridge_tile.dart';
import '../../../pages/Widget/soc_tile.dart';
import 'ble_tool.dart';
import 'fridge_protocol.dart';
import 'juntek_tool.dart';

class HakHomeWidgets {
  static const _ch = MethodChannel('hak/widget');
  static DateTime? _last;
  static bool _busy = false;

  static Future<void> publish({
    required PackLive pack,
    required bool packOn,
    required FridgeLive fridge,
    required bool fridgeOn,
    required JuntekLive juntek,
    required bool juntekOn,
  }) async {
    if (_busy) return;
    if (_last != null && DateTime.now().difference(_last!) < const Duration(seconds: 8)) return;
    _busy = true;
    _last = DateTime.now();
    try {
      await _save('hak_voltx', const Size(320, 400), _pack(pack, packOn));
      await _save('hak_fridge', const Size(320, 400), _fridge(fridge, fridgeOn));
      await _save('hak_juntek', const Size(320, 400), _juntek(juntek, juntekOn));
      await _save('hak_dash', const Size(720, 360), _dash(pack, packOn, fridge, fridgeOn, juntek, juntekOn));
    } catch (_) {
    } finally {
      _busy = false;
    }
  }

  static Future<void> _save(String key, Size size, Widget child) async {
    final png = await _png(_box(size, child), size);
    await _ch.invokeMethod('save', {'key': key, 'png': png});
  }

  static Future<Uint8List> _png(Widget widget, Size size) async {
    final view = ui.PlatformDispatcher.instance.implicitView!;
    final ratio = view.devicePixelRatio;
    final boundary = RenderRepaintBoundary();
    final renderView = RenderView(
      view: view,
      child: RenderPositionedBox(alignment: Alignment.center, child: boundary),
      configuration: ViewConfiguration(
        logicalConstraints: BoxConstraints.tight(size),
        devicePixelRatio: ratio,
      ),
    );
    final pipeline = PipelineOwner();
    final owner = BuildOwner(focusManager: FocusManager());
    pipeline.rootNode = renderView;
    renderView.prepareInitialFrame();
    final root = RenderObjectToWidgetAdapter<RenderBox>(
      container: boundary,
      child: widget,
    ).attachToRenderTree(owner);
    owner.buildScope(root);
    owner.finalizeTree();
    pipeline.flushLayout();
    pipeline.flushCompositingBits();
    pipeline.flushPaint();
    final image = await boundary.toImage(pixelRatio: ratio);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    root.unmount();
    return bytes!.buffer.asUint8List();
  }

  static Widget _box(Size size, Widget child) {
    return MediaQuery(
      data: MediaQueryData(size: size),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: Material(
          color: const Color(0xFF05080A),
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    );
  }

  static Widget _empty(String label) {
    return Center(
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(color: Color(0xFF6A8088), fontSize: 13),
      ),
    );
  }

  static double? _packWatts(PackLive live) => (live.inputW - live.outputW).toDouble();

  static double? _juntekWatts(JuntekLive live) {
    final w = live.watts;
    if (w == null) return null;
    if (live.charging == false) return -w.abs();
    if (live.charging == true) return w.abs();
    return w;
  }

  static Widget _pack(PackLive live, bool on) {
    if (!on) return _empty('Connect VoltX in Hak Power');
    return SocTile(
      label: 'VOLTX',
      soc: live.soc,
      online: on,
      watts: _packWatts(live),
      subtitle: live.remainWh != null ? '${live.remainWh} Wh' : null,
    );
  }

  static Widget _fridge(FridgeLive live, bool on) {
    if (!on) return _empty('Connect Brass Monkey in Hak Power');
    return FridgeTile(leftC: live.leftC, rightC: live.rightC, unit: live.unit, online: on);
  }

  static Widget _juntek(JuntekLive live, bool on) {
    if (!on) return _empty('Connect Juntek in Hak Power');
    return SocTile(
      label: 'JUNTEK',
      soc: live.soc,
      online: on,
      watts: _juntekWatts(live),
      subtitle: live.ahRemain != null ? '${live.ahRemain!.toStringAsFixed(1)} Ah' : null,
    );
  }

  static Widget _dash(
    PackLive pack,
    bool packOn,
    FridgeLive fridge,
    bool fridgeOn,
    JuntekLive juntek,
    bool juntekOn,
  ) {
    final tiles = <Widget>[
      if (packOn) Expanded(child: _pack(pack, true)),
      if (fridgeOn) Expanded(child: _fridge(fridge, true)),
      if (juntekOn) Expanded(child: _juntek(juntek, true)),
    ];
    if (tiles.isEmpty) return _empty('Connect pack, fridge or Juntek in Hak Power');
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Row(
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            tiles[i],
          ],
        ],
      ),
    );
  }
}
