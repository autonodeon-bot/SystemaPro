import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sync_service.dart';
import '../services/api_service.dart';
import '../screens/equipment_list_screen.dart';
import 'package:intl/intl.dart';

class SyncScreen extends ConsumerStatefulWidget {
  const SyncScreen({super.key});

  @override
  ConsumerState<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends ConsumerState<SyncScreen> {
  final SyncService _syncService = SyncService();
  final ApiService _apiService = ApiService();
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  int _pendingCount = 0;
  int _uploadReportIndex = 0;
  int _uploadReportTotal = 0;
  int _uploadBytesSent = 0;
  int _uploadBytesTotal = 0;
  bool? _isOnline;
  int _signedReadyCount = 0;
  int _signedNeedsAttentionCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final pending = await _syncService.getPendingInspections();
    final lastSync = await _syncService.getLastSyncTime();
    await _checkConnection();
    
    // Подсчитываем черновики (DRAFT) и подписанные (SIGNED)
    int draftCount = 0;
    int signedCount = 0;
    int signedReadyCount = 0;
    int signedNeedsAttentionCount = 0;
    for (final item in pending) {
      final status = (item['status']?.toString().toUpperCase() ?? 'DRAFT');
      if (status == 'DRAFT') {
        draftCount += 1;
      } else if (status == 'SIGNED') {
        signedCount += 1;
        final missing = _getSignedInspectionMissingFields(item);
        if (missing.isEmpty) {
          signedReadyCount += 1;
        } else {
          signedNeedsAttentionCount += 1;
        }
      }
    }
    
    setState(() {
      _pendingCount = pending.length;
      _lastSyncTime = lastSync;
      _draftCount = draftCount;
      _signedCount = signedCount;
      _signedReadyCount = signedReadyCount;
      _signedNeedsAttentionCount = signedNeedsAttentionCount;
    });
  }
  
  int _draftCount = 0;
  int _signedCount = 0;

  Future<void> _checkConnection() async {
    final hasConnection = await _apiService.checkConnection();
    if (!mounted) return;
    setState(() {
      _isOnline = hasConnection;
    });
  }

  List<String> _getSignedInspectionMissingFields(Map<String, dynamic> item) {
    final missing = <String>[];
    final data = item['data'];
    if (data is! Map) {
      return ['Структура данных обследования'];
    }
    final payload = Map<String, dynamic>.from(data);
    final docs = item['document_files'];
    final docsMap = docs is Map ? Map<String, dynamic>.from(docs) : <String, dynamic>{};

    final organization = payload['organization']?.toString().trim() ?? '';
    final executors = payload['executors']?.toString().trim() ?? '';
    if (organization.isEmpty) {
      missing.add('Организация');
    }
    if (executors.isEmpty) {
      missing.add('Исполнители');
    }

    final hasFactoryPlate = (payload['factory_plate_photo']?.toString().trim().isNotEmpty ?? false) ||
        docsMap.containsKey('factory_plate_photo');
    final hasControlScheme = (payload['control_scheme_image']?.toString().trim().isNotEmpty ?? false) ||
        docsMap.containsKey('control_scheme_image');
    if (!hasFactoryPlate) {
      missing.add('Фото заводской таблички');
    }
    if (!hasControlScheme) {
      missing.add('Схема контроля');
    }

    return missing;
  }

  Future<void> _syncNow() async {
    if (_signedNeedsAttentionCount > 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Есть подписанные обследования с неполными данными: $_signedNeedsAttentionCount. '
              'Рекомендуется дозаполнить их перед синхронизацией для корректного отчета.',
            ),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    }

