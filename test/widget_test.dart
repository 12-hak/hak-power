import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:s2200/main.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('hak/sound'),
      (call) async => null,
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
}
