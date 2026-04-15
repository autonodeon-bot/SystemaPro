import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/auth_service.dart';
import '../models/user.dart';
import '../theme/app_colors.dart';

/// Статус состояния прибора (П.4.8)
enum InstrumentCondition { ok, damaged, broken }

extension InstrumentConditionExt on InstrumentCondition {
  String get label {
    switch (this) {
      case InstrumentCondition.ok:
        return 'Исправен';
      case InstrumentCondition.damaged:
        return 'Повреждён';
      case InstrumentCondition.broken:
        return 'Неисправен';
    }
  }

  Color get color {
    switch (this) {
      case InstrumentCondition.ok:
        return Colors.greenAccent;
      case InstrumentCondition.damaged:
        return Colors.orange;
      case InstrumentCondition.broken:
        return Colors.redAccent;
    }
  }

  IconData get icon {
    switch (this) {
      case InstrumentCondition.ok:
        return Icons.check_circle_outline;
      case InstrumentCondition.damaged:
        return Icons.warning_amber_rounded;
      case InstrumentCondition.broken:
        return Icons.cancel_outlined;
    }
  }
}

/// Экран «Реестр приборов / Приборный парк» (П.4)
class InstrumentParkScreen extends StatefulWidget {
  const InstrumentParkScreen({super.key});

  @override
  State<InstrumentParkScreen> createState() => _InstrumentParkScreenState();
}

class _InstrumentParkScreenState extends State<InstrumentParkScreen> {
  final _apiService = ApiService();
  final _authService = AuthService();

