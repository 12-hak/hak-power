import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:s2200/main.dart';
import 'package:s2200/modules/common/utils/juntek_tool.dart';
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

  testWidgets('landscape dash shows pack and fridge faces', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const S2200App());
    await tester.pump();
    expect(find.text('AC IN'), findsOneWidget);
    expect(find.text('PV / CAR IN'), findsOneWidget);
    expect(find.text('AC OUT'), findsOneWidget);
    expect(find.text('DC OUT'), findsOneWidget);
    expect(find.text('TEMP LEFT'), findsOneWidget);
    expect(find.text('TEMP RIGHT'), findsOneWidget);
    expect(find.textContaining('SET'), findsNWidgets(2));
    expect(find.text('BRASS MONKEY'), findsOneWidget);
  });

  testWidgets('portrait dash still shows pack and fridge', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    await tester.pumpWidget(const S2200App());
    await tester.pump();
    expect(find.text('AC IN'), findsOneWidget);
    expect(find.text('BRASS MONKEY'), findsOneWidget);
  });

  test('juntek frame parses voltage and watts', () {
    final map = parseJuntekFrame(
      Uint8List.fromList([0xbb, 0x12, 0x02, 0xc0, 0x84, 0x14, 0xd8, 0x67, 0xee]),
    );
    expect(map[0xc0], 1202);
    expect(map[0xd8], 8414);
  });
}