    // Проверка доступности сети перед синхронизацией (не тратим попытки при отсутствии интернета)
    final hasConnection = await _apiService.checkConnection();
    if (!hasConnection) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет интернета. Подключитесь к сети и повторите.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    setState(() {
      _isSyncing = true;
      _uploadReportIndex = 0;
      _uploadReportTotal = 0;
      _uploadBytesSent = 0;
      _uploadBytesTotal = 0;
    });
    _syncService.onUploadProgress = (index, total, sent, totalBytes) {
      if (mounted) {
        setState(() {
          _uploadReportIndex = index;
          _uploadReportTotal = total;
          _uploadBytesSent = sent;
          _uploadBytesTotal = totalBytes;
        });
      }
    };
    try {
      final result = await _syncService.syncPendingInspections();
      
      if (mounted) {
        String msg;
        if (result.syncedCount > 0 && result.failedCount == 0) {
          msg = result.syncedCount == 1
              ? 'Отправлено 1 обследование.'
              : 'Отправлено обследований: ${result.syncedCount}.';
        } else if (result.syncedCount > 0 && result.failedCount > 0) {
          msg = 'Отправлено: ${result.syncedCount}. Не удалось отправить: ${result.failedCount}. Проверьте интернет и нажмите «Синхронизировать» ещё раз.';
        } else if (result.failedCount > 0) {
          final reason = result.lastFailureReason ?? result.error;
          final reasonText = reason != null && reason.isNotEmpty
              ? (reason.length > 500 ? '${reason.substring(0, 500)}…' : reason)
              : 'Проверьте интернет или войдите в приложение заново и повторите.';
          msg = result.failedCount == 1
              ? 'Не удалось отправить 1 обследование.\nПричина: $reasonText'
              : 'Не удалось отправить ${result.failedCount} обследований.\nПричина: $reasonText';
        } else {
          msg = result.message ?? result.error ?? 'Синхронизация завершена.';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: SingleChildScrollView(
              child: Text(
                msg,
                style: const TextStyle(fontSize: 13),
              ),
            ),
            backgroundColor: result.failedCount == 0 ? Colors.green : Colors.orange,
            duration: Duration(seconds: result.failedCount > 0 && msg.length > 150 ? 8 : 4),
          ),
        );
        
        // Обновляем список оборудования в экране оборудования
        // Инвалидируем провайдер для перезагрузки данных
        ref.invalidate(equipmentListProvider);
      }
      
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Ошибка синхронизации: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSyncing = false;
          _uploadReportTotal = 0;
        });
        _syncService.onUploadProgress = null;
      }
      await _checkConnection();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Синхронизация данных'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _isSyncing ? null : _loadData,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Статистика
            Card(
              color: const Color(0xFF1e293b),
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Статистика',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Состояние сети:',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: _isOnline == true
                                ? Colors.green.withValues(alpha: 0.18)
                                : Colors.orange.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: _isOnline == true
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          ),
                          child: Text(
                            _isOnline == true ? 'Онлайн' : 'Офлайн',
                            style: TextStyle(
                              color: _isOnline == true
                                  ? Colors.greenAccent
                                  : Colors.orangeAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Всего ожидает синхронизации:',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(
                          '$_pendingCount',
                          style: const TextStyle(
                            color: Color(0xFF3b82f6),
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    if (_draftCount > 0 || _signedCount > 0) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '  • Черновики (DRAFT):',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          Text(
                            '$_draftCount',
                            style: const TextStyle(
                              color: Colors.orange,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '  • Подписанные (SIGNED):',
                            style: TextStyle(color: Colors.white70, fontSize: 14),
                          ),
                          Text(
                            '$_signedCount',
                            style: const TextStyle(
                              color: Colors.green,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                      if (_signedCount > 0) ...[
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '  • Готово к отправке:',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                            Text(
                              '$_signedReadyCount',
                              style: const TextStyle(
                                color: Colors.lightGreenAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              '  • Требует проверки:',
                              style: TextStyle(color: Colors.white70, fontSize: 14),
                            ),
                            Text(
                              '$_signedNeedsAttentionCount',
                              style: const TextStyle(
                                color: Colors.orangeAccent,
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text(
                          'Последняя синхронизация:',
                          style: TextStyle(color: Colors.white70),
                        ),
                        Text(
                          _lastSyncTime != null
                              ? DateFormat('dd.MM.yyyy HH:mm').format(_lastSyncTime!)
                              : 'Никогда',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            const SizedBox(height: 24),
            
            if (_pendingCount > 0)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: Text(
                  'Есть неотправленные обследования (в т.ч. фото). Подключитесь к интернету и нажмите кнопку ниже.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.orange, fontSize: 14),
                ),
              ),
            // Кнопка синхронизации
            Semantics(
              label: 'Синхронизировать данные с сервером. Отправляет черновики и подписанные осмотры.',
              button: true,
              child: ElevatedButton(
                onPressed: _isSyncing ? null : _syncNow,
                style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3b82f6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: _isSyncing
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Синхронизация...'),
                      ],
                    )
                  : Text(
                      _pendingCount > 0
                          ? 'Подключиться и синхронизировать'
                          : 'Синхронизировать сейчас',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
              ),
            ),

            if (_isSyncing && _uploadReportTotal > 0) ...[
              const SizedBox(height: 16),
              Text(
                'Отчёт $_uploadReportIndex из $_uploadReportTotal',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _uploadBytesTotal > 0 ? _uploadBytesSent / _uploadBytesTotal : null,
                backgroundColor: Colors.white24,
                valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFF3b82f6)),
              ),
              const SizedBox(height: 4),
              Text(
                '${(_uploadBytesSent / 1024 / 1024).toStringAsFixed(1)} МБ из ${(_uploadBytesTotal / 1024 / 1024).toStringAsFixed(1)} МБ',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ],
            
            if (_pendingCount == 0)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'Нет данных для отправки на сервер. Нажмите «Синхронизировать сейчас» для обновления списка оборудования.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            const SizedBox(height: 16),
            Theme(
              data: Theme.of(context).copyWith(
                dividerColor: Colors.transparent,
              ),
              child: const Card(
                color: Color(0xFF1e293b),
                child: ExpansionTile(
                  iconColor: Colors.white70,
                  collapsedIconColor: Colors.white54,
                  title: Text(
                    'Быстрая помощь',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  childrenPadding: EdgeInsets.fromLTRB(16, 0, 16, 16),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        '• Офлайн: данные сохраняются локально в очереди.\n'
                        '• Если часть файлов не отправилась — нажмите «Синхронизировать» повторно.\n'
                        '• При ошибке авторизации: войдите в приложение заново и повторите синхронизацию.\n'
                        '• Для больших фото нужна стабильная сеть — лучше Wi-Fi или хороший 4G.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          height: 1.45,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



