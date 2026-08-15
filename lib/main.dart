import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pages/dash_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const S2200App());
}

class S2200App extends StatelessWidget {
  const S2200App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Hak Power',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        colorScheme: const ColorScheme.dark(primary: Color(0xFF2EC7FF)),
        inputDecorationTheme: const InputDecorationTheme(
          labelStyle: TextStyle(color: Color(0xFF8B9198)),
        ),
      ),
      home: const DashPage(),
    );
  }
}
