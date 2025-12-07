import 'package:flutter/material.dart';
import '../services/sync_service.dart';
import '../services/auth_service.dart';
import 'package:intl/intl.dart';

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});

  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  final SyncService _syncService = SyncService();
  final AuthService _authService = AuthService();
  bool _isSyncing = false;
  DateTime? _lastSyncTime;
  int _pendingCount = 0;
  bool _isEngineer = false;

  @override
  void initState() {
    super.initState();
    _checkUserRole();
    _loadData();
  }

  Future<void> _checkUserRole() async {
    final user = await _authService.getCurrentUser();
    setState(() {
      _isEngineer = user?.role == 'engineer';
    });
  }

  int _pendingInspections = 0;
  int _pendingReports = 0;
  int _pendingQuestionnaires = 0;

  Future<void> _loadData() async {
    final pendingInspections = await _syncService.getPendingInspections();
    final pendingReports = await _syncService.getPendingReports();
    final pendingQuestionnaires = await _syncService.getPendingQuestionnaires();
    final lastSync = await _syncService.getLastSyncTime();
    
    setState(() {
      _pendingInspections = pendingInspections.length;
      _pendingReports = pendingReports.length;
      _pendingQuestionnaires = pendingQuestionnaires.length;
      _pendingCount = _pendingInspections + _pendingReports + _pendingQuestionnaires;
      _lastSyncTime = lastSync;
    });
  }

  Future<void> _syncNow() async {
    setState(() => _isSyncing = true);
    
    try {
      int totalSynced = 0;
      int totalFailed = 0;
      List<String> messages = [];
      
      // Синхронизация диагностик
      if (_pendingInspections > 0) {
        final result = await _syncService.syncPendingInspections();
        totalSynced += result.syncedCount;
        totalFailed += result.failedCount;
        if (result.message != null) messages.add('Диагностики: ${result.message}');
      }
      
      // Синхронизация отчетов
      if (_pendingReports > 0) {
        final result = await _syncService.syncPendingReports();
        totalSynced += result.syncedCount;
        totalFailed += result.failedCount;
        if (result.message != null) messages.add('Отчеты: ${result.message}');
      }
      
      // Синхронизация опросных листов
      if (_pendingQuestionnaires > 0) {
        final result = await _syncService.syncPendingQuestionnaires();
        totalSynced += result.syncedCount;
        totalFailed += result.failedCount;
        if (result.message != null) messages.add('Опросные листы: ${result.message}');
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              totalSynced > 0 || totalFailed > 0
                  ? 'Синхронизация завершена: $totalSynced успешно, $totalFailed ошибок'
                  : 'Нет данных для синхронизации',
            ),
            backgroundColor: totalFailed == 0 ? Colors.green : Colors.orange,
            duration: const Duration(seconds: 4),
          ),
        );
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
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Проверка: только инженеры могут синхронизировать
    if (!_isEngineer) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Синхронизация данных'),
          backgroundColor: const Color(0xFF0f172a),
          foregroundColor: Colors.white,
        ),
        backgroundColor: const Color(0xFF0f172a),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.lock_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              const Text(
                'Доступ запрещен',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Синхронизация доступна только инженерам',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

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
                          'Ожидающих синхронизации:',
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
            
            // Кнопка синхронизации
            ElevatedButton(
              onPressed: _isSyncing || _pendingCount == 0 ? null : _syncNow,
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
                  : const Text(
                      'Синхронизировать сейчас',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
            
            if (_pendingCount == 0)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Text(
                  'Нет данных для синхронизации',
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



