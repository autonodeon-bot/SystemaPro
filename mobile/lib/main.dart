import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'screens/login_screen.dart';
import 'screens/dashboard_screen.dart';
import 'services/auth_service.dart';
import 'services/notification_service.dart';
import 'providers/theme_provider.dart';
import 'theme/app_theme.dart';
import 'theme/app_colors.dart';

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

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: 'ЕС ТД НГО',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: _isLoading
          ? Scaffold(
              backgroundColor: themeMode == ThemeMode.light
                  ? AppColors.lightBackground
                  : AppColors.darkBackground,
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
