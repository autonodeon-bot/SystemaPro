import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import '../data/checklist_constants.dart';
import '../services/api_service.dart';
import '../services/sync_service.dart';

class OpoSurveyScreen extends StatefulWidget {
  final String opoId;
  final String opoName;

  const OpoSurveyScreen({
    super.key,
    required this.opoId,
    required this.opoName,
  });

  @override
  State<OpoSurveyScreen> createState() => _OpoSurveyScreenState();
}

class _OpoSurveyScreenState extends State<OpoSurveyScreen> {
  final _formKey = GlobalKey<FormBuilderState>();
  final ApiService _api = ApiService();
  final SyncService _sync = SyncService();
  bool _loading = true;
  bool _saving = false;

  Map<String, dynamic> _initial = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final resp = await _api.getOpoSurvey(widget.opoId);
      final data = (resp['survey_data'] is Map)
          ? Map<String, dynamic>.from(resp['survey_data'] as Map)
          : <String, dynamic>{};

      final docs = (data['documents'] is Map)
          ? Map<String, dynamic>.from(data['documents'] as Map)
          : <String, dynamic>{};

      final initialDocs = <String, bool>{};
      for (final d in ChecklistConstants.documents.where((x) {
        final n = int.tryParse(x['number'] ?? '0') ?? 0;
        return n >= 1 && n <= 9;
      })) {
        final num = d['number']!;
        initialDocs[num] = (docs[num] == true);
      }

      setState(() {
        _initial = {
          'organization': data['organization']?.toString(),
          'executors': data['executors']?.toString(),
          'documents': initialDocs,
        };
      });
    } catch (_) {
      // Если сервер недоступен/нет данных — начнем с пустого
      final initialDocs = <String, bool>{};
      for (final d in ChecklistConstants.documents.where((x) {
        final n = int.tryParse(x['number'] ?? '0') ?? 0;
        return n >= 1 && n <= 9;
      })) {
        initialDocs[d['number']!] = false;
      }
      setState(() {
        _initial = {
          'organization': null,
          'executors': null,
          'documents': initialDocs,
        };
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Map<String, dynamic> _collectSurveyData() {
    final v = _formKey.currentState?.value ?? {};
    final docsRaw = v['documents'];
    final docs = <String, bool>{};
    if (docsRaw is Map) {
      for (final e in docsRaw.entries) {
        docs[e.key.toString()] = (e.value == true);
      }
    }

    return {
      'organization': v['organization']?.toString(),
      'executors': v['executors']?.toString(),
      'documents': docs,
    };
  }

  Future<void> _saveLocal() async {
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final surveyData = _collectSurveyData();
      await _sync.saveOpoSurveyOffline(opoId: widget.opoId, surveyData: surveyData);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ОПО сохранено локально. Отправка на сервер при синхронизации.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка сохранения: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAndSyncNow() async {
    if (!(_formKey.currentState?.saveAndValidate() ?? false)) return;
    setState(() => _saving = true);
    try {
      final surveyData = _collectSurveyData();
      // Сохраняем локально как источник истины
      await _sync.saveOpoSurveyOffline(opoId: widget.opoId, surveyData: surveyData);
      final res = await _sync.syncPendingInspections();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(res.message ?? res.error ?? 'Синхронизация завершена'),
          backgroundColor: res.success ? Colors.green : Colors.red,
        ),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Ошибка синхронизации: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('ОПО: ${widget.opoName}'),
        backgroundColor: const Color(0xFF0f172a),
        foregroundColor: Colors.white,
      ),
      backgroundColor: const Color(0xFF0f172a),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : FormBuilder(
              key: _formKey,
              initialValue: _initial,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  const Text(
                    'Опросный лист ОПО (пункты 1–9)',
                    style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  FormBuilderTextField(
                    name: 'organization',
                    decoration: const InputDecoration(
                      labelText: 'Организация (НГДУ, цех, месторождение)',
                      labelStyle: TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Color(0xFF1e293b),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 12),
                  FormBuilderTextField(
                    name: 'executors',
                    decoration: const InputDecoration(
                      labelText: 'Исполнители',
                      labelStyle: TextStyle(color: Colors.white70),
                      filled: true,
                      fillColor: Color(0xFF1e293b),
                      border: OutlineInputBorder(),
                    ),
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Перечень документов (1–9)',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  FormBuilderField<Map<String, bool>>(
                    name: 'documents',
                    builder: (field) {
                      final value = field.value ?? <String, bool>{};
                      return Column(
                        children: ChecklistConstants.documents.where((doc) {
                          final n = int.tryParse(doc['number'] ?? '0') ?? 0;
                          return n >= 1 && n <= 9;
                        }).map((doc) {
                          final num = doc['number']!;
                          final checked = value[num] == true;
                          return CheckboxListTile(
                            value: checked,
                            onChanged: (v) {
                              final next = Map<String, bool>.from(value);
                              next[num] = v == true;
                              field.didChange(next);
                            },
                            title: Text(
                              '${doc['number']}. ${doc['name']}',
                              style: const TextStyle(color: Colors.white),
                            ),
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: Colors.green,
                          );
                        }).toList(),
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving ? null : _saveLocal,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Сохранить локально'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _saving ? null : _saveAndSyncNow,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Сохранить и синхронизировать'),
                        ),
                      ),
                    ],
                  )
                ],
              ),
            ),
    );
  }
}

