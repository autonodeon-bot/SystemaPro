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

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final pending = await _syncService.getPendingInspections();
    final lastSync = await _syncService.getLastSyncTime();
    
    // Подсчитываем черновики (DRAFT) и подписанные (SIGNED)
    int draftCount = 0;
    int signedCount = 0;
    for (final item in pending) {
      final status = (item['status']?.toString().toUpperCase() ?? 'DRAFT');
      if (status == 'DRAFT') {
        draftCount += 1;
      } else if (status == 'SIGNED') {
        signedCount += 1;
      }
    }
    
    setState(() {
      _pendingCount = pending.length;
      _lastSyncTime = lastSync;
      _draftCount = draftCount;
      _signedCount = signedCount;
    });
  }
  
  int _draftCount = 0;
  int _signedCount = 0;

  Future<void> _syncNow() async {
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
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Синхронизация данных'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
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
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Есть неотправленные обследования (в т.ч. фото). Подключитесь к интернету и нажмите кнопку ниже.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.orange, fontSize: 14),
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
          ],
        ),
      ),
    );
  }
}



