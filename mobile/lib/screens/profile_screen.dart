import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import '../services/sync_service.dart';
import '../providers/theme_provider.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _authService = AuthService();
  User? _user;
  bool _isLoading = true;
  String _appVersion = 'Загрузка...';
  bool _pinEnabled = false;

  @override
  void initState() {
    super.initState();
    _loadUser();
    _loadAppVersion();
    _loadPinStatus();
  }

  Future<void> _loadAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      setState(() {
        _appVersion = '${packageInfo.version} (build ${packageInfo.buildNumber})';
      });
    } catch (e) {
      setState(() {
        _appVersion = 'Неизвестно';
      });
    }
  }

  Future<void> _loadUser() async {
    final user = await _authService.getCurrentUser();
    setState(() {
      _user = user;
      _isLoading = false;
    });
  }

  Future<void> _loadPinStatus() async {
    final enabled = await _authService.hasPin();
    if (!mounted) return;
    setState(() {
      _pinEnabled = enabled;
    });
  }

  static String _themeModeSubtitle(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.light:
        return 'Светлая';
      case ThemeMode.dark:
        return 'Тёмная';
      case ThemeMode.system:
        return 'Как в системе';
    }
  }

  static void _showThemeDialog(BuildContext context, WidgetRef ref) {
    final current = ref.read(themeModeProvider);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
        title: Text(
          'Тема',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode), label: Text('Светлая')),
                ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode), label: Text('Тёмная')),
                ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto), label: Text('Система')),
              ],
              selected: {current},
              onSelectionChanged: (Set<ThemeMode> selection) {
                ref.read(themeModeProvider.notifier).setThemeMode(selection.first);
                Navigator.of(ctx).pop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showSetPinDialog({required bool requireCurrent}) async {
    final currentController = TextEditingController();
    final pinController = TextEditingController();
    final confirmController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: Text(
          requireCurrent ? 'Изменить PIN-код' : 'Установить PIN-код',
          style: const TextStyle(color: Colors.white),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (requireCurrent) ...[
                TextField(
                  controller: currentController,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  decoration: const InputDecoration(
                    labelText: 'Текущий PIN',
                    labelStyle: TextStyle(color: Colors.white70),
                  ),
                  style: const TextStyle(color: Colors.white),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                controller: pinController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Новый PIN (4-6 цифр)',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                obscureText: true,
                keyboardType: TextInputType.number,
                maxLength: 6,
                decoration: const InputDecoration(
                  labelText: 'Повторите PIN',
                  labelStyle: TextStyle(color: Colors.white70),
                ),
                style: const TextStyle(color: Colors.white),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Сохранить', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final currentPin = currentController.text.trim();
    final pin = pinController.text.trim();
    final confirm = confirmController.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN должен содержать 4-6 цифр'), backgroundColor: Colors.red),
      );
      return;
    }
    if (pin != confirm) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN не совпадает'), backgroundColor: Colors.red),
      );
      return;
    }
    if (requireCurrent) {
      final verified = await _authService.verifyPin(currentPin);
      if (!verified) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Неверный текущий PIN'), backgroundColor: Colors.red),
        );
        return;
      }
    }

    await _authService.setPin(pin);
    if (!mounted) return;
    setState(() => _pinEnabled = true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN-код сохранен'), backgroundColor: Colors.green),
    );
  }

  Future<void> _showRemovePinDialog() async {
    final pinController = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: const Text('Отключить PIN-код', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: pinController,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: const InputDecoration(
            labelText: 'Введите PIN',
            labelStyle: TextStyle(color: Colors.white70),
          ),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена', style: TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Отключить', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final pin = pinController.text.trim();
    if (!RegExp(r'^\d{4,6}$').hasMatch(pin)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN должен содержать 4-6 цифр'), backgroundColor: Colors.red),
      );
      return;
    }
    final verified = await _authService.verifyPin(pin);
    if (!verified) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Неверный PIN'), backgroundColor: Colors.red),
      );
      return;
    }
    await _authService.clearPin();
    if (!mounted) return;
    setState(() => _pinEnabled = false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('PIN-код отключен'), backgroundColor: Colors.green),
    );
  }

  Future<void> _clearOfflineCache() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: const Text(
          'Очистить локальный кэш',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Будут удалены сохранённые для офлайна задания и оборудование. '
          'Несохранённые черновики обследований останутся. Продолжить?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Очистить', style: TextStyle(color: Colors.orange)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      try {
        await SyncService().clearOfflineCache();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Кэш очищен. При следующем входе в сеть загрузите задания заново.'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e'), backgroundColor: Colors.red),
          );
        }
      }
    }
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1e293b),
        title: const Text(
          'Выход',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'Вы уверены, что хотите выйти?',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              'Выйти',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _authService.logout();
      // Чистим офлайн-кэш (чтобы следующий инженер не увидел чужое оборудование/задания)
      try {
        await SyncService().clearOfflineCache();
      } catch (_) {
        // ignore
      }
      if (mounted) {
        context.go('/login');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0f172a),
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_user == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF0f172a),
        appBar: AppBar(
          title: const Text('Личный кабинет'),
          backgroundColor: const Color(0xFF0f172a),
        ),
        body: const Center(
          child: Text(
            'Пользователь не найден',
            style: TextStyle(color: Colors.white),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: const Text('Личный кабинет'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFF1e293b),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 40,
                        backgroundColor: Color(0xFF3b82f6),
                        child: Icon(
                          Icons.person,
                          size: 40,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _user!.fullName ?? _user!.username,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            if (_user!.email != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                _user!.email!,
                                style: const TextStyle(
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          _buildInfoCard('Логин', _user!.username),
          if (_user!.role != null)
            _buildInfoCard('Роль', _getRoleName(_user!.role!)),
          const SizedBox(height: 16),
          _buildInfoCard('Версия приложения', _appVersion),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Внешний вид',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: ListTile(
              leading: Icon(Icons.palette_outlined, color: Theme.of(context).colorScheme.primary),
              title: Text(
                'Тема',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
              ),
              subtitle: Text(
                _themeModeSubtitle(ref.watch(themeModeProvider)),
                style: TextStyle(color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7), fontSize: 12),
              ),
              trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7)),
              onTap: () => _showThemeDialog(context, ref),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'О приложении',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withOpacity(0.7),
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1e293b),
            child: ListTile(
              leading: const Icon(Icons.info_outline, color: Colors.white70),
              title: const Text(
                'ЕС ТД НГО — мобильное приложение инженера диагностики',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
              subtitle: const Text(
                'Заполнение чек-листов, офлайн-режим, синхронизация с сервером',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFF1e293b),
            child: ListTile(
              leading: const Icon(Icons.delete_sweep, color: Colors.orange),
              title: const Text(
                'Очистить локальный кэш',
                style: TextStyle(color: Colors.white),
              ),
              subtitle: const Text(
                'Удалить сохранённые задания и оборудование. Черновики не трогаются.',
                style: TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white70),
              onTap: _clearOfflineCache,
            ),
          ),
          const SizedBox(height: 24),
          Card(
            color: const Color(0xFF1e293b),
            child: ListTile(
              leading: const Icon(Icons.sync, color: Colors.blue),
              title: const Text(
                'Синхронизация данных',
                style: TextStyle(color: Colors.white),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white70),
              onTap: () {
                context.go('/dashboard');
              },
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFF1e293b),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.lock, color: Colors.orange),
                  title: const Text(
                    'PIN-код',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: Text(
                    _pinEnabled ? 'Включен' : 'Не установлен',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white70),
                  onTap: () {
                    _showSetPinDialog(requireCurrent: _pinEnabled);
                  },
                ),
                if (_pinEnabled)
                  ListTile(
                    leading: const Icon(Icons.delete, color: Colors.red),
                    title: const Text(
                      'Отключить PIN',
                      style: TextStyle(color: Colors.white),
                    ),
                    onTap: _showRemovePinDialog,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Card(
            color: const Color(0xFF1e293b),
            child: ListTile(
              leading: const Icon(Icons.settings, color: Colors.grey),
              title: const Text(
                'Настройки',
                style: TextStyle(color: Colors.white),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white70),
              onTap: () {
                // TODO: Переход на экран настроек
              },
            ),
          ),
          const SizedBox(height: 24),
          Card(
            color: const Color(0xFF1e293b),
            child: ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text(
                'Выйти',
                style: TextStyle(color: Colors.red),
              ),
              onTap: _logout,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(String label, String value) {
    return Card(
      color: const Color(0xFF1e293b),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getRoleName(String role) {
    switch (role) {
      case 'admin':
        return 'Администратор';
      case 'chief_operator':
        return 'Главный оператор';
      case 'operator':
        return 'Оператор';
      case 'engineer':
        return 'Инженер';
      case 'client':
        return 'Клиент';
      default:
        return role;
    }
  }
}
