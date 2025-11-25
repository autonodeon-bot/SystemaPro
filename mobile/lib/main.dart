import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/equipment_list_screen.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ЕС ТД НГО',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF3b82f6),
          surface: Color(0xFF0f172a),
          onSurface: Colors.white,
          secondary: Color(0xFF1e293b),
        ),
        scaffoldBackgroundColor: const Color(0xFF0f172a),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0f172a),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const EquipmentListScreen(),
    );
  }
}
