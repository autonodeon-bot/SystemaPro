import 'package:flutter/material.dart';
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

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSectionHeader('4. Проверки'),
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
      ],
    );
  }
}
