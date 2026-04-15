import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../models/vessel_checklist.dart';
import '../theme/app_colors.dart';

/// Степень опасности дефекта (по НТД)
enum _DefectSeverity {
  critical('Критический', Colors.red),
  significant('Значительный', Colors.orange),
  minor('Малозначительный', Colors.yellow);

  const _DefectSeverity(this.label, this.color);
  final String label;
  final Color color;
}

/// Строка ведомости дефектов
class _DefectRow {
  int num;
  String defectName = '';      // Наименование/вид дефекта
  String location = '';        // Место расположения (элемент, узел, зона)
  String size = '';            // Размер дефекта, мм
  _DefectSeverity severity = _DefectSeverity.significant;
  String recommendation = '';  // Рекомендуемые мероприятия
  String notes = '';           // Примечания

  _DefectRow(this.num);

  factory _DefectRow.fromVik(int num, Map<String, dynamic> vikDefect) {
    final r = _DefectRow(num);
    r.defectName = (vikDefect['defect_type'] as String? ?? '').isNotEmpty
        ? vikDefect['defect_type'].toString()
        : 'Дефект ВИК';
    r.location = vikDefect['location']?.toString() ?? '';
    r.size = vikDefect['size']?.toString() ?? '';
    r.notes = vikDefect['description']?.toString() ?? '';
    return r;
  }

  factory _DefectRow.fromUzt(int num, ThicknessMeasurement m) {
    final r = _DefectRow(num);
    r.defectName = 'Утонение стенки (УЗТ)';
    r.location = m.location.isNotEmpty ? m.location : 'Точка ${m.sectionNumber}';
    if (m.thickness != null) {
      r.size = 'Факт: ${m.thickness!.toStringAsFixed(1)} мм'
          '${m.nominalThickness != null ? ' (ном. ${m.nominalThickness!.toStringAsFixed(1)} мм)' : ''}';
      if (m.minAllowedThickness != null &&
          m.thickness! < m.minAllowedThickness!) {
        r.severity = _DefectSeverity.critical;
        r.recommendation = 'Требует немедленного ремонта или замены элемента';
      }
    }
    return r;
  }
}

/// Ведомость дефектов (П.6).
/// Стандартный бланк по результатам НК.
/// Формат соответствует общепринятой практике оформления
/// ведомостей дефектов для сосудов, трубопроводов и ОПО.
class DefectStatementScreen extends StatefulWidget {
  final String objectName;
  final String date;
  final String executor;
  final String customer;
  final String devices;
  final String normDoc;
  final List<String> controlMethods;
  final List<Map<String, dynamic>> vikDefects;
  final List<ThicknessMeasurement> uztMeasurements;

  const DefectStatementScreen({
    super.key,
    required this.objectName,
    required this.date,
    required this.executor,
    required this.customer,
    required this.devices,
    required this.normDoc,
    this.controlMethods = const [],
    this.vikDefects = const [],
    this.uztMeasurements = const [],
  });

  @override
  State<DefectStatementScreen> createState() => _DefectStatementScreenState();
}

class _DefectStatementScreenState extends State<DefectStatementScreen> {
  final _objectCtrl = TextEditingController();
  final _dateCtrl = TextEditingController();
  final _executorCtrl = TextEditingController();
  final _certCtrl = TextEditingController();     // № сертификата
  final _customerCtrl = TextEditingController();
  final _devicesCtrl = TextEditingController();
  final _normDocCtrl = TextEditingController();
  final _conclusionCtrl = TextEditingController();
  final _orgCtrl = TextEditingController();      // Организация
  final _docNumCtrl = TextEditingController();   // № ведомости

  List<_DefectRow> _rows = [];
  bool _editMode = true; // редактирование или просмотр
  bool _showCriticalOnly = false;

  @override
  void initState() {
    super.initState();
    _objectCtrl.text = widget.objectName;
    _dateCtrl.text = widget.date.isNotEmpty
        ? widget.date
        : intl.DateFormat('dd.MM.yyyy').format(DateTime.now());
    _executorCtrl.text = widget.executor;
    _customerCtrl.text = widget.customer;
    _devicesCtrl.text = widget.devices;
    _normDocCtrl.text = widget.normDoc.isNotEmpty
        ? widget.normDoc
        : 'РД 03-421-01, ГОСТ Р 55614-2013';
    _docNumCtrl.text =
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-${DateTime.now().millisecondsSinceEpoch % 1000}';

    _buildInitialRows();
    _updateConclusion();
  }