  bool _loading = true;
  List<Map<String, dynamic>> _instruments = [];
  List<Map<String, dynamic>> _filteredInstruments = [];
  List<Map<String, dynamic>> _engineers = []; // список инженеров для закрепления
  String? _filterType;
  String? _filterSpecialist;
  bool? _filterExpiring; // только с истекающей поверкой
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _currentUser = await _authService.getCurrentUser();
      final data = await _apiService.getInstruments();
      // Загружаем список инженеров для назначения прибора (П.4.2)
      try {
        final engData = await _apiService.getEngineers();
        if (mounted) {
          _engineers = List<Map<String, dynamic>>.from(engData);
        }
      } catch (_) {}
      if (mounted) {
        setState(() {
          _instruments = List<Map<String, dynamic>>.from(data);
          _applyFilters();
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка загрузки: $e')),
        );
      }
    }
  }

  void _applyFilters() {
    setState(() {
      _filteredInstruments = _instruments.where((inst) {
        if (_filterType != null && _filterType!.isNotEmpty) {
          final type = (inst['type'] as String? ?? '').toLowerCase();
          if (!type.contains(_filterType!.toLowerCase())) return false;
        }
        if (_filterSpecialist != null && _filterSpecialist!.isNotEmpty) {
          final spec = (inst['specialist_name'] as String? ?? '').toLowerCase();
          if (!spec.contains(_filterSpecialist!.toLowerCase())) return false;
        }
        if (_filterExpiring == true) {
          final vUntil = inst['verification_until'] as String?;
          if (vUntil != null) {
            try {
              final dt = DateTime.parse(vUntil);
              if (!dt.isBefore(DateTime.now().add(const Duration(days: 30)))) {
                return false;
              }
            } catch (_) {}
          }
        }
        return true;
      }).toList();
    });
  }

  bool _isUserOperatorOrAdmin() {
    final role = _currentUser?.role ?? '';
    return role == 'admin' ||
        role == 'chief_operator' ||
        role == 'operator';
  }

  Future<void> _showAddEditDialog({Map<String, dynamic>? existing}) async {
    final nameCtrl = TextEditingController(text: existing?['name'] as String? ?? '');
    final typeCtrl = TextEditingController(text: existing?['type'] as String? ?? '');
    final serialCtrl = TextEditingController(text: existing?['serial_number'] as String? ?? '');
    final verUntilCtrl = TextEditingController(text: existing?['verification_until'] as String? ?? '');
    final conditionCtrl = TextEditingController(text: existing?['condition_notes'] as String? ?? '');

    InstrumentCondition condition = InstrumentCondition.ok;
    if (existing != null) {
      final c = existing['condition'] as String? ?? 'ok';
      if (c == 'damaged') condition = InstrumentCondition.damaged;
      if (c == 'broken') condition = InstrumentCondition.broken;
    }

    // Выбранный специалист (П.4.2) — по умолчанию из существующего прибора
    String? selectedSpecialistId = existing?['specialist_id'] as String?;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: Text(existing != null ? 'Редактировать прибор' : 'Добавить прибор'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(labelText: 'Наименование *'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: typeCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Тип (УЗТ, УЗК, ВИК, ПВК...)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: serialCtrl,
                  decoration: const InputDecoration(labelText: 'Зав. номер'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: verUntilCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Поверка до (YYYY-MM)',
                      hintText: '2026-08'),
                ),
                const SizedBox(height: 8),
                // Закрепить за специалистом (П.4.2)
                DropdownButtonFormField<String?>(
                  value: selectedSpecialistId,
                  decoration: const InputDecoration(
                    labelText: 'Закрепить за специалистом',
                    prefixIcon: Icon(Icons.person_outline, size: 18),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('— Не закреплён —'),
                    ),
                    ..._engineers.map((eng) {
                      final id = (eng['id'] ?? eng['user_id'] ?? '').toString();
                      final name = (eng['full_name'] ?? eng['username'] ?? 'Инженер').toString();
                      return DropdownMenuItem<String?>(
                        value: id,
                        child: Text(name, overflow: TextOverflow.ellipsis),
                      );
                    }),
                  ],
                  onChanged: (v) => setLocal(() => selectedSpecialistId = v),
                ),
                const SizedBox(height: 8),
                // Состояние прибора (П.4.8)
                DropdownButtonFormField<InstrumentCondition>(
                  value: condition,
                  decoration: const InputDecoration(labelText: 'Состояние'),
                  items: InstrumentCondition.values
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Row(
                              children: [
                                Icon(c.icon, color: c.color, size: 16),
                                const SizedBox(width: 8),
                                Text(c.label),
                              ],
                            ),
                          ))
                      .toList(),
                  onChanged: (v) => setLocal(() => condition = v!),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: conditionCtrl,
                  decoration: const InputDecoration(
                      labelText: 'Примечание к состоянию'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final payload = {
                  'name': nameCtrl.text.trim(),
                  'type': typeCtrl.text.trim(),
                  'serial_number': serialCtrl.text.trim(),
                  'verification_until': verUntilCtrl.text.trim(),
                  'condition': condition.name,
                  'condition_notes': conditionCtrl.text.trim(),
                  'specialist_id': selectedSpecialistId,
                };
                Navigator.pop(ctx);
                try {
                  if (existing != null) {
                    await _apiService.updateInstrument(
                        existing['id'].toString(), payload);
                  } else {
                    await _apiService.createInstrument(payload);
                  }
                  await _load();
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Ошибка: $e')),
                    );
                  }
                }
              },
              child: Text(existing != null ? 'Сохранить' : 'Добавить'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteInstrument(Map<String, dynamic> inst) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Подтверждение удаления'),
        content: Text('Удалить прибор "${inst['name']}"?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Нет')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Да'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await _apiService.deleteInstrument(inst['id'].toString());
        await _load();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка: $e')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.darkBackground,
      appBar: AppBar(
        title: const Text('Приборный парк'),
        backgroundColor: AppColors.darkSurface,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list),
            onPressed: _showFilterDialog,
            tooltip: 'Фильтры',
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
            tooltip: 'Обновить',
          ),
        ],
      ),
      floatingActionButton: _isUserOperatorOrAdmin()
          ? FloatingActionButton.extended(
              onPressed: () => _showAddEditDialog(),
              backgroundColor: AppColors.darkPrimary,
              foregroundColor: Colors.white,
              icon: const Icon(Icons.add),
              label: const Text('Добавить прибор'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                if (_filterType != null || _filterSpecialist != null || _filterExpiring == true)
                  _buildActiveFilters(),
                _buildStats(),
                Expanded(
                  child: _filteredInstruments.isEmpty
                      ? _buildEmpty()
                      : _buildInstrumentTable(),
                ),
              ],
            ),
    );
  }

  Widget _buildStats() {
    final total = _instruments.length;
    final expiringSoon = _instruments.where((i) {
      final v = i['verification_until'] as String?;
      if (v == null) return false;
      try {
        return DateTime.parse('$v-01')
            .isBefore(DateTime.now().add(const Duration(days: 30)));
      } catch (_) {
        return false;
      }
    }).length;
    final broken = _instruments
        .where((i) => i['condition'] == 'damaged' || i['condition'] == 'broken')
        .length;

    return Container(
      color: AppColors.darkSurface,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          _statChip('Всего: $total', Colors.white60),
          const SizedBox(width: 12),
          if (expiringSoon > 0)
            _statChip('Поверка истекает: $expiringSoon', Colors.orange),
          if (broken > 0) ...[
            const SizedBox(width: 12),
            _statChip('Неисправных: $broken', Colors.redAccent),
          ],
        ],
      ),
    );
  }

  Widget _statChip(String label, Color color) {
    return Text(label,
        style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500));
  }

  Widget _buildActiveFilters() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: AppColors.darkPrimary.withOpacity(0.15),
      child: Row(
        children: [
          const Icon(Icons.filter_list, color: Colors.white60, size: 14),
          const SizedBox(width: 4),
          const Text('Фильтр: ',
              style: TextStyle(color: Colors.white60, fontSize: 12)),
          if (_filterType != null)
            _filterTag('Тип: $_filterType'),
          if (_filterSpecialist != null)
            _filterTag('Специалист: $_filterSpecialist'),
          if (_filterExpiring == true)
            _filterTag('Поверка истекает'),
          const Spacer(),
          GestureDetector(
            onTap: () {
              setState(() {
                _filterType = null;
                _filterSpecialist = null;
                _filterExpiring = null;
              });
              _applyFilters();
            },
            child: const Text('Сбросить',
                style: TextStyle(
                    color: AppColors.darkPrimary, fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _filterTag(String label) {
    return Container(
      margin: const EdgeInsets.only(left: 4),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.darkPrimary.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 11)),
    );
  }

  InstrumentCondition _parseCondition(String? code) {
    switch (code) {
      case 'damaged':
        return InstrumentCondition.damaged;
      case 'broken':
        return InstrumentCondition.broken;
      default:
        return InstrumentCondition.ok;
    }
  }

  /// Возвращает цвет поверки: красный=истёк, оранжевый=скоро, зелёный=ОК
  Color _verColor(String? verUntil) {
    if (verUntil == null || verUntil.isEmpty || verUntil == '—') return Colors.white38;
    try {
      final dt = DateTime.parse('$verUntil-01');
      if (dt.isBefore(DateTime.now())) return Colors.redAccent;
      if (dt.isBefore(DateTime.now().add(const Duration(days: 90)))) return Colors.orange;
      return Colors.greenAccent;
    } catch (_) {
      return Colors.white38;
    }
  }

  Widget _buildInstrumentTable() {
    return SingleChildScrollView(
      scrollDirection: Axis.vertical,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Заголовок таблицы
            Container(
              color: AppColors.darkSurface,
              child: Row(
                children: [
                  _thCell('№', 36),
                  _thCell('Наименование', 130),
                  _thCell('Тип', 60),
                  _thCell('Поверка до', 88),
                  _thCell('Состояние', 160),
                  _thCell('Специалист', 120),
                  if (_isUserOperatorOrAdmin()) _thCell('', 64),
                ],
              ),
            ),
            const Divider(height: 1, color: Colors.white24),
            // Строки таблицы
            ...List.generate(_filteredInstruments.length, (idx) {
              final inst = _filteredInstruments[idx];
              final name = (inst['name'] as String?) ?? 'Прибор';
              final type = (inst['type'] as String?) ?? '';
              final verUntil = (inst['verification_until'] as String?) ?? '—';
              final specialist = (inst['specialist_name'] as String?) ?? '—';
              final cond = _parseCondition(inst['condition'] as String?);
              final condNotes = (inst['condition_notes'] as String?) ?? '';
              final condLabel =
                  condNotes.isNotEmpty ? condNotes : cond.label;
              final verColor = _verColor(inst['verification_until'] as String?);

              return Column(
                children: [
                  InkWell(
                    onTap: _isUserOperatorOrAdmin()
                        ? () => _showAddEditDialog(existing: inst)
                        : null,
                    child: Container(
                      color: idx.isOdd
                          ? Colors.white.withOpacity(0.03)
                          : Colors.transparent,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          _tdCell(
                            Text('${idx + 1}',
                                style: const TextStyle(
                                    color: Colors.white54, fontSize: 12)),
                            36,
                          ),
                          _tdCell(
                            Text(name,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w500,
                                    fontSize: 12),
                                overflow: TextOverflow.ellipsis),
                            130,
                          ),
                          _tdCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: AppColors.darkPrimary.withOpacity(0.2),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(type,
                                  style: TextStyle(
                                      color: AppColors.darkPrimary,
                                      fontSize: 11)),
                            ),
                            60,
                          ),
                          _tdCell(
                            Text(verUntil,
                                style: TextStyle(
                                    color: verColor,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                            88,
                          ),
                          _tdCell(
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 3),
                              decoration: BoxDecoration(
                                color: cond.color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(condLabel,
                                  style: TextStyle(
                                      color: cond.color, fontSize: 11),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            160,
                          ),
                          _tdCell(
                            Text(specialist,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                                overflow: TextOverflow.ellipsis),
                            120,
                          ),
                          if (_isUserOperatorOrAdmin())
                            SizedBox(
                              width: 64,
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  InkWell(
                                    onTap: () =>
                                        _showAddEditDialog(existing: inst),
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(Icons.edit,
                                          color: Colors.white54, size: 15),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () => _deleteInstrument(inst),
                                    child: const Padding(
                                      padding: EdgeInsets.all(6),
                                      child: Icon(Icons.delete,
                                          color: Colors.redAccent, size: 15),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white12),
                ],
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _thCell(String label, double width) => SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 9),
          child: Text(label,
              style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontWeight: FontWeight.w700),
              overflow: TextOverflow.ellipsis),
        ),
      );

  Widget _tdCell(Widget child, double width) => SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: child,
        ),
      );

  Widget _buildEmpty() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.build_circle_outlined, size: 48, color: Colors.white30),
          const SizedBox(height: 16),
          const Text('Приборов не найдено',
              style: TextStyle(color: Colors.white54)),
          const SizedBox(height: 8),
          if (_isUserOperatorOrAdmin())
            ElevatedButton.icon(
              onPressed: () => _showAddEditDialog(),
              icon: const Icon(Icons.add, size: 16),
              label: const Text('Добавить первый прибор'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkPrimary,
                foregroundColor: Colors.white,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showFilterDialog() async {
    String? tmpType = _filterType;
    String? tmpSpec = _filterSpecialist;
    bool? tmpExpiring = _filterExpiring;

    // Собираем уникальные типы и специалисты
    final types = _instruments
        .map((i) => (i['type'] as String?) ?? '')
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
    final specialists = _instruments
        .map((i) => (i['specialist_name'] as String?) ?? '')
        .where((s) => s.isNotEmpty)
        .toSet()
        .toList()
      ..sort();

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Фильтры'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Тип
              DropdownButtonFormField<String>(
                value: tmpType,
                decoration: const InputDecoration(labelText: 'Тип прибора'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Все типы')),
                  ...types.map((t) => DropdownMenuItem(value: t, child: Text(t))),
                ],
                onChanged: (v) => setLocal(() => tmpType = v),
              ),
              const SizedBox(height: 12),
              // Специалист
              DropdownButtonFormField<String>(
                value: tmpSpec,
                decoration: const InputDecoration(labelText: 'Специалист'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Все')),
                  ...specialists.map(
                      (s) => DropdownMenuItem(value: s, child: Text(s))),
                ],
                onChanged: (v) => setLocal(() => tmpSpec = v),
              ),
              const SizedBox(height: 12),
              // Поверка истекает
              CheckboxListTile(
                value: tmpExpiring ?? false,
                title: const Text('Только с истекающей поверкой'),
                contentPadding: EdgeInsets.zero,
                onChanged: (v) => setLocal(() => tmpExpiring = v),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена'),
            ),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _filterType = tmpType;
                  _filterSpecialist = tmpSpec;
                  _filterExpiring = tmpExpiring;
                });
                _applyFilters();
                Navigator.pop(ctx);
              },
              child: const Text('Применить'),
            ),
          ],
        ),
      ),
    );
  }
}
