import 'package:flutter/material.dart';
import '../../constants/report_formulation_options.dart';
import '../../data/technical_report_form_registry.dart';
import '../../models/vessel_checklist.dart';
import '../../data/checklist_constants.dart';
import 'inspection_form_fields.dart';

class InspectionChecksSection extends StatelessWidget {
  final VesselChecklist checklist;
  final VoidCallback onStateChanged;

  const InspectionChecksSection({
    super.key,
    required this.checklist,
    required this.onStateChanged,
  });

  void _setOp(String key, String? value) {
    if (value == null || value.isEmpty) {
      checklist.operationalDiagnostics.remove(key);
    } else {
      checklist.operationalDiagnostics[key] = value;
    }
    onStateChanged();
  }

  @override
  Widget build(BuildContext context) {
    final form = TechnicalReportFormRegistry.formForChecklist(checklist.reportFormId);
    final op = checklist.operationalDiagnostics;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSectionHeader(
          form.sectionHeader('checks', fallback: '4. Проверки'),
        ),
        buildYesNoField('matches_drawing', 'Соответствует ли сосуд чертежу',
            (value) {
          checklist.matchesDrawing = value == 'yes';
        }),
        buildYesNoField(
            'has_thermal_insulation', 'Наличие тепловой изоляции', (value) {
          checklist.hasThermalInsulation = value == 'yes';
        }),
        buildDropdownField(
            'anticorrosion_coating',
            'Состояние антикоррозионного покрытия',
            ChecklistConstants.states, (value) {
          checklist.anticorrosionCoatingState = value;
        }),
        buildDropdownField('support_state', 'Состояние опор сосуда',
            ChecklistConstants.states, (value) {
          checklist.supportState = value;
          _setOp('supports', value);
        }),
        buildDropdownField('fasteners_state',
            'Состояние крепежных элементов', ChecklistConstants.states,
            (value) {
          checklist.fastenersState = value;
        }),
        buildYesNoField('has_flange_misalignment',
            'Перекосы фланцевых соединений', (value) {
          checklist.hasFlangeMisalignment = value == 'yes';
        }),
        buildYesNoField('has_nozzle_misalignment',
            'Непрямолинейность патрубков', (value) {
          checklist.hasNozzleMisalignment = value == 'yes';
        }),
        buildYesNoField('has_vessel_repairs',
            'Имеются ли места ремонта сосуда', (value) {
          checklist.hasVesselRepairs = value == 'yes';
        }),
        buildYesNoField(
            'has_tpa_repairs', 'Имеются ли места ремонта ТПА', (value) {
          checklist.hasTpaRepairs = value == 'yes';
        }),
        buildInspectionTextField(
            'internal_devices_state', 'Состояние внутренних устройств',
            (value) {
          checklist.internalDevicesState = value;
        }),
        buildSectionHeader('Оперативная (функциональная) диагностика'),
        buildDropdownField(
          'op_params_ok',
          'Значения основных параметров эксплуатации',
          ReportFormulationOptions.operationalEval,
          (v) => _setOp('params_ok', v),
          initialValue: op['params_ok'] ?? 'Соответствуют',
        ),
        buildDropdownField(
          'op_vibration',
          'Повышенная вибрация сосуда',
          ReportFormulationOptions.operationalEval,
          (v) => _setOp('vibration', v),
          initialValue: op['vibration'] ?? 'Не выявлена',
        ),
        buildDropdownField(
          'op_foundation',
          'Деформации оснований / фундаментов',
          ReportFormulationOptions.operationalEval,
          (v) => _setOp('foundation', v),
          initialValue: op['foundation'] ?? 'Не выявлена',
        ),
        buildDropdownField(
          'op_kip',
          'Состояние КИП / СА / ПАЗ',
          ReportFormulationOptions.operationalEval,
          (v) => _setOp('kip', v),
          initialValue: op['kip'] ?? 'Работоспособное',
        ),
        buildDropdownField(
          'op_conclusion',
          'Заключение по оперативной диагностике',
          ReportFormulationOptions.operationalConclusion,
          (v) {
            checklist.operationalConclusion = v;
            onStateChanged();
          },
          initialValue: checklist.operationalConclusion ?? 'соответствует',
        ),
      ],
    );
  }
}
