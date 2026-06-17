import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import '../services/api_service.dart';
import '../theme/app_colors.dart';
import 'equipment_list_screen.dart';
import 'assignments_screen.dart';
import 'profile_screen.dart';
import 'sync_screen.dart';
import 'opo_list_screen.dart';
import 'protocols_registry_screen.dart';
import 'diagnostic_create_menu_screen.dart';
import '../services/sync_service.dart';

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
  final _syncService = SyncService();
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  BuildContext? _progressDialogContext;
  int _pendingCount = 0;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _loadAppVersion();
    _checkForUpdate();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    try {
      final pending = await _syncService.getPendingInspections();
      final pendingStandalone =
          await _syncService.getPendingStandaloneProtocols();
      final pendingQuestionnaires =
          await _syncService.getPendingQuestionnaires();
      final pendingQuestionnaireNdt =
          await _syncService.getPendingQuestionnaireNdt();
      final offlineMode = await _syncService.isOfflineMode();
      final hasConnection = await _apiService.checkConnection();
      if (mounted) {
        setState(() {
          _pendingCount = pending.length +
              pendingStandalone.length +
              pendingQuestionnaires.length +
              pendingQuestionnaireNdt.length;
          _isOffline = offlineMode || !hasConnection;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isOffline = true);
    }
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
      barrierDismissible: !_isDownloading,
      builder: (context) => AlertDialog(
        title: const Text('Доступно обновление'),
        content: _isDownloading
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Скачивание обновления...'),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _downloadProgress),
                  const SizedBox(height: 8),
                  Text('${(_downloadProgress * 100).toStringAsFixed(0)}%'),
                ],
              )
            : const Text('Доступна новая версия приложения. Хотите скачать и установить?'),
        actions: [
          if (!_isDownloading)
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Позже'),
            ),
          TextButton(
            onPressed: _isDownloading ? null : () async {
              Navigator.of(context).pop();
              if (_updateUrl != null) {
                await _downloadAndInstallUpdate(_updateUrl!);
              }
            },
            child: _isDownloading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Скачать и установить'),
          ),
        ],
      ),
    );
  }

  void _showProgressDialog() {
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        _progressDialogContext = context;
        return StatefulBuilder(
          builder: (context, setDialogState) {
            // Сохраняем setDialogState для обновления диалога
            _updateDialogState = setDialogState;
            return AlertDialog(
              title: const Text('Скачивание обновления'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Пожалуйста, подождите...'),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: _downloadProgress),
                  const SizedBox(height: 8),
                  Text('${(_downloadProgress * 100).toStringAsFixed(0)}%'),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void Function(void Function())? _updateDialogState;

  void _updateProgressDialog() {
    if (_updateDialogState != null) {
      _updateDialogState!(() {});
    }
  }

  void _closeProgressDialog() {
    if (_progressDialogContext != null && mounted) {
      Navigator.of(_progressDialogContext!).pop();
      _progressDialogContext = null;
      _updateDialogState = null;
    }
  }

  Future<void> _downloadAndInstallUpdate(String url) async {
    if (_isDownloading) return;

    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    // Показываем диалог с прогрессом
    if (mounted) {
      _showProgressDialog();
    }

    try {
      // Получаем директорию для сохранения файла
      final directory = await getExternalStorageDirectory();
      if (directory == null) {
        throw Exception('Не удалось получить директорию для сохранения');
      }

      // Извлекаем имя файла из URL
      final uri = Uri.parse(url);
      final fileName = uri.pathSegments.last;
      if (fileName.isEmpty || !fileName.endsWith('.apk')) {
        throw Exception('Неверный формат файла обновления');
      }

      final filePath = '${directory.path}/$fileName';

      // Скачиваем файл
      final dio = Dio();
      await dio.download(
        url,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() {
              _downloadProgress = received / total;
            });
            _updateProgressDialog();
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloadProgress = 1.0;
        });
        _updateProgressDialog();
      }

      // Закрываем диалог прогресса
      _closeProgressDialog();

      // Открываем установщик APK
      // Для Android 8.0+ система автоматически запросит разрешение на установку из неизвестных источников
      final result = await OpenFilex.open(filePath);
      
      if (mounted) {
        if (result.type == ResultType.done) {
          // После успешной установки обновляем версию и проверяем обновления снова
          await _loadAppVersion();
          // Ждем немного, чтобы система обновила информацию о пакете
          await Future.delayed(const Duration(seconds: 2));
          await _checkForUpdate();
          
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Установка начата. После завершения установки приложение будет обновлено.'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 5),
            ),
          );
        } else if (result.type == ResultType.noAppToOpen) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Не найдено приложение для установки APK. Пожалуйста, установите файловый менеджер.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 5),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка при открытии установщика: ${result.message}'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        }
      }
    } catch (e) {
      // Закрываем диалог прогресса в случае ошибки
      _closeProgressDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка при скачивании обновления: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      print('Ошибка скачивания обновления: $e');
    } finally {
      setState(() {
        _isDownloading = false;
        _downloadProgress = 0.0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      body: Column(
        children: [
          // Top status strip — 2026 refined: точечный цветовой индикатор + чип "Ожидают отправки".
          Material(
            color: AppColors.darkBackgroundDeep,
            child: SafeArea(
              bottom: false,
              child: Semantics(
                label: _isOffline
                    ? 'Режим офлайн. Нажмите для перехода к синхронизации'
                    : 'Подключено к серверу. Нажмите для перехода к синхронизации',
                button: true,
                child: InkWell(
                  onTap: () => setState(() => _currentIndex = 4),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: _isOffline ? AppColors.warning : AppColors.success,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: (_isOffline ? AppColors.warning : AppColors.success).withOpacity(0.45),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _isOffline ? 'Режим офлайн' : 'Онлайн',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.1,
                          ),
                        ),
                        const Spacer(),
                        if (_pendingCount > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withOpacity(0.14),
                              border: Border.all(color: AppColors.warning.withOpacity(0.35)),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.sync_problem, size: 13, color: AppColors.warning),
                                const SizedBox(width: 4),
                                Text(
                                  'В очереди: $_pendingCount',
                                  style: const TextStyle(
                                    color: AppColors.warning,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          )
                        else
                          const Icon(Icons.chevron_right, size: 18, color: Colors.white38),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: const [
                AssignmentsScreen(),
                EquipmentListScreen(),
                OpoListScreen(),
                ProtocolsRegistryScreen(),
                SyncScreen(),
                ProfileScreen(),
              ],
            ),
          ),
        ],
      ),
      // Кнопка «Создать» — показывается только на вкладке «Протоколы»
      floatingActionButton: _currentIndex == 3
          ? FloatingActionButton.extended(
              onPressed: () => _showCreateProtocolSheet(context),
              backgroundColor: AppColors.darkPrimary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Создать'),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_appVersion.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              color: AppColors.darkBackground,
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
            onTap: (index) async {
              await _loadStatus();
              setState(() {
                _currentIndex = index;
              });
            },
            backgroundColor: AppColors.darkSurface,
            selectedItemColor: AppColors.darkPrimary,
            unselectedItemColor: Colors.white70,
            type: BottomNavigationBarType.fixed,
            items: const [
              BottomNavigationBarItem(
                icon: Icon(Icons.assignment, semanticLabel: 'Задания'),
                label: 'Задания',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.list, semanticLabel: 'Оборудование'),
                label: 'Оборудование',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.dangerous, semanticLabel: 'ОПО'),
                label: 'ОПО',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.folder_copy_outlined, semanticLabel: 'Протоколы'),
                label: 'Протоколы',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.sync, semanticLabel: 'Синхронизация'),
                label: 'Синхронизация',
              ),
              BottomNavigationBarItem(
                icon: Icon(Icons.person, semanticLabel: 'Профиль'),
                label: 'Профиль',
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Меню «создать» по структуре диагностических данных (xlsx).
  void _showCreateProtocolSheet(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DiagnosticCreateMenuScreen()),
    );
  }
}
