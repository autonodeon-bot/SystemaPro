import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../models/equipment.dart';
import '../models/questionnaire.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';

class QuestionnaireScreen extends StatefulWidget {
  final Equipment equipment;
  final Questionnaire? existingQuestionnaire;
  /// Задание (если опросник открыт из контекста обследования по наряду).
  final String? assignmentId;

  const QuestionnaireScreen({
    super.key,
    required this.equipment,
    this.existingQuestionnaire,
    this.assignmentId,
  });

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final _scrollController = ScrollController();
  final _apiService = ApiService();
  final _syncService = SyncService();
  bool _isSubmitting = false;
  
  late Questionnaire _questionnaire;
  List<NDTMethod> _ndtMethods = [];
  String? _questionnaireId;

  @override
  void initState() {
    super.initState();
    _questionnaire = widget.existingQuestionnaire ?? Questionnaire();
    _questionnaire.equipmentId = widget.equipment.id;
    _questionnaire.equipmentName = widget.equipment.name;
    _questionnaireId = _questionnaire.id;
    if (_questionnaireId != null && _questionnaireId!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadNDTMethods();
      });
    }
  }

  Future<void> _loadNDTMethods() async {
    final qid = _questionnaireId;
    if (qid == null || qid.isEmpty) return;

    if (_syncService.isPendingQuestionnaireLocalId(qid)) {
      final pending = await _syncService.getPendingQuestionnaires();
      Map<String, dynamic>? item;
      for (final e in pending) {
        if (e['id']?.toString() == qid) {
          item = e;
          break;
        }
      }
      final raw = item?['pending_ndt_methods'];
      if (raw is! List) return;
      final local = <NDTMethod>[];
      for (final m in raw) {
        if (m is! Map) continue;
        final map = Map<String, dynamic>.from(m);
        local.add(NDTMethod.fromJson({
          'method_code': map['method_code'],
          'method_name': map['method_name'],
          'is_performed': map['is_performed'] == true,
          'standard': map['standard'],
          'equipment': map['equipment'],
          'inspector_name': map['inspector_name'],
          'inspector_level': map['inspector_level'],
          'results': map['results'],
          'defects': map['defects'],
          'conclusion': map['conclusion'],
          'performed_date': map['performed_date'],
          'photos': (map['offline_photo_paths'] as List?)
                  ?.map((e) =>
                      e is Map ? (e['path']?.toString() ?? '') : '')
                  .where((p) => p.isNotEmpty)
                  .toList() ??
              <String>[],
        }));
      }
      if (mounted) setState(() => _ndtMethods = local);
      return;
    }

    try {
      final methods = await _apiService.getNDTMethods(qid);
      if (mounted) {
        setState(() {
          _ndtMethods = methods.map((m) => NDTMethod.fromJson(m)).toList();
        });
      }
    } catch (e) {
      print('Ошибка загрузки методов НК: $e');
    }
  }

  Future<void> _addNDTMethod() async {
    if (_questionnaireId == null || _questionnaireId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала сохраните опросный лист'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final result = await context.push<bool>('/add-ndt-method', extra: {
      'questionnaireId': _questionnaireId!,
    });

    if (result == true) {
      await _loadNDTMethods();
    }
  }

  Future<void> _submitForm() async {
    if (_formKey.currentState?.saveAndValidate() ?? false) {
      setState(() {
        _isSubmitting = true;
      });

      try {
        _formKey.currentState?.save();
        final invRaw = _formKey.currentState?.fields['inspection_date']?.value;
        if (invRaw is DateTime) {
          _questionnaire.inspectionDate = invRaw.toIso8601String();
        }

        final datePerf = _questionnaire.inspectionDate;
        final payload = _questionnaire.toJson();
        final online = await _apiService.checkConnection();

        if (online) {
          final hasToken = await _apiService.ensureValidToken();
          if (!hasToken) {
            throw Exception(
              'Сессия истекла. Войдите снова или синхронизируйте на экране «Синхронизация».',
            );
          }
          final result = await _apiService.saveQuestionnaire(
            equipmentId: widget.equipment.id,
            data: payload,
            assignmentId: widget.assignmentId,
            questionnaireId: _questionnaireId,
            status: 'DRAFT',
            datePerformed: datePerf,
          );
          final newId = result['id']?.toString();
          if (newId != null && newId.isNotEmpty) {
            setState(() {
              _questionnaire.id = newId;
              _questionnaireId = newId;
            });
            await _loadNDTMethods();
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Опросный лист сохранён на сервере'),
                backgroundColor: Colors.green,
              ),
            );
          }
        } else {
          final localId = await _syncService.saveQuestionnaireOffline(
            equipmentId: widget.equipment.id,
            data: payload,
            assignmentId: widget.assignmentId,
            questionnaireId: _questionnaireId,
            status: 'DRAFT',
            datePerformed: datePerf,
          );
          setState(() {
            _questionnaireId = localId;
          });
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Нет сети: опросный лист в очереди. Отправьте на экране «Синхронизация».',
                ),
                backgroundColor: Colors.orange,
                duration: Duration(seconds: 5),
              ),
            );
          }
        }
      } catch (e) {
        final msg = e.toString();
        final isNetwork = msg.contains('SocketException') ||
            msg.contains('Failed host lookup') ||
            msg.contains('Нет связи') ||
            msg.contains('Connection');
        if (isNetwork) {
          try {
            final localId = await _syncService.saveQuestionnaireOffline(
              equipmentId: widget.equipment.id,
              data: _questionnaire.toJson(),
              assignmentId: widget.assignmentId,
              questionnaireId: _questionnaireId,
              status: 'DRAFT',
              datePerformed: _questionnaire.inspectionDate,
            );
            setState(() {
              _questionnaireId = localId;
            });
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text(
                    'Ошибка сети: опросный лист сохранён локально и будет отправлен при синхронизации.',
                  ),
                  backgroundColor: Colors.orange,
                  duration: Duration(seconds: 5),
                ),
              );
            }
          } catch (offlineErr) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('Ошибка сохранения: $offlineErr'),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
        } else if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Ошибка сохранения: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      } finally {
        if (mounted) {
          setState(() {
            _isSubmitting = false;
          });
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Опросный лист: ${widget.equipment.name}'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
        actions: [
          if (_isSubmitting)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: _submitForm,
              tooltip: 'Сохранить',
            ),
        ],
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: FormBuilder(
        key: _formKey,
        child: ListView(
          controller: _scrollController,
          padding: const EdgeInsets.all(16),
          children: [
            _buildSectionHeader('Основная информация'),
            FormBuilderTextField(
              name: 'equipment_inventory_number',
              decoration: const InputDecoration(
                labelText: 'Инвентарный номер',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              initialValue: _questionnaire.equipmentInventoryNumber,
              onChanged: (value) {
                _questionnaire.equipmentInventoryNumber = value;
              },
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FormBuilderDateTimePicker(
              name: 'inspection_date',
              decoration: const InputDecoration(
                labelText: 'Дата обследования',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              initialValue: _questionnaire.inspectionDate != null
                  ? DateTime.tryParse(_questionnaire.inspectionDate!)
                  : null,
              inputType: InputType.date,
              format: DateFormat('yyyy-MM-dd'),
              onChanged: (value) {
                _questionnaire.inspectionDate = value?.toIso8601String();
              },
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'inspector_name',
              decoration: const InputDecoration(
                labelText: 'ФИО инженера',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              initialValue: _questionnaire.inspectorName,
              onChanged: (value) {
                _questionnaire.inspectorName = value;
              },
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 16),
            FormBuilderTextField(
              name: 'inspector_position',
              decoration: const InputDecoration(
                labelText: 'Должность инженера',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
                enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24),
                ),
                focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.blue),
                ),
              ),
              initialValue: _questionnaire.inspectorPosition,
              onChanged: (value) {
                _questionnaire.inspectorPosition = value;
              },
              style: const TextStyle(color: Colors.white),
            ),
            const SizedBox(height: 24),
            _buildSectionHeader('Методы неразрушающего контроля'),
            if (_ndtMethods.isNotEmpty)
              ..._ndtMethods.map((method) => _buildNDTMethodCard(method)),
            ElevatedButton.icon(
              onPressed: _addNDTMethod,
              icon: const Icon(Icons.add),
              label: const Text('Добавить метод НК'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _isSubmitting ? null : _submitForm,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                padding: const EdgeInsets.symmetric(vertical: 16),
                disabledBackgroundColor: Colors.grey,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text(
                      'Сохранить опросный лист',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16, top: 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildNDTMethodCard(NDTMethod method) {
    return Card(
      color: const Color(0xFF1e293b),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${method.methodCode} - ${method.methodName}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                if (method.isPerformed)
                  const Icon(Icons.check_circle, color: Colors.green, size: 20),
              ],
            ),
            if (method.standard != null) ...[
              const SizedBox(height: 8),
              Text(
                'Нормативный документ: ${method.standard}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
            if (method.inspectorName != null) ...[
              const SizedBox(height: 4),
              Text(
                'Инженер: ${method.inspectorName}${method.inspectorLevel != null ? " (${method.inspectorLevel})" : ""}',
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
            if (method.results != null) ...[
              const SizedBox(height: 8),
              Text(
                'Результаты: ${method.results}',
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