  @override
  void dispose() {
    _objectCtrl.dispose();
    _dateCtrl.dispose();
    _executorCtrl.dispose();
    _certCtrl.dispose();
    _customerCtrl.dispose();
    _devicesCtrl.dispose();
    _normDocCtrl.dispose();
    _conclusionCtrl.dispose();
    _orgCtrl.dispose();
    _docNumCtrl.dispose();
    super.dispose();
  }

  void _buildInitialRows() {
    int num = 1;
    final rows = <_DefectRow>[];

    // ВИК дефекты
    for (final d in widget.vikDefects) {
      rows.add(_DefectRow.fromVik(num++, d));
    }

    // УЗТ — только точки с потерей стенки (меньше отбраковочной)
    for (final m in widget.uztMeasurements) {
      if (m.thickness != null &&
          m.minAllowedThickness != null &&
          m.thickness! < m.minAllowedThickness!) {
        rows.add(_DefectRow.fromUzt(num++, m));
      }
    }

    // Если нет дефектов — добавляем пустую строку
    if (rows.isEmpty) rows.add(_DefectRow(1));

    setState(() => _rows = rows);
  }

  void _updateConclusion() {
    final hasCritical = _rows.any((r) => r.severity == _DefectSeverity.critical);
    final count = _rows.where((r) => r.defectName.trim().isNotEmpty).length;

    if (count == 0) {
      _conclusionCtrl.text =
          'Дефектов, снижающих работоспособность объекта, не обнаружено. '
          'Объект соответствует требованиям НТД.';
    } else if (hasCritical) {
      _conclusionCtrl.text =
          'По результатам контроля выявлено $count дефект(ов). '
          'Обнаружены критические дефекты. '
          'Дальнейшая эксплуатация объекта НЕ ДОПУСКАЕТСЯ до устранения дефектов.';
    } else {
      _conclusionCtrl.text =
          'По результатам контроля выявлено $count дефект(ов) '
          'незначительного характера. Рекомендуется устранение в плановом порядке.';
    }
  }

  void _addRow() {
    setState(() {
      final n = _rows.isEmpty ? 1 : _rows.last.num + 1;
      _rows.add(_DefectRow(n));
    });
  }

