import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:intl/intl.dart';
import '../models/equipment.dart';
import '../models/questionnaire.dart';
import '../services/api_service.dart';
import 'add_ndt_method_screen.dart';

class QuestionnaireScreen extends StatefulWidget {
  final Equipment equipment;
  final Questionnaire? existingQuestionnaire;

  const QuestionnaireScreen({
    super.key,
    required this.equipment,
    this.existingQuestionnaire,
  });

  @override
  State<QuestionnaireScreen> createState() => _QuestionnaireScreenState();
}

class _QuestionnaireScreenState extends State<QuestionnaireScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final _scrollController = ScrollController();
  final _apiService = ApiService();
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
    _questionnaireId = widget.existingQuestionnaire != null ? 'temp' : null;
  }

  Future<void> _loadNDTMethods() async {
    if (_questionnaireId != null && _questionnaireId != 'temp') {
      try {
        final methods = await _apiService.getNDTMethods(_questionnaireId!);
        setState(() {
          _ndtMethods = methods.map((m) => NDTMethod.fromJson(m)).toList();
        });
      } catch (e) {
        print('Ошибка загрузки методов НК: $e');
      }
    }
  }

  Future<void> _addNDTMethod() async {
    if (_questionnaireId == null || _questionnaireId == 'temp') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Сначала сохраните опросный лист'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => AddNDTMethodScreen(
          questionnaireId: _questionnaireId!,
        ),
      ),
    );

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
        // TODO: Реализовать отправку опросного листа на сервер
        // После сохранения получим ID и сможем добавлять методы НК
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Опросный лист успешно сохранен'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      } catch (e) {
        if (mounted) {
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
