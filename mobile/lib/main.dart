import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/auth_service.dart';

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
      home: FutureBuilder(
        future: AuthService().isAuthenticated(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          // ВАЖНО: Всегда показываем экран логина при запуске
          // Автоматический вход отключен для безопасности
          // Пользователь должен явно ввести логин и пароль
          return const LoginScreen();
        },
      ),
    );
  }
}
