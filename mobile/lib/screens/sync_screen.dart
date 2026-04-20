import 'dart:ui' show FontFeature;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/sync_service.dart';
import '../services/api_service.dart';
import '../screens/equipment_list_screen.dart';
import '../theme/app_colors.dart';
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
        title: const Text(
          'Синхронизация',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: AppColors.darkBackgroundDeep,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: 'Обновить',
            onPressed: _isSyncing ? null : _loadData,
            icon: const Icon(Icons.refresh, size: 20),
          ),
        ],
      ),
      backgroundColor: AppColors.darkBackground,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
        children: [
          _buildStatusStrip(),
          const SizedBox(height: 12),
          _buildStatsGrid(),
          if (_signedCount > 0) ...[
            const SizedBox(height: 12),
            _buildSignedBreakdown(),
          ],
          const SizedBox(height: 12),
          _buildLastSyncRow(),
          const SizedBox(height: 20),
          _buildSyncButton(),
          if (_isSyncing && _uploadReportTotal > 0) ...[
            const SizedBox(height: 16),
            _buildUploadProgress(),
          ],
          if (_pendingCount == 0 && !_isSyncing) ...[
            const SizedBox(height: 16),
            _buildEmptyHint(),
          ],
          if (_pendingCount > 0 && !_isSyncing) ...[
            const SizedBox(height: 12),
            _buildPendingHint(),
          ],
          const SizedBox(height: 16),
          _buildQuickHelp(),
        ],
      ),
    );
  }

  Widget _buildStatusStrip() {
    final online = _isOnline == true;
    final color = online ? AppColors.success : AppColors.warning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 6, spreadRadius: 1),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            online ? 'Онлайн' : 'Офлайн',
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
          const Spacer(),
          Text(
            online ? 'Готов к отправке' : 'Нет сети — данные в очереди',
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsGrid() {
    return Row(
      children: [
        Expanded(child: _statTile('В очереди', '$_pendingCount', AppColors.accent)),
        const SizedBox(width: 8),
        Expanded(child: _statTile('Черновики', '$_draftCount', AppColors.warning)),
        const SizedBox(width: 8),
        Expanded(child: _statTile('Подписаны', '$_signedCount', AppColors.success)),
      ],
    );
  }

  Widget _statTile(String label, String value, Color accent) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: accent,
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSignedBreakdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: _miniStat(
              icon: Icons.check_circle_outline,
              color: AppColors.success,
              label: 'Готовы',
              value: '$_signedReadyCount',
            ),
          ),
          Container(width: 1, height: 28, color: AppColors.darkBorder),
          Expanded(
            child: _miniStat(
              icon: Icons.error_outline,
              color: AppColors.warning,
              label: 'Проверить',
              value: '$_signedNeedsAttentionCount',
            ),
          ),
        ],
      ),
    );
  }

  Widget _miniStat({required IconData icon, required Color color, required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(
            label,
            style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLastSyncRow() {
    final label = _lastSyncTime != null
        ? DateFormat('dd.MM.yyyy HH:mm').format(_lastSyncTime!)
        : 'Никогда';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.history, size: 16, color: AppColors.textSecondary),
          const SizedBox(width: 10),
          const Text(
            'Последняя синхронизация',
            style: TextStyle(color: AppColors.textSecondary, fontSize: 12),
          ),
          const Spacer(),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncButton() {
    return Semantics(
      label: 'Синхронизировать данные с сервером. Отправляет черновики и подписанные осмотры.',
      button: true,
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isSyncing ? null : _syncNow,
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.accent,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.darkBorder,
            disabledForegroundColor: AppColors.textSecondary,
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: _isSyncing
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Синхронизация…',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.2),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.sync, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _pendingCount > 0 ? 'Отправить $_pendingCount в очереди' : 'Обновить данные',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildUploadProgress() {
    final progress = _uploadBytesTotal > 0 ? _uploadBytesSent / _uploadBytesTotal : null;
    final sent = (_uploadBytesSent / 1024 / 1024).toStringAsFixed(1);
    final total = (_uploadBytesTotal / 1024 / 1024).toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'Отчёт $_uploadReportIndex из $_uploadReportTotal',
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              const Spacer(),
              Text(
                '$sent / $total МБ',
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: AppColors.darkBorder,
              valueColor: const AlwaysStoppedAnimation<Color>(AppColors.accent),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyHint() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.darkSurface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.darkBorder),
      ),
      child: const Row(
        children: [
          Icon(Icons.cloud_done_outlined, size: 18, color: AppColors.success),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Очередь пуста. Нажмите, чтобы обновить список оборудования с сервера.',
              style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingHint() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.35)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: AppColors.warning),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Есть неотправленные данные (включая фото). Подключитесь к сети и запустите синхронизацию.',
              style: TextStyle(color: AppColors.warning, fontSize: 12, height: 1.45),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickHelp() {
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.darkSurface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.darkBorder),
        ),
        child: const ExpansionTile(
          iconColor: AppColors.textSecondary,
          collapsedIconColor: AppColors.textSecondary,
          tilePadding: EdgeInsets.symmetric(horizontal: 12),
          title: Text(
            'Быстрая помощь',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          childrenPadding: EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '• Офлайн — данные копятся локально в очереди.\n'
                '• Часть файлов не ушла? Нажмите «Синхронизировать» снова.\n'
                '• При ошибке авторизации — перелогиньтесь и повторите.\n'
                '• Для больших фото лучше Wi-Fi или стабильный 4G.',
                style: TextStyle(color: AppColors.textSecondary, fontSize: 12, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}