  Future<void> _deleteRow(int idx) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить строку?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Нет')),
          TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Да')),
        ],
      ),
    );
    if (ok == true) {
      setState(() {
        _rows.removeAt(idx);
        for (int i = 0; i < _rows.length; i++) {
          _rows[i].num = i + 1;
        }
      });
      _updateConclusion();
    }
  }

  Future<void> _editRow(int idx) async {
    final row = _rows[idx];
    final nameCtrl = TextEditingController(text: row.defectName);
    final locCtrl = TextEditingController(text: row.location);
    final sizeCtrl = TextEditingController(text: row.size);
    final recCtrl = TextEditingController(text: row.recommendation);
    final notesCtrl = TextEditingController(text: row.notes);
    var severity = row.severity;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Дефект № ${row.num}'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                    controller: nameCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Наименование / вид дефекта *')),
                const SizedBox(height: 8),
                TextField(
                    controller: locCtrl,
                    decoration: const InputDecoration(
                        labelText: 'Место расположения (элемент, узел)')),
                const SizedBox(height: 8),
                TextField(
                    controller: sizeCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Размеры дефекта, мм')),
                const SizedBox(height: 8),
                DropdownButtonFormField<_DefectSeverity>(
                  value: severity,
                  decoration: const InputDecoration(labelText: 'Степень опасности'),
                  items: _DefectSeverity.values
                      .map((s) => DropdownMenuItem(
                            value: s,
                            child: Row(children: [
                              Icon(Icons.circle, color: s.color, size: 12),
                              const SizedBox(width: 6),
                              Text(s.label),
                            ]),
                          ))
                      .toList(),
                  onChanged: (v) => set(() => severity = v!),
                ),
                const SizedBox(height: 8),
                TextField(
                    controller: recCtrl,
                    maxLines: 2,
                    decoration: const InputDecoration(
                        labelText: 'Рекомендуемые мероприятия')),
                const SizedBox(height: 8),
                TextField(
                    controller: notesCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Примечания')),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена')),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  row
                    ..defectName = nameCtrl.text
                    ..location = locCtrl.text
                    ..size = sizeCtrl.text
                    ..severity = severity
                    ..recommendation = recCtrl.text
                    ..notes = notesCtrl.text;
                });
                _updateConclusion();
                Navigator.pop(ctx);
              },
              child: const Text('Сохранить'),
            ),
          ],
        ),
      ),
    );

    nameCtrl.dispose();
    locCtrl.dispose();
    sizeCtrl.dispose();
    recCtrl.dispose();
    notesCtrl.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final displayRows = _showCriticalOnly
        ? _rows.where((r) => r.severity == _DefectSeverity.critical).toList()
        : _rows;

    return Scaffold(
      backgroundColor: const Color(0xFF0f172a),
      appBar: AppBar(
        title: const Text('Ведомость дефектов'),
        backgroundColor: const Color(0xFF1e293b),
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Icon(
              _editMode ? Icons.visibility_outlined : Icons.edit_outlined,
              color: Colors.white70,
            ),
            tooltip: _editMode ? 'Режим просмотра' : 'Редактировать',
            onPressed: () => setState(() => _editMode = !_editMode),
          ),
          IconButton(
            icon: const Icon(Icons.filter_list, color: Colors.white70),
            tooltip: _showCriticalOnly
                ? 'Показать все'
                : 'Только критические',
            onPressed: () => setState(() => _showCriticalOnly = !_showCriticalOnly),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Шапка документа ──────────────────────────────────────────────
          _buildDocumentHeader(),
          const SizedBox(height: 16),

          // ── Сведения об объекте ──────────────────────────────────────────
          _sectionTitle('СВЕДЕНИЯ ОБ ОБЪЕКТЕ'),
          _buildInfoGrid(),
          const SizedBox(height: 16),

          // ── Таблица дефектов ─────────────────────────────────────────────
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _sectionTitleInline('ПЕРЕЧЕНЬ ВЫЯВЛЕННЫХ ДЕФЕКТОВ'),
              if (_showCriticalOnly)
                const Chip(
                  label: Text('Только критические',
                      style: TextStyle(fontSize: 10, color: Colors.white)),
                  backgroundColor: Colors.red,
                  visualDensity: VisualDensity.compact,
                ),
            ],
          ),
          const SizedBox(height: 8),
          _buildDefectsTable(displayRows),

          if (_editMode) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add, size: 14),
              label: const Text('Добавить строку'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.darkPrimary,
                side: BorderSide(color: AppColors.darkPrimary),
              ),
            ),
          ],

          // ── Статистика ───────────────────────────────────────────────────
          const SizedBox(height: 16),
          _buildStats(),

          // ── Заключение ───────────────────────────────────────────────────
          const SizedBox(height: 16),
          _sectionTitle('ЗАКЛЮЧЕНИЕ'),
          TextField(
            controller: _conclusionCtrl,
            readOnly: !_editMode,
            maxLines: 4,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            decoration: _inputDecor('Заключение по результатам контроля'),
          ),
          const SizedBox(height: 16),

          // ── Подписи ──────────────────────────────────────────────────────
          _sectionTitle('ПОДПИСИ'),
          _buildSignatures(),
          const SizedBox(height: 32),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  // ── Шапка документа ────────────────────────────────────────────────────────

  Widget _buildDocumentHeader() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF1e293b),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          const Text(
            'ВЕДОМОСТЬ ДЕФЕКТОВ',
            style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.5),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            'по результатам неразрушающего контроля',
            style: TextStyle(color: Colors.white60, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          if (_editMode)
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _orgCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: _inputDecor('Организация'),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _docNumCtrl,
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                    decoration: _inputDecor('№ ведомости'),
                  ),
                ),
              ],
            )
          else ...[
            if (_orgCtrl.text.isNotEmpty)
              Text(_orgCtrl.text,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 12),
                  textAlign: TextAlign.center),
            Text('№ ${_docNumCtrl.text}',
                style: const TextStyle(
                    color: Colors.white54, fontSize: 11),
                textAlign: TextAlign.center),
          ],
        ],
      ),
    );
  }

  // ── Сведения об объекте ────────────────────────────────────────────────────

  Widget _buildInfoGrid() {
    if (_editMode) {
      return Column(
        children: [
          _row2(
            _editField(_objectCtrl, 'Наименование объекта *'),
            _editField(_dateCtrl, 'Дата составления'),
          ),
          const SizedBox(height: 8),
          _row2(
            _editField(_customerCtrl, 'Заказчик (организация)'),
            _editField(_executorCtrl, 'Исполнитель (ФИО)'),
          ),
          const SizedBox(height: 8),
          _row2(
            _editField(_certCtrl, '№ сертификата / удостоверения'),
            _editField(_normDocCtrl, 'НТД / ГОСТ'),
          ),
          const SizedBox(height: 8),
          _editField(_devicesCtrl, 'Применяемые приборы'),
        ],
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1e293b),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Table(
        columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(1.5)},
        border: TableBorder.all(color: Colors.white12, width: 0.5),
        children: [
          _tableRow('Объект:', _objectCtrl.text),
          _tableRow('Дата:', _dateCtrl.text),
          _tableRow('Заказчик:', _customerCtrl.text),
          _tableRow('Исполнитель:', _executorCtrl.text),
          if (_certCtrl.text.isNotEmpty)
            _tableRow('Сертификат:', _certCtrl.text),
          _tableRow('НТД:', _normDocCtrl.text),
          if (_devicesCtrl.text.isNotEmpty)
            _tableRow('Приборы:', _devicesCtrl.text),
          if (widget.controlMethods.isNotEmpty)
            _tableRow('Методы НК:', widget.controlMethods.join(', ')),
        ],
      ),
    );
  }

  TableRow _tableRow(String key, String value) => TableRow(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(key,
                style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                    fontWeight: FontWeight.w500)),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Text(value.isNotEmpty ? value : '—',
                style: const TextStyle(color: Colors.white, fontSize: 12)),
          ),
        ],
      );

  // ── Таблица дефектов ───────────────────────────────────────────────────────

  Widget _buildDefectsTable(List<_DefectRow> rows) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1e293b),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFF0f172a)),
          dataRowColor: WidgetStateProperty.all(const Color(0xFF1e293b)),
          columnSpacing: 8,
          headingTextStyle: const TextStyle(
              color: Colors.white60,
              fontSize: 11,
              fontWeight: FontWeight.w600),
          dataTextStyle:
              const TextStyle(color: Colors.white, fontSize: 11),
          columns: const [
            DataColumn(label: Text('№')),
            DataColumn(label: Text('Наим./вид дефекта')),
            DataColumn(label: Text('Место\nрасположения')),
            DataColumn(label: Text('Размеры,\nмм')),
            DataColumn(label: Text('Степень\nопасности')),
            DataColumn(label: Text('Рекомендации')),
            DataColumn(label: Text('Примеч.')),
            DataColumn(label: Text('')),
          ],
          rows: rows.asMap().entries.map((entry) {
            final idx = entry.key;
            final r = entry.value;
            return DataRow(cells: [
              DataCell(Text('${r.num}')),
              DataCell(SizedBox(
                  width: 130,
                  child: Text(r.defectName,
                      overflow: TextOverflow.ellipsis))),
              DataCell(SizedBox(
                  width: 100,
                  child: Text(r.location,
                      overflow: TextOverflow.ellipsis))),
              DataCell(Text(r.size)),
              DataCell(
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: r.severity.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: r.severity.color.withOpacity(0.5)),
                  ),
                  child: Text(
                    r.severity.label,
                    style: TextStyle(
                        color: r.severity.color,
                        fontSize: 10,
                        fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              DataCell(SizedBox(
                  width: 130,
                  child: Text(r.recommendation,
                      overflow: TextOverflow.ellipsis))),
              DataCell(SizedBox(
                  width: 80,
                  child: Text(r.notes, overflow: TextOverflow.ellipsis))),
              DataCell(
                _editMode
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 26, minHeight: 26),
                            icon: const Icon(Icons.edit,
                                color: Colors.white54, size: 14),
                            onPressed: () => _editRow(idx),
                          ),
                          IconButton(
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                                minWidth: 26, minHeight: 26),
                            icon: const Icon(Icons.delete,
                                color: Colors.redAccent, size: 14),
                            onPressed: () => _deleteRow(idx),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }

  // ── Статистика ────────────────────────────────────────────────────────────

  Widget _buildStats() {
    final critical =
        _rows.where((r) => r.severity == _DefectSeverity.critical).length;
    final significant =
        _rows.where((r) => r.severity == _DefectSeverity.significant).length;
    final minor =
        _rows.where((r) => r.severity == _DefectSeverity.minor).length;
    final total =
        _rows.where((r) => r.defectName.trim().isNotEmpty).length;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1e293b),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _statItem('Всего', total.toString(), Colors.white70),
          _statItem('Критических', critical.toString(), Colors.red),
          _statItem('Значительных', significant.toString(), Colors.orange),
          _statItem('Малозначит.', minor.toString(), Colors.yellow),
        ],
      ),
    );
  }

  Widget _statItem(String label, String value, Color color) => Column(
        children: [
          Text(value,
              style: TextStyle(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.bold)),
          Text(label,
              style: const TextStyle(color: Colors.white54, fontSize: 10)),
        ],
      );

  // ── Подписи ────────────────────────────────────────────────────────────────

  Widget _buildSignatures() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF1e293b),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        children: [
          _signLine('Исполнитель НК', _executorCtrl.text),
          const SizedBox(height: 12),
          _signLine('Ответственный за контроль', ''),
          const SizedBox(height: 12),
          _signLine('Представитель заказчика', _customerCtrl.text),
        ],
      ),
    );
  }

  Widget _signLine(String title, String name) => Row(
        children: [
          Expanded(
            flex: 2,
            child: Text(title,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 12)),
          ),
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 28,
                  decoration: const BoxDecoration(
                    border: Border(
                        bottom: BorderSide(color: Colors.white38)),
                  ),
                  child: name.isNotEmpty
                      ? Text(name,
                          style: const TextStyle(
                              color: Colors.white, fontSize: 12))
                      : null,
                ),
                const SizedBox(height: 2),
                Text(
                  name.isNotEmpty ? name : '(Ф.И.О. / подпись / дата)',
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 9),
                ),
              ],
            ),
          ),
        ],
      );

  // ── Кнопки нижней панели ──────────────────────────────────────────────────

  Widget _buildBottomBar() {
    return Container(
      color: const Color(0xFF1e293b),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _exportPdf,
              icon: const Icon(Icons.picture_as_pdf, size: 15),
              label: const Text('Экспорт PDF'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(color: Colors.white30),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ElevatedButton.icon(
              onPressed: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                      content: Text('Ведомость сохранена'),
                      backgroundColor: Colors.green),
                );
                Navigator.of(context).pop();
              },
              icon: const Icon(Icons.check_circle_outline, size: 15),
              label: const Text('Завершить'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.darkPrimary,
                foregroundColor: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PDF-экспорт ───────────────────────────────────────────────────────────

  Future<void> _exportPdf() async {
    try {
      final pdf = pw.Document();
      pw.Font? base;
      pw.Font? bold;
      try {
        base = await PdfGoogleFonts.notoSansRegular();
        bold = await PdfGoogleFonts.notoSansBold();
      } catch (_) {}

      pw.TextStyle ts(double size, {bool isBold = false, PdfColor? color}) =>
          pw.TextStyle(
            font: isBold ? bold : base,
            fontSize: size,
            color: color ?? PdfColors.black,
          );

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4,
          margin: const pw.EdgeInsets.all(24),
          build: (ctx) => [
            // Заголовок
            pw.Center(
              child: pw.Text('ВЕДОМОСТЬ ДЕФЕКТОВ',
                  style: ts(14, isBold: true, color: PdfColors.blue900)),
            ),
            pw.SizedBox(height: 4),
            pw.Center(
              child: pw.Text(_objectCtrl.text.isNotEmpty ? _objectCtrl.text : '',
                  style: ts(11)),
            ),
            pw.SizedBox(height: 8),
            // Реквизиты
            pw.Container(
              decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
              padding: const pw.EdgeInsets.all(6),
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  _pdfLine('Дата:', _dateCtrl.text, ts(9), ts(9, isBold: true)),
                  _pdfLine('Объект:', _objectCtrl.text, ts(9), ts(9, isBold: true)),
                  _pdfLine('Заказчик:', _customerCtrl.text, ts(9), ts(9, isBold: true)),
                  _pdfLine('Исполнитель:', _executorCtrl.text, ts(9), ts(9, isBold: true)),
                  _pdfLine('Приборы:', _devicesCtrl.text, ts(9), ts(9, isBold: true)),
                  _pdfLine('НД:', _normDocCtrl.text, ts(9), ts(9, isBold: true)),
                ],
              ),
            ),
            pw.SizedBox(height: 8),
            // Таблица дефектов
            pw.Text('Перечень дефектов:', style: ts(10, isBold: true)),
            pw.SizedBox(height: 4),
            pw.Table.fromTextArray(
              headers: ['№', 'Наименование / вид дефекта', 'Место расположения', 'Размер', 'Степень', 'Рекомендации'],
              data: _rows.map((d) => [
                '${d.num}',
                d.defectName,
                d.location,
                d.size,
                d.severity.label,
                d.recommendation,
              ]).toList(),
              headerStyle: ts(8, isBold: true, color: PdfColors.white),
              headerDecoration: const pw.BoxDecoration(color: PdfColors.blue900),
              cellStyle: ts(8),
              cellHeight: 20,
              cellAlignments: {
                0: pw.Alignment.center,
                3: pw.Alignment.center,
                4: pw.Alignment.center,
              },
            ),
            pw.SizedBox(height: 8),
            // Заключение
            if (_conclusionCtrl.text.isNotEmpty) ...[
              pw.Text('Заключение:', style: ts(10, isBold: true)),
              pw.SizedBox(height: 4),
              pw.Container(
                decoration: pw.BoxDecoration(border: pw.Border.all(color: PdfColors.grey300)),
                padding: const pw.EdgeInsets.all(6),
                child: pw.Text(_conclusionCtrl.text, style: ts(9)),
              ),
              pw.SizedBox(height: 8),
            ],
            // Подписи
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Исполнитель: ${_executorCtrl.text}', style: ts(9)),
                pw.Text('Подпись: ___________', style: ts(9)),
                pw.Text('Дата: ${_dateCtrl.text}', style: ts(9)),
              ],
            ),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (_) async => pdf.save(),
        name: 'Ведомость_дефектов_${_objectCtrl.text.isNotEmpty ? _objectCtrl.text : "объект"}.pdf',
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка создания PDF: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  pw.Widget _pdfLine(String label, String value, pw.TextStyle labelStyle, pw.TextStyle valueStyle) =>
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 2),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(width: 100, child: pw.Text(label, style: labelStyle)),
            pw.Expanded(child: pw.Text(value, style: valueStyle)),
          ],
        ),
      );

  // ── Вспомогательные ───────────────────────────────────────────────────────

  Widget _sectionTitle(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(t,
            style: const TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0)),
      );

  Widget _sectionTitleInline(String t) => Text(t,
      style: const TextStyle(
          color: Colors.white70,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.0));

  Widget _row2(Widget a, Widget b) => Row(children: [
        Expanded(child: a),
        const SizedBox(width: 8),
        Expanded(child: b),
      ]);

  Widget _editField(TextEditingController ctrl, String label) => TextField(
        controller: ctrl,
        style: const TextStyle(color: Colors.white, fontSize: 13),
        decoration: _inputDecor(label),
      );

  InputDecoration _inputDecor(String label) => InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 12),
        isDense: true,
        filled: true,
        fillColor: const Color(0xFF0f172a),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: AppColors.darkPrimary)),
      );
}
