import '../theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../config/app_config.dart';
import '../providers/theme_provider.dart';

/// Настройки приложения: тема, сведения о сборке, переход к синхронизации.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  PackageInfo? _pkg;

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((p) {
      if (mounted) setState(() => _pkg = p);
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final themeNotifier = ref.read(themeModeProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Настройки'),
        backgroundColor: AppColors.scaffold(context),
        foregroundColor: AppColors.onSurface(context),
      ),
      backgroundColor: AppColors.scaffold(context),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: AppColors.surface(context),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ListTile(
                  title: Text('Тема оформления',
                      style: TextStyle(color: AppColors.onSurface(context))),
                  subtitle: Text(
                    'Сохраняется на устройстве',
                    style: TextStyle(
                        color: AppColors.mutedText(context), fontSize: 12),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  child: SegmentedButton<ThemeMode>(
                    segments: [
                      const ButtonSegment(
                          value: ThemeMode.light, label: Text('Светлая')),
                      const ButtonSegment(
                          value: ThemeMode.dark, label: Text('Тёмная')),
                      const ButtonSegment(
                          value: ThemeMode.system, label: Text('Системная')),
                    ],
                    selected: {themeMode},
                    onSelectionChanged: (s) {
                      themeNotifier.setThemeMode(s.first);
                    },
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: AppColors.surface(context),
            child: ListTile(
              title: Text('Сервер API',
                  style: TextStyle(color: AppColors.onSurface(context))),
              subtitle: SelectableText(
                AppConfig.effectiveApiBaseUrl,
                style: TextStyle(
                    color: AppColors.mutedText(context), fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: AppColors.surface(context),
            child: ListTile(
              title: Text('Синхронизация',
                  style: TextStyle(color: AppColors.onSurface(context))),
              subtitle: Text(
                'Очередь обследований и загрузка на сервер',
                style: TextStyle(
                    color: AppColors.mutedText(context), fontSize: 13),
              ),
              trailing: Icon(Icons.chevron_right,
                  color: AppColors.mutedText(context)),
              onTap: () => context.push('/sync'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: AppColors.surface(context),
            child: ListTile(
              title: Text('Версия приложения',
                  style: TextStyle(color: AppColors.onSurface(context))),
              subtitle: Text(
                _pkg == null ? '…' : '${_pkg!.version} (${_pkg!.buildNumber})',
                style: TextStyle(
                    color: AppColors.mutedText(context), fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
