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
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            color: const Color(0xFF1e293b),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const ListTile(
                  title: Text('Тема оформления', style: TextStyle(color: Colors.white)),
                  subtitle: Text(
                    'Сохраняется на устройстве',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(value: ThemeMode.light, label: Text('Светлая')),
                      ButtonSegment(value: ThemeMode.dark, label: Text('Тёмная')),
                      ButtonSegment(value: ThemeMode.system, label: Text('Системная')),
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
            color: const Color(0xFF1e293b),
            child: ListTile(
              title: const Text('Сервер API', style: TextStyle(color: Colors.white)),
              subtitle: SelectableText(
                AppConfig.effectiveApiBaseUrl,
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFF1e293b),
            child: ListTile(
              title: const Text('Синхронизация', style: TextStyle(color: Colors.white)),
              subtitle: const Text(
                'Очередь обследований и загрузка на сервер',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              trailing: const Icon(Icons.chevron_right, color: Colors.white70),
              onTap: () => context.push('/sync'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            color: const Color(0xFF1e293b),
            child: ListTile(
              title: const Text('Версия приложения', style: TextStyle(color: Colors.white)),
              subtitle: Text(
                _pkg == null ? '…' : '${_pkg!.version} (${_pkg!.buildNumber})',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
