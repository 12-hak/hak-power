import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:s2200/main.dart';
import 'package:s2200/modules/common/utils/juntek_tool.dart';
import 'package:s2200/pages/Widget/amp_gauge.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('hak/sound'),
      (call) async {
        if (call.method == 'fridgeMuted') return false;
        return null;
      },
    );
  });

  testWidgets('dash shows settings when nothing is connected', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const S2200App());
    await tester.pump();
    expect(find.byIcon(Icons.settings), findsOneWidget);
    expect(find.textContaining('Connect pack'), findsOneWidget);
  });

  test('juntek names and vat frames', () {
    expect(likelyJuntekName('VAT-1230'), isTrue);
    expect(likelyJuntekName('KG140F'), isTrue);
    expect(likelyJuntekName('BTG004'), isTrue);
    expect(likelyJuntekName('lily fridge'), isFalse);
    final map = parseJuntekFrame(
      Uint8List.fromList([0xbb, 0x12, 0x02, 0xc0, 0x84, 0x14, 0xd8, 0x67, 0xee]),
    );
    expect(map[0xc0], 1202);
    expect(map[0xd8], 8414);
    final ascii = parseJuntekAscii(':r50=1,123,1198,1090,7421,');
    expect(ascii?.volts, 11.98);
    expect(ascii?.amps, 10.90);
    expect(ascii?.ahRemain, 7.421);
    expect(parseJuntekR51Cap(':r51=1,211,3000,100,2000,2000,10000,151,10,7,200,120,90,'), 20.0);
    expect(parseJuntekR51Cap(':r51=1,211,3000,100,2000,2000,10000,151,10,7,1000,120,90,'), 100.0);
    expect(parseJuntekFrame(Uint8List.fromList([0xbb, 0x10, 0x00, 0xb0, 0xee]))[0xb0], 1000);
    expect(JuntekLive(ahRemain: 97.5, capacityAh: 150).soc, closeTo(65, 0.1));
    expect(JuntekLive(ahRemain: 97.5, capacityAh: 100).soc, closeTo(97.5, 0.1));
    expect(parseJuntekAscii(':r50=1,123,1198,1090,7421,2749,437,298,113,0,0,1,69,')?.charging, isTrue);
    expect(parseJuntekAscii(':r50=1,123,1198,1090,7421,2749,437,298,113,0,0,0,69,')?.charging, isFalse);
  });

  test('watt meter scale snaps', () {
    expect(wattScaleFor(30), 50);
    expect(wattScaleFor(70), 100);
    expect(wattScaleFor(-150), 200);
    expect(wattScaleFor(350), 500);
    expect(wattScaleFor(700), 1000);
  });
}
