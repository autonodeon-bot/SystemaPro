import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'providers/theme_provider.dart';

void main() {
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> {
  final _authService = AuthService();
  bool _isLoading = true;
  bool _isAuthenticated = false;

  @override
  void initState() {
    super.initState();
    _checkAuth();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().initialize();
    });
  }

  Future<void> _checkAuth() async {
    final authenticated = await _authService.isAuthenticated();
    if (!mounted) return;
    setState(() {
      _isAuthenticated = authenticated;
      _isLoading = false;
    });
  }

  static ThemeData get _lightTheme => ThemeData(
        useMaterial3: true,
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF2563eb),
          surface: Color(0xFFf8fafc),
          onSurface: Color(0xFF0f172a),
          secondary: Color(0xFFe2e8f0),
        ),
        scaffoldBackgroundColor: const Color(0xFFf8fafc),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFf1f5f9),
          foregroundColor: Color(0xFF0f172a),
          elevation: 0,
        ),
      );

  static ThemeData get _darkTheme => ThemeData(
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
      );

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'ЕС ТД НГО',
      debugShowCheckedModeBanner: false,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      themeMode: themeMode,
      home: _isLoading
          ? Scaffold(
              backgroundColor: themeMode == ThemeMode.light
                  ? const Color(0xFFf8fafc)
                  : const Color(0xFF0f172a),
              body: const Center(
                child: CircularProgressIndicator(),
              ),
            )
          : _isAuthenticated
              ? const DashboardScreen()
              : const LoginScreen(),
    );
  }
}
