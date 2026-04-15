import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../services/sync_service.dart';
import '../services/biometric_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> with WidgetsBindingObserver {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _authService = AuthService();
  final _apiService = ApiService();
  final _biometricService = BiometricService();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _hasOfflineSession = false;
  String? _offlineUserName;
  bool _biometricAvailable = false;
  bool _biometricEnabled = false;
  bool _pinEnabled = false;
  bool _pinCheckInProgress = false;
  bool _hasPin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkOfflineAvailability().then((_) {
      if (mounted) _checkBiometricAvailability();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Обновляем состояние PIN при возврате приложения в foreground
    if (state == AppLifecycleState.resumed) {
      _checkPinStatus();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Обновляем состояние при возврате на экран (например, после установки PIN)
    _checkPinStatus();
  }

  Future<void> _checkPinStatus() async {
    if (_pinCheckInProgress) return;
    _pinCheckInProgress = true;
    try {
      final hasPin = await _authService.hasPin();
      final user = await _authService.getCurrentUser();
      // Показываем кнопку PIN, если есть сохраненный пользователь (даже если PIN не установлен)
      final shouldShowPin = user != null;
      if (mounted) {
        setState(() {
          _pinEnabled = shouldShowPin;
          _hasPin = hasPin;
        });
      }
    } finally {
      _pinCheckInProgress = false;
    }
  }

  Future<void> _checkOfflineAvailability() async {
    final user = await _authService.getCurrentUser();
    final offlineUsername = await _authService.getOfflineUsername();
    final hasPin = await _authService.hasPin();
    if (!mounted) return;
    setState(() {
      _hasOfflineSession = user != null;
      _offlineUserName = user?.fullName ?? user?.username;
      _pinEnabled = user != null;
      _hasPin = hasPin;
      if (offlineUsername != null && offlineUsername.isNotEmpty) {
        _usernameController.text = offlineUsername;
      }
    });
  }

  Future<void> _checkBiometricAvailability() async {
    final isAvailable = await _biometricService.isBiometricAvailable();
    final isEnabled = await _authService.isBiometricEnabled();
    final isBound = await _authService.isUserBoundToDevice();
    
    if (!mounted) return;
    setState(() {
      _biometricAvailable = isAvailable && isBound;
      _biometricEnabled = isEnabled;
    });
    
    // Автоматически предлагаем биометрическую аутентификацию при открытии экрана
    if (_biometricAvailable && _biometricEnabled && _hasOfflineSession) {
      // Небольшая задержка для показа экрана входа
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _loginWithBiometric();
        }
      });
    }
  }

  Future<void> _login() async {
    if (_formKey.currentState!.validate()) {
      setState(() {
        _isLoading = true;
      });

      try {
        final response = await _apiService.login(
          _usernameController.text,
          _passwordController.text,
        );

        if (response != null && response['access_token'] != null) {
          final user = User(
            id: response['user_id']?.toString() ?? _usernameController.text,
            username: _usernameController.text,
            email: response['email'],
            fullName: response['full_name'],
            role: response['role'],
            token: response['access_token'],
          );

          // Сохраняем пользователя и учётные данные (логин/пароль) для авто-входа при синхронизации
          await _authService.saveUser(user, passwordHash: response['password_hash']);
          await _authService.saveCredentials(_usernameController.text.trim(), _passwordController.text);

          // Предлагаем включить биометрическую аутентификацию
          if (mounted && !_biometricEnabled) {
            final biometricAvailable = await _biometricService.isBiometricAvailable();
            if (biometricAvailable) {
              _showBiometricSetupDialog();
            } else {
              context.go('/dashboard');
            }
          } else {
            if (mounted) {
              context.go('/dashboard');
            }
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Неверный логин или пароль'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка входа: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isLoading = false;
          });
        }
      }
    }
  }

  Future<void> _loginWithBiometric() async {
    if (!_biometricAvailable || !_biometricEnabled) {
      return;
    }

    final savedUser = await _authService.getCurrentUser();
    if (savedUser == null && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала войдите по логину и паролю, затем включите вход по отпечатку.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      final authenticated = await _authService.authenticateWithBiometric();

      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });

      if (authenticated) {
        final user = await _authService.getCurrentUser();
        if (user != null) {
          context.go('/dashboard');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Данные пользователя не найдены. Войдите по логину и паролю.'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Вход по отпечатку отменён или не распознан. Попробуйте снова или войдите по паролю.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  void _showBiometricSetupDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Включить вход по отпечатку пальца?'),
        content: const Text(
          'Вы можете использовать отпечаток пальца или PIN-код для быстрого входа в приложение без ввода пароля.',
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/dashboard');
            },
            child: const Text('Позже'),
          ),
          TextButton(
            onPressed: () async {
              await _authService.ensureDeviceBound();
              await _authService.setBiometricEnabled(true);
              if (!context.mounted) return;
              Navigator.of(context).pop();
              context.go('/dashboard');
            },
            child: const Text('Включить'),
          ),
        ],
      ),
    );
  }

  Future<void> _loginOffline() async {
    final savedUser = await _authService.getCurrentUser();
    final savedUsername = await _authService.getOfflineUsername();
    
    if (savedUser == null || savedUsername == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Офлайн-вход недоступен: сначала выполните вход с интернетом.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    // Подсказка при первом офлайн-входе без кэша
    final offlineEquipment = await SyncService().getOfflineEquipment();
    final offlineAssignments = await SyncService().getOfflineAssignments();
    if (offlineEquipment.isEmpty && offlineAssignments.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Для работы офлайн сначала войдите при подключённом интернете и откройте список заданий — данные сохранятся для офлайна.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    } else if (offlineEquipment.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Нет сохранённого оборудования. Откройте задания при интернете для загрузки данных.'),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
    }
    
    // Проверяем, что имя пользователя совпадает (если введено)
    if (_usernameController.text.isNotEmpty && _usernameController.text != savedUsername) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Неверное имя пользователя'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    
    // Если пароль введен, проверяем его
    if (_passwordController.text.isNotEmpty) {
      final passwordValid = await _authService.verifyPasswordOffline(_passwordController.text);
      if (!passwordValid) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Неверный пароль'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
    }

    if (!mounted) return;
    context.go('/dashboard');
  }

  Future<void> _loginWithPin() async {
    final savedUser = await _authService.getCurrentUser();
    final savedUsername = await _authService.getOfflineUsername();

    if (savedUser == null || savedUsername == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала выполните вход с интернетом, чтобы сохранить данные для офлайн-входа.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Проверяем, установлен ли PIN
    final hasPin = await _authService.hasPin();
    
    if (!hasPin) {
      // Если PIN не установлен, предлагаем его установить
      final setupPin = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Установить PIN-код'),
          content: const Text(
            'PIN-код позволит быстро входить в приложение без ввода логина и пароля. Установить PIN-код?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Позже'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Установить'),
            ),
          ],
        ),
      );

      if (setupPin == true) {
        // Переходим на экран профиля для установки PIN
        // Или устанавливаем PIN прямо здесь
        await _setupPin();
        return;
      } else {
        return;
      }
    }

    // Если PIN установлен, запрашиваем его
    final pinController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Вход по PIN'),
        content: TextField(
          controller: pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'PIN-код (4-6 цифр)',
            hintText: 'Введите PIN-код',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Войти'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final pin = pinController.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('PIN должен содержать 4-6 цифр'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    final verified = await _authService.verifyPin(pin);
    if (!mounted) return;
    setState(() => _isLoading = false);
    if (!verified) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Неверный PIN'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    context.go('/dashboard');
  }

  Future<void> _setupPin() async {
    final pinController1 = TextEditingController();
    final pinController2 = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Установить PIN-код'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: pinController1,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Введите PIN-код (4-6 цифр)',
                  hintText: 'PIN-код',
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: pinController2,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Подтвердите PIN-код',
                  hintText: 'PIN-код',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () {
              final pin1 = pinController1.text.trim();
              final pin2 = pinController2.text.trim();
              if (!RegExp(r'^\d{4,6}$').hasMatch(pin1)) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('PIN должен содержать 4-6 цифр'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              if (pin1 != pin2) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(
                    content: Text('PIN-коды не совпадают'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }
              Navigator.pop(ctx, true);
            },
            child: const Text('Установить'),
          ),
        ],
      ),
    );

    if (result == true) {
      final pin = pinController1.text.trim();
      await _authService.setPin(pin);
      if (mounted) {
        setState(() {
          _pinEnabled = true;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PIN-код успешно установлен'),
            backgroundColor: Colors.green,
          ),
        );
        context.go('/dashboard');
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(
                    Icons.account_circle,
                    size: 100,
                    color: Color(0xFF3b82f6),
                  ),
                  const SizedBox(height: 32),
                  const Text(
                    'Монитор',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Мобильное приложение инженера',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.white70,
                    ),
                  ),
                  const SizedBox(height: 48),
                  TextFormField(
                    controller: _usernameController,
                    decoration: InputDecoration(
                      labelText: 'Логин',
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon:
                          const Icon(Icons.person, color: Colors.white70),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF3b82f6)),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1e293b),
                    ),
                    style: const TextStyle(color: Colors.white),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Введите логин';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Пароль',
                      labelStyle: const TextStyle(color: Colors.white70),
                      prefixIcon: const Icon(Icons.lock, color: Colors.white70),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility
                              : Icons.visibility_off,
                          color: Colors.white70,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Colors.white24),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: const BorderSide(color: Color(0xFF3b82f6)),
                      ),
                      filled: true,
                      fillColor: const Color(0xFF1e293b),
                    ),
                    style: const TextStyle(color: Colors.white),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Введите пароль';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF3b82f6),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor:
                                  AlwaysStoppedAnimation<Color>(Colors.white),
                            ),
                          )
                        : const Text(
                            'Войти',
                            style: TextStyle(
                                fontSize: 16, fontWeight: FontWeight.bold),
                          ),
                  ),
                  // Кнопка биометрической аутентификации (если доступна и есть офлайн-сессия)
                  if (_hasOfflineSession && _biometricAvailable && _biometricEnabled) ...[
                    const SizedBox(height: 12),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _loginWithBiometric,
                      icon: const Icon(Icons.fingerprint, size: 24),
                      label: const Text(
                        'Войти по отпечатку пальца',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10b981),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                  // Кнопка PIN-входа (показывается, если есть сохраненный пользователь)
                  if (_pinEnabled) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _loginWithPin,
                      icon: const Icon(Icons.lock, color: Colors.white70),
                      label: Text(
                        _hasPin 
                            ? 'Войти по PIN-коду'
                            : 'Установить PIN-код',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                  // Кнопка офлайн-входа — всегда показываем при сохранённом пользователе
                  if (_hasOfflineSession) ...[
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _isLoading ? null : _loginOffline,
                      icon: const Icon(Icons.offline_bolt, color: Colors.white70),
                      label: Text(
                        _offlineUserName != null
                            ? 'Войти офлайн ($_offlineUserName)'
                            : 'Войти офлайн',
                        style: const TextStyle(color: Colors.white70),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
