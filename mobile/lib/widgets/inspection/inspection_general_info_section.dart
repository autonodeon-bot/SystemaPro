import 'package:flutter/material.dart';
import 'package:flutter_form_builder/flutter_form_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../data/technical_report_form_registry.dart';
import '../../models/vessel_checklist.dart';
import '../../services/api_service.dart';
import '../../services/auth_service.dart';
import 'inspection_form_fields.dart';

class InspectionGeneralInfoSection extends StatelessWidget {
  final VesselChecklist checklist;
  final List<String> selectedEquipmentIds;
  final List<Map<String, String>> manualVerificationEquipment;
  final List<Map<String, dynamic>> engineers;
  final bool loadingEngineers;
  final bool showAllEngineersList;
  final Map<String, Map<String, dynamic>> selectedEngineerByMethod;
  final List<Map<String, dynamic>> opos;
  final bool loadingOpos;
  final String? selectedOpoId;
  final String? equipmentOpoId;
  final List<String> organizationOptions;
  final List<String> selectedVerificationLabels;
  final VoidCallback onStateChanged;
  final void Function(List<String>) onEquipmentIdsChanged;
  final void Function(List<Map<String, String>>) onManualEquipmentChanged;
  final void Function(bool) onShowAllEngineersChanged;
  final void Function(String, Map<String, dynamic>) onEngineerSelected;
  final void Function(String?) onOpoChanged;

  const InspectionGeneralInfoSection({
    super.key,
    required this.checklist,
    required this.selectedEquipmentIds,
    required this.manualVerificationEquipment,
    required this.engineers,
    required this.loadingEngineers,
    required this.showAllEngineersList,
    required this.selectedEngineerByMethod,
    required this.opos,
    required this.loadingOpos,
    required this.selectedOpoId,
    required this.equipmentOpoId,
    required this.organizationOptions,
    required this.selectedVerificationLabels,
    required this.onStateChanged,
    required this.onEquipmentIdsChanged,
    required this.onManualEquipmentChanged,
    required this.onShowAllEngineersChanged,
    required this.onEngineerSelected,
    required this.onOpoChanged,
  });

