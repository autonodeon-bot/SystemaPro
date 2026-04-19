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
import 'quick_control_screen.dart';
import 'new_ndk_protocol_screen.dart';
import 'protocol_template_selection_screen.dart';
import 'select_equipment_for_act_screen.dart';
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
      final offlineMode = await _syncService.isOfflineMode();
      final hasConnection = await _apiService.checkConnection();
      if (mounted) {
        setState(() {
          _pendingCount = pending.length;
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

  /// Нижний лист «Создать» (П.1.1) с 4-мя подразделами
  void _showCreateProtocolSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.darkSurface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Создать протокол / акт',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Выберите тип создаваемого документа',
                style: TextStyle(color: Colors.white54, fontSize: 13),
              ),
              const SizedBox(height: 20),
              // 1.1.1 Быстрый контроль ВИК/УЗТ
              _createSheetItem(
                ctx,
                icon: Icons.flash_on,
                color: Colors.amber,
                title: 'Быстрый контроль',
                subtitle: 'ВИК, УЗТ — оперативный протокол',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const QuickControlScreen(),
                  ));
                },
              ),
              const SizedBox(height: 12),
              // 1.1.2 Новый протокол НК
              _createSheetItem(
                ctx,
                icon: Icons.assignment_add,
                color: Colors.blueAccent,
                title: 'Новый протокол НК',
                subtitle: 'Выбор методов: ВИК, УЗТ, УЗК, ПВК(МПД)',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const NewNdkProtocolScreen(),
                  ));
                },
              ),
              const SizedBox(height: 12),
              // 1.1.3 Акт ТД (ЭПБ)
              _createSheetItem(
                ctx,
                icon: Icons.description_outlined,
                color: Colors.greenAccent,
                title: 'Акт ТД (ЭПБ) оборудования',
                subtitle: 'Сосуд, котёл, буровая установка и др.',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const SelectEquipmentForActScreen(),
                  ));
                },
              ),
              const SizedBox(height: 12),
              // 1.1.4 Свой протокол (загрузка из конструктора)
              _createSheetItem(
                ctx,
                icon: Icons.layers_outlined,
                color: Colors.orangeAccent,
                title: 'Свой протокол / акт',
                subtitle: 'Выбрать шаблон из конструктора',
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ProtocolTemplateSelectionScreen(),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _createSheetItem(
    BuildContext context, {
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white30, size: 14),
          ],
        ),
      ),
    );
  }
}
