import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import 'equipment_list_screen.dart';
import 'assignments_screen.dart'; // Версия 3.3.0
import 'profile_screen.dart';
import 'sync_screen.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _currentIndex = 0;
  String _appVersion = '';
  String? _updateUrl;
  final _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _checkForUpdate();
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

  Future<void> _checkForUpdate() async {
    try {
      final updateInfo = await _apiService.checkAppUpdate();
      if (updateInfo != null) {
        // Проверяем флаг has_update и is_latest
        final hasUpdate = updateInfo['has_update'] == true;
        final isLatest = updateInfo['is_latest'] == true;
        
        // Показываем диалог только если реально есть обновление и версия не последняя
        if (hasUpdate && !isLatest && updateInfo['download_url'] != null) {
          setState(() {
            _updateUrl = updateInfo['download_url'];
          });
          if (mounted) {
            _showUpdateDialog();
          }
        }
        // Логируем для отладки
        print('Проверка обновлений: has_update=$hasUpdate, is_latest=$isLatest, current=${updateInfo['current_version']}+${updateInfo['current_build']}, latest=${updateInfo['latest_version']}+${updateInfo['latest_build']}');
      }
    } catch (e) {
      // Игнорируем ошибки проверки обновлений, но логируем
      print('Ошибка проверки обновлений: $e');
    }
  }

  void _showUpdateDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Доступно обновление'),
        content: const Text('Доступна новая версия приложения. Хотите скачать?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Позже'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.of(context).pop();
              if (_updateUrl != null) {
                try {
                  final uri = Uri.parse(_updateUrl!);
                  // Используем externalApplication для прямого скачивания APK
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(
                      uri,
                      mode: LaunchMode.externalApplication,
                    );
                  } else {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Не удалось открыть ссылку для скачивания'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                } catch (e) {
                  if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Ошибка при открытии ссылки: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
                }
              }
            },
            child: const Text('Скачать'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      body: IndexedStack(
        index: _currentIndex,
        children: const [
          AssignmentsScreen(), // Версия 3.3.0: Задания вместо списка оборудования
          EquipmentListScreen(), // Оборудование доступно как отдельный экран
          SyncScreen(),
          ProfileScreen(),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_appVersion.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: const Color(0xFF0f172a),
              child: Text(
                'Версия: $_appVersion',
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          BottomNavigationBar(
            currentIndex: _currentIndex,
            onTap: (index) {
              setState(() {
                _currentIndex = index;
              });
            },
            backgroundColor: const Color(0xFF1e293b),
            selectedItemColor: const Color(0xFF3b82f6),
            unselectedItemColor: Colors.white70,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.assignment),
                label: 'Задания', // Версия 3.3.0
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.list),
                label: 'Оборудование',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.sync),
                label: 'Синхронизация',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person),
                label: 'Профиль',
              ),
            ],
          ),
        ],
      ),
    );
  }
}