  @override
  Widget build(BuildContext context) {
    final form = TechnicalReportFormRegistry.formForChecklist(checklist.reportFormId);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSectionHeader(form.sectionHeader('general', fallback: '1. Основная информация')),
        _buildVerificationEquipmentButton(context),
        _buildSelectedVerificationChips(),
        _buildManualEquipmentSection(context),
        if (selectedEquipmentIds.isEmpty && manualVerificationEquipment.isEmpty)
          _buildVerificationWarning(),
        buildDateField('inspection_date', 'Дата обследования', (date) {
          checklist.inspectionDate = date?.toIso8601String();
        }),
        _buildExecutorsField(context),
        _buildOrganizationField(context),
        _buildCustomerContractorSection(context),
        if (equipmentOpoId == null || equipmentOpoId!.isEmpty)
          _buildOpoSelectionField(),
        const SizedBox(height: 16),
        _buildEngineerSelectionSection(),
      ],
    );
  }

  Widget _buildCustomerContractorSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        const Text(
          'Сведения о заказчике / организации ТД',
          style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        const Text(
          'Подтягиваются из веб-настроек отчёта; при необходимости уточните ниже.',
          style: TextStyle(color: Colors.white38, fontSize: 12),
        ),
        const SizedBox(height: 8),
        FormBuilderTextField(
          name: 'customer_legal_name',
          initialValue: checklist.customerInfo['legal_name'] ?? '',
          decoration: const InputDecoration(
            labelText: 'Заказчик (юр. наименование)',
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
          style: const TextStyle(color: Colors.white),
          onChanged: (v) {
            checklist.customerInfo['legal_name'] = v ?? '';
            onStateChanged();
          },
        ),
        const SizedBox(height: 8),
        FormBuilderTextField(
          name: 'customer_address',
          initialValue: checklist.customerInfo['address'] ?? '',
          decoration: const InputDecoration(
            labelText: 'Адрес заказчика',
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
          style: const TextStyle(color: Colors.white),
          onChanged: (v) {
            checklist.customerInfo['address'] = v ?? '';
            onStateChanged();
          },
        ),
        const SizedBox(height: 8),
        FormBuilderTextField(
          name: 'contractor_name',
          initialValue: checklist.contractorInfo['name'] ?? checklist.contractorInfo['legal_name'] ?? '',
          decoration: const InputDecoration(
            labelText: 'Организация, проводившая ТД',
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
          style: const TextStyle(color: Colors.white),
          onChanged: (v) {
            checklist.contractorInfo['name'] = v ?? '';
            checklist.contractorInfo['legal_name'] = v ?? '';
            onStateChanged();
          },
        ),
        const SizedBox(height: 8),
        FormBuilderTextField(
          name: 'contractor_address',
          initialValue: checklist.contractorInfo['address'] ?? '',
          decoration: const InputDecoration(
            labelText: 'Адрес организации ТД',
            labelStyle: TextStyle(color: Colors.white70),
            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
          ),
          style: const TextStyle(color: Colors.white),
          onChanged: (v) {
            checklist.contractorInfo['address'] = v ?? '';
            onStateChanged();
          },
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _loadReportOrgSettings(context),
            icon: const Icon(Icons.cloud_download, size: 18),
            label: const Text('Загрузить из настроек отчёта'),
          ),
        ),
      ],
    );
  }

  Future<void> _loadReportOrgSettings(BuildContext context) async {
    try {
      final auth = await AuthService().getToken();
      final uri = Uri.parse('${ApiService.baseUrl}/api/report-org-settings');
      final response = await http.get(
        uri,
        headers: {
          if (auth != null && auth.isNotEmpty) 'Authorization': 'Bearer $auth',
          'Accept': 'application/json',
        },
      ).timeout(ApiService.requestTimeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('HTTP ${response.statusCode}');
      }
      final data = jsonDecode(utf8.decode(response.bodyBytes));
      if (data is! Map) return;
      final customer = data['customer'];
      final contractor = data['contractor'];
      if (customer is Map) {
        checklist.customerInfo = {
          'legal_name': customer['legal_name']?.toString() ?? customer['name']?.toString() ?? '',
          'address': customer['address']?.toString() ?? customer['legal_address']?.toString() ?? '',
          'phone': customer['phone']?.toString() ?? '',
          'director': customer['director']?.toString() ?? customer['director_name']?.toString() ?? '',
        };
      }
      if (contractor is Map) {
        checklist.contractorInfo = {
          'name': contractor['name']?.toString() ?? contractor['legal_name']?.toString() ?? '',
          'legal_name': contractor['legal_name']?.toString() ?? contractor['name']?.toString() ?? '',
          'address': contractor['address']?.toString() ?? contractor['postal_address']?.toString() ?? '',
          'phone': contractor['phone']?.toString() ?? '',
          'director_name': contractor['director_name']?.toString() ?? '',
        };
      }
      onStateChanged();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сведения заказчика/организации загружены')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось загрузить настройки: $e')),
        );
      }
    }
  }

  Widget _buildVerificationEquipmentButton(BuildContext context) {
    final isEmpty =
        selectedEquipmentIds.isEmpty && manualVerificationEquipment.isEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: ElevatedButton.icon(
        onPressed: () async {
          final selected = await context.push<List<String>>('/verification-equipment', extra: {
            'preselectedIds': selectedEquipmentIds,
          });
          if (selected != null) {
            onEquipmentIdsChanged(selected);
          }
        },
        icon: Icon(
          isEmpty ? Icons.warning : Icons.check_circle,
          color: isEmpty ? Colors.orange : Colors.green,
        ),
        label: Text(
          isEmpty
              ? 'Выбрать оборудование для поверок *'
              : 'Оборудование для поверок: ${selectedEquipmentIds.length + manualVerificationEquipment.length}',
          style: TextStyle(
            color: isEmpty ? Colors.orange : Colors.green,
            fontWeight: FontWeight.bold,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isEmpty
              ? Colors.orange.withOpacity(0.2)
              : Colors.green.withOpacity(0.2),
          padding: const EdgeInsets.all(16),
          side: BorderSide(
            color: isEmpty ? Colors.orange : Colors.green,
            width: 2,
          ),
        ),
      ),
    );
  }

  Widget _buildSelectedVerificationChips() {
    if (selectedVerificationLabels.isEmpty &&
        manualVerificationEquipment.isEmpty) {
      return const SizedBox.shrink();
    }
    final labels = <String>[
      ...selectedVerificationLabels,
      ...manualVerificationEquipment.map((e) => e['name'] ?? 'Прибор'),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: labels
            .map((name) => Chip(
                  label: Text(name, style: const TextStyle(fontSize: 12)),
                  backgroundColor: Colors.green.withOpacity(0.15),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildExecutorsField(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Исполнители',
              style: TextStyle(color: Colors.white70, fontSize: 13)),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            onPressed: engineers.isEmpty
                ? null
                : () => _showExecutorsPicker(context),
            icon: const Icon(Icons.people_outline, size: 18),
            label: Text(
              (checklist.executors ?? '').trim().isEmpty
                  ? 'Выбрать из справочника'
                  : checklist.executors!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 44),
            ),
          ),
          const SizedBox(height: 6),
          buildInspectionTextField('executors', 'Или введите вручную', (value) {
            checklist.executors = value;
          }, initialValue: checklist.executors),
        ],
      ),
    );
  }

  Widget _buildOrganizationField(BuildContext context) {
    if (organizationOptions.isEmpty) {
      return buildInspectionTextField(
        'organization',
        'Организация (НГДУ, цех, месторождение)',
        (value) {
          checklist.organization = value;
        },
        initialValue: checklist.organization,
      );
    }
    final current = checklist.organization?.trim() ?? '';
    final inList = organizationOptions.contains(current);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FormBuilderDropdown<String>(
            name: 'organization_select',
            initialValue: inList ? current : null,
            decoration: const InputDecoration(
              labelText: 'Организация (из справочника)',
              labelStyle: TextStyle(color: Colors.white70),
            ),
            dropdownColor: kInspectionDarkBg,
            style: const TextStyle(color: Colors.white),
            items: [
              ...organizationOptions.map(
                (o) => DropdownMenuItem(value: o, child: Text(o)),
              ),
            ],
            onChanged: (value) {
              if (value != null) {
                checklist.organization = value;
                onStateChanged();
              }
            },
          ),
          const SizedBox(height: 8),
          buildInspectionTextField(
            'organization_custom',
            'Или укажите вручную',
            (value) {
              checklist.organization = value;
            },
            initialValue: inList ? '' : current,
          ),
        ],
      ),
    );
  }

  Future<void> _showExecutorsPicker(BuildContext context) async {
    final selected = <String>{};
    final current = (checklist.executors ?? '')
        .split(RegExp(r'[,;]'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toSet();
    for (final eng in engineers) {
      final name = (eng['full_name'] ?? eng['name'] ?? '').toString().trim();
      if (name.isNotEmpty && current.contains(name)) {
        selected.add(eng['id']?.toString() ?? name);
      }
    }

    final result = await showDialog<Set<String>>(
      context: context,
      builder: (ctx) {
        final temp = Set<String>.from(selected);
        return StatefulBuilder(
          builder: (ctx, setDlg) => AlertDialog(
            backgroundColor: kInspectionDarkBg,
            title: const Text('Исполнители',
                style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: engineers.map((eng) {
                  final id = eng['id']?.toString() ?? '';
                  final name =
                      (eng['full_name'] ?? eng['name'] ?? id).toString();
                  final key = id.isNotEmpty ? id : name;
                  return CheckboxListTile(
                    value: temp.contains(key),
                    title: Text(name,
                        style: const TextStyle(color: Colors.white)),
                    subtitle: eng['position'] != null
                        ? Text(eng['position'].toString(),
                            style: const TextStyle(color: Colors.white54))
                        : null,
                    onChanged: (v) {
                      setDlg(() {
                        if (v == true) {
                          temp.add(key);
                        } else {
                          temp.remove(key);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Отмена'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, temp),
                child: const Text('Готово'),
              ),
            ],
          ),
        );
      },
    );

    if (result == null) return;
    final names = <String>[];
    for (final key in result) {
      Map<String, dynamic>? found;
      for (final eng in engineers) {
        if (eng['id']?.toString() == key) {
          found = eng;
          break;
        }
      }
      if (found != null) {
        names.add((found['full_name'] ?? found['name'] ?? key).toString());
      } else {
        names.add(key);
      }
    }
    checklist.executors = names.join(', ');
    // Сразу пишем в FormBuilder, иначе sync при смене страницы затрёт выбор пустым полем
    FormBuilder.of(context)?.fields['executors']?.didChange(names.join(', '));
    onStateChanged();
  }

  Widget _buildVerificationWarning() {
    return Container(
      padding: const EdgeInsets.all(12),
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.red),
      ),
      child: const Row(
        children: [
          Icon(Icons.warning, color: Colors.red),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Внимание! Необходимо выбрать поверенное оборудование или добавить прибор вручную.',
              style: TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  // --- Ручной ввод приборов ---

  Widget _buildManualEquipmentSection(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kInspectionDarkBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Ручной ввод приборов и поверок',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              TextButton.icon(
                onPressed: () => _showManualEquipmentDialog(context),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Добавить'),
              ),
            ],
          ),
          if (manualVerificationEquipment.isEmpty)
            const Text(
              'Если прибора нет в справочнике, добавьте вручную.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            )
          else
            ...manualVerificationEquipment.asMap().entries.map((entry) {
              final i = entry.key;
              final item = entry.value;
              final subtitle = [
                if ((item['serial_number'] ?? '').isNotEmpty)
                  'Зав. № ${item['serial_number']}',
                if ((item['verification_certificate_number'] ?? '').isNotEmpty)
                  'Поверка № ${item['verification_certificate_number']}',
                if ((item['next_verification_date'] ?? '').isNotEmpty)
                  'до ${item['next_verification_date']}',
              ].join(' | ');
              return ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  item['name'] ?? 'Прибор',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: subtitle.isNotEmpty
                    ? Text(subtitle,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 12))
                    : null,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () => _showManualEquipmentDialog(context,
                          existing: item, index: i),
                      icon: const Icon(Icons.edit,
                          color: Colors.white70, size: 18),
                    ),
                    IconButton(
                      onPressed: () {
                        final updated =
                            List<Map<String, String>>.from(manualVerificationEquipment);
                        updated.removeAt(i);
                        onManualEquipmentChanged(updated);
                      },
                      icon: const Icon(Icons.delete,
                          color: Colors.redAccent, size: 18),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _showManualEquipmentDialog(BuildContext context,
      {Map<String, String>? existing, int? index}) async {
    final nameCtrl = TextEditingController(text: existing?['name'] ?? '');
    final serialCtrl =
        TextEditingController(text: existing?['serial_number'] ?? '');
    final certCtrl = TextEditingController(
        text: existing?['verification_certificate_number'] ?? '');
    final untilCtrl = TextEditingController(
        text: existing?['next_verification_date'] ?? '');

    final saved = await showDialog<Map<String, String>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
            index == null ? 'Добавить прибор вручную' : 'Редактировать прибор'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration:
                    const InputDecoration(labelText: 'Наименование прибора *'),
              ),
              TextField(
                controller: serialCtrl,
                decoration:
                    const InputDecoration(labelText: 'Заводской номер'),
              ),
              TextField(
                controller: certCtrl,
                decoration: const InputDecoration(
                    labelText: '№ свидетельства / поверки'),
              ),
              TextField(
                controller: untilCtrl,
                decoration: const InputDecoration(
                    labelText: 'Действительно до (дд.мм.гггг)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Отмена')),
          ElevatedButton(
            onPressed: () {
              final name = nameCtrl.text.trim();
              if (name.isEmpty) return;
              Navigator.pop(ctx, {
                'name': name,
                'serial_number': serialCtrl.text.trim(),
                'verification_certificate_number': certCtrl.text.trim(),
                'next_verification_date': untilCtrl.text.trim(),
              });
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (saved == null) return;
    final updated =
        List<Map<String, String>>.from(manualVerificationEquipment);
    if (index != null &&
        index >= 0 &&
        index < manualVerificationEquipment.length) {
      updated[index] = saved;
    } else {
      updated.add(saved);
    }
    onManualEquipmentChanged(updated);
  }

  // --- Выбор ОПО ---

  Widget _buildOpoSelectionField() {
    if (loadingOpos) {
      return Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(16),
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    if (opos.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      child: FormBuilderDropdown<String>(
        name: 'opo_id',
        decoration: InputDecoration(
          labelText: 'ОПО (Опасный производственный объект)',
          labelStyle: const TextStyle(color: Colors.white70),
          filled: true,
          fillColor: kInspectionDarkBg,
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.white24),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.blue),
          ),
        ),
        initialValue: selectedOpoId,
        items: opos.map((opo) {
          final id = opo['id'] as String? ?? '';
          final name = opo['name'] as String? ?? 'Без названия';
          final code = opo['code'] as String?;
          final displayName = code != null ? '$name ($code)' : name;
          return DropdownMenuItem<String>(
            value: id,
            child: Text(displayName,
                style: const TextStyle(color: Colors.white)),
          );
        }).toList(),
        onChanged: onOpoChanged,
        style: const TextStyle(color: Colors.white),
        dropdownColor: kInspectionDarkBg,
      ),
    );
  }

  // --- Инженеры ---

  Widget _buildEngineerSelectionSection() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kInspectionDarkBg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Инженеры по видам обследований',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          if (loadingEngineers)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (engineers.isEmpty)
            const Text(
              'Список инженеров не загружен. Подключитесь к интернету и выполните синхронизацию.',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            )
          else ...[
            CheckboxListTile(
              value: showAllEngineersList,
              onChanged: (v) => onShowAllEngineersChanged(v ?? false),
              title: const Text(
                'Показать весь список специалистов (выбрать любого, даже без удостоверения по виду)',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              activeColor: Colors.blue,
              controlAffinity: ListTileControlAffinity.leading,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 12),
            _buildEngineerRow('ВИК', 'VIK'),
            const SizedBox(height: 10),
            _buildEngineerRow('УЗК', 'UZK'),
            const SizedBox(height: 10),
            _buildEngineerRow('УЗТ', 'UZT'),
            const SizedBox(height: 10),
            _buildEngineerRow('ПВК/МК', 'PVK'),
          ],
        ],
      ),
    );
  }

  Widget _buildEngineerRow(String label, String methodKey) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 72,
          child: Padding(
            padding: const EdgeInsets.only(top: 14),
            child: Text(
              label,
              style: const TextStyle(
                color: Colors.white70,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(child: _buildEngineerDropdown(label, methodKey)),
      ],
    );
  }

  Widget _buildEngineerDropdown(String label, String methodKey) {
    final filteredEngineers = engineers.where((engineer) {
      var qualifications = engineer['qualifications'];
      if (qualifications == null) return false;
      if (qualifications is String) {
        try {
          qualifications = json.decode(qualifications);
        } catch (_) {
          return false;
        }
      }
      if (qualifications is List) {
        for (final qual in qualifications) {
          if (_qualificationMatchesMethod(qual, methodKey)) return true;
        }
      }
      return false;
    }).toList();

    final engineersToShow =
        showAllEngineersList ? engineers : filteredEngineers;
    final selected = selectedEngineerByMethod[methodKey];
    final selectedId = selected?['id']?.toString();

    if (engineersToShow.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.2),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.orange),
          ),
          child: Text(
            '$label: нет специалистов с соответствующим удостоверением. Включите «Показать весь список» выше.',
            style: const TextStyle(color: Colors.orange, fontSize: 12),
          ),
        ),
      );
    }

    // value по id — иначе DropdownButton «теряет» выбор при пересборке списка Map
    final ids = engineersToShow
        .map((e) => e['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toList();
    final valueId =
        (selectedId != null && ids.contains(selectedId)) ? selectedId : null;

    return InputDecorator(
      decoration: InputDecoration(
        labelText: showAllEngineersList ? 'весь список' : null,
        labelStyle: const TextStyle(color: Colors.white54, fontSize: 11),
        filled: true,
        fillColor: kInspectionScaffoldBg,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.white24),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: valueId,
          isExpanded: true,
          hint: const Text(
            'Выберите специалиста',
            style: TextStyle(color: Colors.white54, fontSize: 14),
          ),
          dropdownColor: kInspectionDarkBg,
          selectedItemBuilder: (context) {
            return engineersToShow.map((e) {
              final name = (e['full_name'] ?? '').toString();
              return Text(
                name,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              );
            }).toList();
          },
          items: engineersToShow.map((e) {
            final id = e['id']?.toString() ?? '';
            final name = (e['full_name'] ?? '').toString();
            final position = (e['position'] ?? '').toString();
            final qualifications = e['qualifications'];
            String certInfo = '';
            final cert =
                _extractCertificateForMethod(qualifications, methodKey);
            final certNum = cert['certificate_number'] ?? '';
            final validUntil = cert['valid_until'] ?? '';
            if (certNum.isNotEmpty) {
              certInfo = 'Удост. $certNum';
              if (validUntil.isNotEmpty) {
                certInfo += ', до $validUntil';
              }
            }
            return DropdownMenuItem<String>(
              value: id,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      position.isNotEmpty ? '$name — $position' : name,
                      style:
                          const TextStyle(color: Colors.white, fontSize: 14),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (certInfo.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        certInfo,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
          onChanged: (id) {
            if (id == null || id.isEmpty) return;
            final match = engineersToShow.firstWhere(
              (e) => e['id']?.toString() == id,
              orElse: () => <String, dynamic>{},
            );
            if (match.isEmpty) return;
            onEngineerSelected(methodKey, match);
          },
        ),
      ),
    );
  }

  // --- Утилиты инженерных квалификаций ---

  static Set<String> methodAliases(String methodKey) {
    final normalized = methodKey.trim().toUpperCase();
    switch (normalized) {
      case 'VIK':
        return {'VIK', 'ВИК', 'VT', 'VISUAL'};
      case 'UZK':
        return {'UZK', 'УЗК', 'UT', 'UTT'};
      case 'UZT':
        return {'UZT', 'УЗТ', 'UTM', 'THICKNESS'};
      case 'PVK':
        return {'PVK', 'ПВК', 'MK', 'МК', 'PT', 'MT'};
      default:
        return {normalized};
    }
  }

  static bool _qualificationMatchesMethod(
      dynamic qualification, String methodKey) {
    if (qualification is! Map) return false;
    final aliases = methodAliases(methodKey);
    final candidates = <String>{
      qualification['method']?.toString().toUpperCase() ?? '',
      qualification['ndt_method']?.toString().toUpperCase() ?? '',
      qualification['method_code']?.toString().toUpperCase() ?? '',
      qualification['certification_type']?.toString().toUpperCase() ?? '',
      qualification['certification_area']?.toString().toUpperCase() ?? '',
    };
    final areas = qualification['certification_areas'];
    if (areas is List) {
      for (final area in areas) {
        if (area != null) candidates.add(area.toString().toUpperCase());
      }
    }
    for (final c in candidates) {
      if (c.isEmpty) continue;
      if (aliases.any((a) => c.contains(a))) return true;
    }
    return false;
  }

  static Map<String, String> extractCertificateForMethod(
      dynamic qualifications, String methodKey) {
    if (qualifications is! List) return const {};
    Map? matched;
    for (final q in qualifications) {
      if (_qualificationMatchesMethod(q, methodKey)) {
        matched = q as Map;
        break;
      }
    }
    final source =
        (matched ?? (qualifications.isNotEmpty ? qualifications.first : null));
    if (source is! Map) return const {};
    final certNumber =
        source['number']?.toString().trim().isNotEmpty == true
            ? source['number'].toString().trim()
            : (source['certificate_number']?.toString().trim() ?? '');
    final validUntil =
        source['valid_until']?.toString().trim().isNotEmpty == true
            ? source['valid_until'].toString().trim()
            : (source['expiry_date']?.toString().trim() ?? '');
    return {
      'certificate_number': certNumber,
      'valid_until': validUntil,
    };
  }

  Map<String, String> _extractCertificateForMethod(
          dynamic qualifications, String methodKey) =>
      extractCertificateForMethod(qualifications, methodKey);
}
