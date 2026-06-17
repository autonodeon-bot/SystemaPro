import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/auth_service.dart';
import '../services/api_service.dart';
import '../models/user.dart';
import '../services/sync_service.dart';
import '../providers/theme_provider.dart';
import '../theme/app_colors.dart';
import 'instrument_park_screen.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _authService = AuthService();
  final _apiService = ApiService();
  User? _user;
  bool _isLoading = true;
  String _appVersion = 'Загрузка...';
  bool _pinEnabled = false;
  List<Map<String, dynamic>> _myInstruments = [];

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
    _loadMyInstruments();
  }

  Future<void> _loadMyInstruments() async {
    try {
      final data = await _apiService.getMyInstruments();
      if (mounted) {
        setState(() {
          _myInstruments = List<Map<String, dynamic>>.from(data);
        });
      }
    } catch (_) {}
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
        backgroundColor: AppColors.darkBackground,
        body: Center(
          child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.accent),
        ),
      );
    }

    if (_user == null) {
      return Scaffold(
        backgroundColor: AppColors.darkBackground,
        appBar: AppBar(
          title: const Text('Профиль', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
          backgroundColor: AppColors.darkBackgroundDeep,
          foregroundColor: AppColors.textPrimary,
          elevation: 0,
        ),
        body: const Center(
          child: Text(
            'Пользователь не найден',
            style: TextStyle(color: AppColors.textPrimary),
          ),
        ),
      );
    }

    final initials = _extractInitials(_user!.fullName ?? _user!.username);

    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: const Text('Профиль', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.2)),
        backgroundColor: AppColors.darkBackgroundDeep,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.darkSurface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.darkBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.accent.withValues(alpha: 0.5), width: 1.5),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    initials,
                    style: const TextStyle(
                      color: AppColors.accent,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _user!.fullName ?? _user!.username,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                          letterSpacing: -0.2,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '@${_user!.username}',
                        style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                      ),
                      if (_user!.role != null) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: AppColors.darkBorder,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: AppColors.accent.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            _getRoleName(_user!.role!),
                            style: const TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.3,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (_user!.email != null) ...[
            const SizedBox(height: 8),
            _buildInfoCard('Email', _user!.email!),
          ],
          const SizedBox(height: 8),
          _buildInfoCard('Версия', _appVersion),
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
                'Монитор (SystemaPro) — мобильное приложение инженера диагностики',
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
          // Приборный парк — П.4
          Card(
            color: const Color(0xFF1e293b),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.build_circle_outlined, color: Colors.blueAccent),
                  title: const Text(
                    'Приборный парк',
                    style: TextStyle(color: Colors.white),
                  ),
                  subtitle: _myInstruments.isEmpty
                      ? const Text('Нет закреплённых приборов',
                          style: TextStyle(color: Colors.white54, fontSize: 12))
                      : Text(
                          'Закреплено приборов: ${_myInstruments.length}',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                  trailing: const Icon(Icons.chevron_right, color: Colors.white70),
                  onTap: () {
                    Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const InstrumentParkScreen(),
                    ));
                  },
                ),
                // Список закреплённых приборов (П.4.3)
                if (_myInstruments.isNotEmpty) ...[
                  const Divider(color: Colors.white12, height: 1),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Мои приборы',
                            style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 8),
                        ..._myInstruments.map((inst) {
                          final name = (inst['name'] as String?) ?? 'Прибор';
                          final type = (inst['type'] as String?) ?? '';
                          final verUntil = (inst['verification_until'] as String?) ?? '—';
                          final condCode = (inst['condition'] as String?) ?? 'ok';
                          Color condColor = Colors.greenAccent;
                          if (condCode == 'damaged') condColor = Colors.orange;
                          if (condCode == 'broken') condColor = Colors.redAccent;
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              children: [
                                Icon(Icons.circle, size: 8, color: condColor),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '$name${type.isNotEmpty ? ' ($type)' : ''}',
                                    style: const TextStyle(
                                        color: Colors.white, fontSize: 13),
                                  ),
                                ),
                                Text(
                                  'Поверка: $verUntil',
                                  style: const TextStyle(
                                      color: Colors.white54, fontSize: 11),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ],
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
              onTap: () => context.push('/settings'),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  String _extractInitials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts[0].substring(0, 1) + parts[1].substring(0, 1)).toUpperCase();
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
