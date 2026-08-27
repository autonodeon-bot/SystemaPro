import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../constants/report_formulation_options.dart';
import '../../data/technical_report_form_registry.dart';
import '../../data/inspection_form_profiles.dart';
import '../../models/vessel_checklist.dart';
import '../../models/compressor_checklist.dart';
import '../../services/api_service.dart';
import 'inspection_form_fields.dart';

class InspectionSurveyCardSection extends StatelessWidget {
  final VesselChecklist checklist;
  final bool isCompressor;
  final File? factoryPlatePhoto;
  final File? controlSchemeImage;
  final List<String> additionalObjectPhotos;
  final VoidCallback onStateChanged;
  final void Function(ImageSource source, bool isFactoryPlate) onPickImage;
  final VoidCallback onPickImageFromFile;
  final VoidCallback onPickBuiltInTemplate;
  final VoidCallback onPickStandardDrawing;
  final VoidCallback? onOpenSchemeConstructor;
  final void Function(ImageSource source) onPickAdditionalObjectPhoto;
  final void Function(int index) onRemoveObjectPhoto;

  const InspectionSurveyCardSection({
    super.key,
    required this.checklist,
    required this.isCompressor,
    required this.factoryPlatePhoto,
    required this.controlSchemeImage,
    required this.additionalObjectPhotos,
    required this.onStateChanged,
    required this.onPickImage,
    required this.onPickImageFromFile,
    required this.onPickBuiltInTemplate,
    required this.onPickStandardDrawing,
    this.onOpenSchemeConstructor,
    required this.onPickAdditionalObjectPhoto,
    required this.onRemoveObjectPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final form = TechnicalReportFormRegistry.formForChecklist(checklist.reportFormId);
    final formId = (checklist.reportFormId ?? 'to-1').toLowerCase();
    final profile = InspectionFormProfiles.forFormId(formId);
    final isPipeline = InspectionFormProfiles.isPipeline(profile);
    final isCrane = InspectionFormProfiles.isCrane(profile);
    final usesVesselFields =
        InspectionFormProfiles.usesPressureVesselFields(profile);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSectionHeader(
          form.sectionHeader('survey', fallback: '3. Карта обследования'),
        ),
        buildInspectionTextField(
          'vessel_name',
          isCompressor
              ? 'Наименование компрессора'
              : InspectionFormProfiles.nameFieldLabel(profile),
          (value) => checklist.vesselName = value,
          initialValue: checklist.vesselName,
        ),
        buildInspectionTextField('serial_number', 'Заводской номер',
            (value) => checklist.serialNumber = value,
            initialValue: checklist.serialNumber),
        buildInspectionTextField(
            'reg_number',
            isCrane ? 'Учетный / регистрационный номер' : 'Регистрационный номер',
            (value) => checklist.regNumber = value,
            initialValue: checklist.regNumber),
        buildInspectionTextField('inventory_number', 'Инвентарный номер',
            (value) => checklist.inventoryNumber = value,
            initialValue: checklist.inventoryNumber),
        buildInspectionTextField(
            'equipment_location',
            'Местонахождение (цех / НГДУ / трасса)',
            (value) => checklist.equipmentLocation = value,
            initialValue: checklist.equipmentLocation),
        buildInspectionTextField('manufacturer', 'Изготовитель',
            (value) => checklist.manufacturer = value,
            initialValue: checklist.manufacturer),
        buildInspectionTextField('manufacture_year', 'Год изготовления',
            (value) => checklist.manufactureYear = value,
            initialValue: checklist.manufactureYear),
        if (isPipeline) ..._buildPipelineFields(form),
        if (isCrane) ..._buildCraneFields(form),
        if (!isCompressor && !isPipeline && !isCrane && usesVesselFields)
          ..._buildVesselFields(form, context),
        if (!isCompressor &&
            !isPipeline &&
            !isCrane &&
            !usesVesselFields)
          ..._buildGenericEquipmentFields(form, profile),
        if (isCompressor) _buildCompressorFields(),
        const SizedBox(height: 16),
        _buildPhotoSection(context, 'Фото заводской таблички / объекта',
            factoryPlatePhoto, true),
        const SizedBox(height: 8),
        _buildPhotoSection(
            context,
            isPipeline
                ? 'Схема трассы / сварных соединений'
                : isCrane
                    ? 'Схема контроля металлоконструкции'
                    : 'Схема контроля объекта',
            controlSchemeImage,
            false),
        _buildAdditionalObjectPhotosSection(context),
      ],
    );
  }

  List<Widget> _buildGenericEquipmentFields(
    TechnicalReportForm form,
    InspectionProfile profile,
  ) {
    return [
      buildInspectionTextField(
        'working_medium',
        profile == InspectionProfile.electrical
            ? 'Номинальные параметры / напряжение'
            : 'Рабочая среда / назначение',
        (value) => checklist.workingMedium = value,
        initialValue: checklist.workingMedium,
      ),
      buildInspectionTextField(
        'commissioning_year',
        'Год ввода в эксплуатацию',
        (value) => checklist.commissioningYear = value,
        initialValue: checklist.commissioningYear,
      ),
      buildInspectionTextField(
        'purpose',
        profile == InspectionProfile.electrical
            ? 'Тип / марка оборудования'
            : 'Назначение / тип',
        (value) => checklist.purpose = value,
        initialValue: checklist.purpose,
      ),
      buildInspectionTextField(
        'design_pressure',
        'Основные технические параметры',
        (value) => checklist.designPressure = value,
        initialValue: checklist.designPressure,
      ),
    ];
  }

  List<Widget> _buildPipelineFields(TechnicalReportForm form) {
    String? ad(String key) {
      final m = checklist.additionalData;
      if (m == null) return null;
      final v = m[key];
      return v?.toString();
    }

    void setAd(String key, String? v) {
      checklist.additionalData ??= {};
      checklist.additionalData![key] = v;
      onStateChanged();
    }

    return [
      buildSectionHeader(
        form.sectionHeader('survey', fallback: 'Характеристика трубопровода'),
      ),
      buildInspectionTextField(
          'purpose', 'Назначение', (v) => checklist.purpose = v,
          initialValue: checklist.purpose),
      buildInspectionTextField(
        'pipeline_category',
        'Категория трубопровода',
        (v) => setAd('pipeline_category', v),
        initialValue: ad('pipeline_category'),
      ),
      buildInspectionTextField(
        'pipeline_length',
        'Протяженность участка',
        (v) => setAd('pipeline_length', v),
        initialValue: ad('pipeline_length'),
      ),
      buildInspectionTextField('diameter', 'Номинальный диаметр DN, мм',
          (value) => checklist.diameter = value,
          initialValue: checklist.diameter),
      buildInspectionTextField('working_pressure', 'Рабочее / номинальное давление',
          (value) => checklist.workingPressure = value,
          initialValue: checklist.workingPressure),
      buildInspectionTextField(
          'wall_thickness', 'Толщина стенки (номинал), мм',
          (value) => checklist.wallThickness = value,
          initialValue: checklist.wallThickness),
      buildInspectionTextField(
          'working_medium', 'Рабочая среда', (v) => checklist.workingMedium = v,
          initialValue: checklist.workingMedium),
      buildInspectionTextField(
          'working_temperature',
          'Температура рабочей среды, ℃',
          (v) => checklist.workingTemperature = v,
          initialValue: checklist.workingTemperature),
      buildInspectionTextField(
        'pipe_material',
        'Материал труб',
        (v) => setAd('pipe_material', v),
        initialValue: ad('pipe_material') ?? ad('shell_material'),
      ),
      buildInspectionTextField('commissioning_year', 'Год ввода в эксплуатацию',
          (v) => checklist.commissioningYear = v,
          initialValue: checklist.commissioningYear?.toString()),
    ];
  }

  List<Widget> _buildCraneFields(TechnicalReportForm form) {
    String? ad(String key) {
      final m = checklist.additionalData;
      if (m == null) return null;
      return m[key]?.toString();
    }

    void setAd(String key, String? v) {
      checklist.additionalData ??= {};
      checklist.additionalData![key] = v;
      onStateChanged();
    }

    return [
      buildSectionHeader(
        form.sectionHeader('survey', fallback: 'Характеристика ГПМ'),
      ),
      buildInspectionTextField(
        'crane_type',
        'Тип подъемного сооружения',
        (v) => setAd('crane_type', v),
        initialValue: ad('crane_type'),
      ),
      buildInspectionTextField(
          'purpose', 'Назначение', (v) => checklist.purpose = v,
          initialValue: checklist.purpose),
      buildInspectionTextField(
        'crane_capacity',
        'Грузоподъемность',
        (v) => setAd('crane_capacity', v),
        initialValue: ad('crane_capacity'),
      ),
      buildInspectionTextField(
        'crane_mode',
        'Режим работы (группа классификации)',
        (v) => setAd('crane_mode', v),
        initialValue: ad('crane_mode'),
      ),
      buildInspectionTextField(
        'lift_height',
        'Высота подъема',
        (v) => setAd('lift_height', v),
        initialValue: ad('lift_height'),
      ),
      buildInspectionTextField(
        'crane_span',
        'Пролет / вылет',
        (v) => setAd('crane_span', v),
        initialValue: ad('crane_span'),
      ),
      buildInspectionTextField(
        'operating_environment',
        'Окружающая среда эксплуатации',
        (v) => setAd('operating_environment', v),
        initialValue: ad('operating_environment'),
      ),
    ];
  }

  List<Widget> _buildVesselFields(TechnicalReportForm form, BuildContext context) {
    String? s(dynamic v) => v?.toString();
    return [
      buildInspectionTextField('diameter', 'Диаметр сосуда',
          (value) => checklist.diameter = value,
          initialValue: checklist.diameter),
      buildInspectionTextField('working_pressure', 'Рабочее давление',
          (value) => checklist.workingPressure = value,
          initialValue: checklist.workingPressure),
      buildInspectionTextField(
          'wall_thickness', 'Толщина стенки (обечайка / днище)',
          (value) => checklist.wallThickness = value,
          initialValue: checklist.wallThickness),
      buildSectionHeader(
        form.sectionHeader('survey', fallback: 'Краткая техническая характеристика'),
      ),
      buildInspectionTextField(
          'purpose', 'Назначение', (v) => checklist.purpose = v,
          initialValue: checklist.purpose),
      buildInspectionTextField('commissioning_year',
          'Год ввода в эксплуатацию', (v) => checklist.commissioningYear = v,
          initialValue: s(checklist.commissioningYear)),
      buildInspectionTextField('design_pressure',
          'Расчётное давление, МПа', (v) => checklist.designPressure = v,
          initialValue: s(checklist.designPressure)),
      buildInspectionTextField(
          'test_pressure',
          'Пробное давление гидравлического испытания, МПа',
          (v) => checklist.testPressure = v,
          initialValue: s(checklist.testPressure)),
      buildInspectionTextField('designation', 'Условное обозначение',
          (v) => checklist.designation = v,
          initialValue: checklist.designation),
      buildInspectionTextField(
          'working_temperature',
          'Температура рабочей среды, ℃',
          (v) => checklist.workingTemperature = v,
          initialValue: checklist.workingTemperature),
      buildInspectionTextField('design_temperature',
          'Расчётная температура стенки, ℃',
          (v) => checklist.designTemperature = v,
          initialValue: checklist.designTemperature),
      buildInspectionTextField('working_medium',
          'Наименование рабочей среды (состав)', (v) => checklist.workingMedium = v,
          initialValue: checklist.workingMedium),
      buildInspectionTextField('hazard_class',
          'Класс опасности по ГОСТ 12.1.007', (v) => checklist.hazardClass = v,
          initialValue: checklist.hazardClass),
      buildInspectionTextField('explosion_hazard',
          'Категория взрывоопасности', (v) => checklist.explosionHazard = v,
          initialValue: checklist.explosionHazard),
      buildInspectionTextField('fire_hazard',
          'Категория пожароопасности', (v) => checklist.fireHazard = v,
          initialValue: checklist.fireHazard),
      buildInspectionTextField('connection_scheme',
          'Схема подключения сосуда в установку',
          (v) => checklist.connectionScheme = v,
          initialValue: checklist.connectionScheme),
      buildInspectionTextField('climatic_version',
          'Климатическое исполнение', (v) => checklist.climaticVersion = v,
          initialValue: checklist.climaticVersion),
      buildInspectionTextField(
          'empty_mass', 'Масса порожнего сосуда, кг', (v) => checklist.emptyMass = v,
          initialValue: checklist.emptyMass),
      buildInspectionTextField('load_cycles', 'Число циклов нагружения',
          (v) => checklist.loadCycles = v,
          initialValue: checklist.loadCycles),
      buildInspectionTextField(
          'service_life', 'Расчётный срок службы, лет', (v) => checklist.serviceLife = v,
          initialValue: checklist.serviceLife),
      buildInspectionTextField(
          'vessel_group', 'Группа сосуда', (v) => checklist.vesselGroup = v,
          initialValue: checklist.vesselGroup),
      buildInspectionTextField(
          'vessel_installed', 'Сосуд установлен (дата/место)',
          (v) => checklist.vesselInstalled = v,
          initialValue: checklist.vesselInstalled),
      buildInspectionTextField(
          'supervisory_remarks', 'Наличие замечаний надзорных органов',
          (v) => checklist.supervisoryRemarks = v,
          initialValue: checklist.supervisoryRemarks),
      buildInspectionTextField(
          'accidents_info', 'Сведения об авариях, инцидентах и отказах',
          (v) => checklist.accidentsInfo = v,
          initialValue: checklist.accidentsInfo),
      buildInspectionTextField(
          'repair_info', 'Данные о ремонте и реконструкции',
          (v) => checklist.repairInfo = v,
          initialValue: checklist.repairInfo),
      buildInspectionTextField('medium_group', 'Группа рабочей среды',
          (v) => checklist.mediumGroup = v,
          initialValue: checklist.mediumGroup),
      buildInspectionTextField('corrosion_allowance',
          'Прибавка для компенсации коррозии, мм',
          (v) => checklist.corrosionAllowance = v,
          initialValue: s(checklist.corrosionAllowance)),
      buildDropdownField(
        'calculation_result',
        'Оценка работоспособности (разд. 14)',
        ReportFormulationOptions.calculationResult,
        (v) => checklist.calculationResult = v,
        initialValue: checklist.calculationResult ??
            ReportFormulationOptions.calculationResult.first,
      ),
      buildDropdownField(
        'technical_state',
        'Техническое состояние объекта (разд. 15)',
        ReportFormulationOptions.technicalState,
        (v) => checklist.technicalState = v,
        initialValue: checklist.technicalState ??
            ReportFormulationOptions.technicalState.first,
      ),
      buildDropdownField(
        'documentation_conclusion',
        'Результат анализа документации',
        ReportFormulationOptions.docAnalysis,
        (v) => checklist.documentationConclusion = v,
        initialValue: checklist.documentationConclusion ??
            ReportFormulationOptions.docAnalysis.first,
      ),
      buildInspectionTextField('tech_card_number', '№ технологической карты',
          (v) => checklist.techCardNumber = v,
          initialValue: checklist.techCardNumber),
      buildSectionHeader(
        form.sectionHeader('survey_prev', fallback: '12. Анализ результатов предыдущих обследований'),
      ),
      _buildPreviousInspectionsTable(context),
      buildMultilineField(
          'previous_inspection_result',
          'Дополнительные замечания по предыдущим обследованиям',
          (v) => checklist.previousInspectionResult = v,
          initialValue: checklist.previousInspectionResult),
    ];
  }

  Widget _buildPreviousInspectionsTable(BuildContext context) {
    if (checklist.previousInspections.isEmpty) {
      checklist.previousInspections.add(PreviousInspectionRecord());
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ...checklist.previousInspections.asMap().entries.map((entry) {
          final index = entry.key;
          final row = entry.value;
          return Card(
            color: kInspectionDarkBg,
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text('Запись ${index + 1}',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold)),
                      const Spacer(),
                      if (checklist.previousInspections.length > 1)
                        IconButton(
                          icon: const Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () {
                            checklist.previousInspections.removeAt(index);
                            onStateChanged();
                          },
                        ),
                    ],
                  ),
                  buildInspectionTextField(
                    'prev_kind_$index',
                    'Вид обследования',
                    (v) => row.kind = v,
                    initialValue: row.kind,
                  ),
                  buildInspectionTextField(
                    'prev_date_$index',
                    'Дата обследования',
                    (v) => row.date = v,
                    initialValue: row.date,
                  ),
                  buildInspectionTextField(
                    'prev_report_$index',
                    'Номер отчётной документации',
                    (v) => row.reportNumber = v,
                    initialValue: row.reportNumber,
                  ),
                  buildInspectionTextField(
                    'prev_result_$index',
                    'Результаты контроля',
                    (v) => row.result = v,
                    initialValue: row.result,
                  ),
                  buildInspectionTextField(
                    'prev_scope_$index',
                    'Объём контроля',
                    (v) => row.scope = v,
                    initialValue: row.scope,
                  ),
                  buildInspectionTextField(
                    'prev_org_$index',
                    'Организация-исполнитель',
                    (v) => row.organization = v,
                    initialValue: row.organization,
                  ),
                ],
              ),
            ),
          );
        }),
        OutlinedButton.icon(
          onPressed: () {
            checklist.previousInspections.add(PreviousInspectionRecord());
            onStateChanged();
          },
          icon: const Icon(Icons.add),
          label: const Text('Добавить запись'),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildCompressorFields() {
    final c = checklist as CompressorChecklist;
    return Column(
      children: [
        buildInspectionTextField('compressor_type', 'Тип компрессора',
            (value) => c.compressorType = value),
        buildInspectionTextField(
            'power_rating', 'Мощность', (value) => c.powerRating = value),
        buildInspectionTextField('pressure_ratio', 'Степень сжатия',
            (value) => c.pressureRatio = value),
        buildInspectionTextField('flow_rate', 'Производительность',
            (value) => c.flowRate = value),
        buildInspectionTextField('rotation_speed', 'Частота вращения',
            (value) => c.rotationSpeed = value),
        buildInspectionTextField('number_of_stages', 'Количество ступеней',
            (value) => c.numberOfStages = value),
      ],
    );
  }

  // --- Фото ---

  Widget _buildPhotoSection(
      BuildContext context, String title, File? image, bool isFactoryPlate) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: const TextStyle(color: Colors.white70, fontSize: 14)),
          const SizedBox(height: 8),
          if (image != null)
            GestureDetector(
              onTap: () {
                if (!image.existsSync()) return;
                showDialog(
                  context: context,
                  barrierColor: Colors.black87,
                  builder: (ctx) => Dialog(
                    backgroundColor: Colors.transparent,
                    insetPadding: EdgeInsets.zero,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        InteractiveViewer(
                          minScale: 0.5,
                          maxScale: 4.0,
                          child: Center(
                            child: Image.file(image, fit: BoxFit.contain),
                          ),
                        ),
                        Positioned(
                          top: MediaQuery.of(ctx).padding.top + 8,
                          right: 16,
                          child: IconButton(
                            icon: const Icon(Icons.close,
                                color: Colors.white, size: 28),
                            onPressed: () => Navigator.of(ctx).pop(),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kInspectionBorderColor),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(image, fit: BoxFit.cover),
                ),
              ),
            )
          else
            _buildEmptyPhotoPlaceholder(isFactoryPlate),
        ],
      ),
    );
  }

  Widget _buildEmptyPhotoPlaceholder(bool isFactoryPlate) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kInspectionDarkBg,
        borderRadius: BorderRadius.circular(8),
        border:
            Border.all(color: kInspectionBorderColor, style: BorderStyle.solid),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.camera_alt, color: Colors.white70, size: 48),
          const SizedBox(height: 8),
          const Text('Нет фото',
              style: TextStyle(color: Colors.white70)),
          const SizedBox(height: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                isFactoryPlate
                    ? 'Выберите способ получения фото заводской таблички:'
                    : 'Выберите способ получения схемы контроля:',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      onPickImage(ImageSource.camera, isFactoryPlate),
                  icon: const Icon(Icons.camera, color: Colors.white),
                  label: Text(
                    isFactoryPlate
                        ? 'Сфотографировать табличку'
                        : 'Сфотографировать схему',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kInspectionAccentBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () =>
                      onPickImage(ImageSource.gallery, isFactoryPlate),
                  icon: const Icon(Icons.photo_library,
                      color: Colors.white),
                  label: const Text(
                    'Выбрать из галереи',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kInspectionAccentBlue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              if (!isFactoryPlate) ...[
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onPickImageFromFile,
                    icon: const Icon(Icons.folder_open,
                        color: kInspectionAccentBlue, size: 20),
                    label: const Text('Файл',
                        style: TextStyle(
                            color: kInspectionAccentBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side:
                          const BorderSide(color: kInspectionAccentBlue),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onPickBuiltInTemplate,
                    icon: const Icon(Icons.dashboard_customize,
                        color: kInspectionAccentBlue, size: 20),
                    label: const Text('Встроенный шаблон',
                        style: TextStyle(
                            color: kInspectionAccentBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 13)),
                    style: OutlinedButton.styleFrom(
                      side:
                          const BorderSide(color: kInspectionAccentBlue),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
                if (onOpenSchemeConstructor != null) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onOpenSchemeConstructor,
                      icon: const Icon(Icons.architecture,
                          color: kInspectionAccentBlue, size: 20),
                      label: const Text('Конструктор схемы',
                          style: TextStyle(
                              color: kInspectionAccentBlue,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        side:
                            const BorderSide(color: kInspectionAccentBlue),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onPickStandardDrawing,
                    icon: const Icon(Icons.cloud_download,
                        color: kInspectionAccentBlue),
                    label: const Text('Шаблон с сервера',
                        style: TextStyle(
                            color: kInspectionAccentBlue,
                            fontWeight: FontWeight.w600,
                            fontSize: 14)),
                    style: OutlinedButton.styleFrom(
                      side:
                          const BorderSide(color: kInspectionAccentBlue),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // --- Дополнительные фото ---

  Widget _buildAdditionalObjectPhotosSection(BuildContext context) {
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
          const Text(
            'Дополнительные фото объекта',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Добавьте несколько фото состояния/дефектов объекта. Фото сохраняются и будут доступны в истории объекта.',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      onPickAdditionalObjectPhoto(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Камера'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () =>
                      onPickAdditionalObjectPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('Галерея'),
                ),
              ),
            ],
          ),
          if (additionalObjectPhotos.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children:
                  additionalObjectPhotos.asMap().entries.map((entry) {
                final idx = entry.key;
                final p = entry.value;
                final f = File(p);
                final isRemote = p.startsWith('http://') ||
                    p.startsWith('https://') ||
                    p.startsWith('/api/');
                final remoteUrl = p.startsWith('/api/')
                    ? '${ApiService.baseUrl}$p'
                    : p;
                return Stack(
                  children: [
                    GestureDetector(
                      onTap: () {
                        showDialog(
                          context: context,
                          builder: (_) => Dialog(
                            backgroundColor: Colors.black,
                            child: InteractiveViewer(
                              child: isRemote
                                  ? Image.network(
                                      remoteUrl,
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) =>
                                          const Padding(
                                        padding: EdgeInsets.all(16),
                                        child: Text(
                                          'Не удалось загрузить фото',
                                          style: TextStyle(
                                              color: Colors.white),
                                        ),
                                      ),
                                    )
                                  : f.existsSync()
                                      ? Image.file(f,
                                          fit: BoxFit.contain)
                                      : const Padding(
                                          padding: EdgeInsets.all(16),
                                          child: Text(
                                            'Файл не найден',
                                            style: TextStyle(
                                                color: Colors.white),
                                          ),
                                        ),
                            ),
                          ),
                        );
                      },
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: isRemote
                            ? Image.network(
                                remoteUrl,
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 96,
                                  height: 96,
                                  color: Colors.black26,
                                  child: const Icon(Icons.broken_image,
                                      color: Colors.white54),
                                ),
                              )
                            : f.existsSync()
                                ? Image.file(f,
                                    width: 96,
                                    height: 96,
                                    fit: BoxFit.cover)
                                : Container(
                                    width: 96,
                                    height: 96,
                                    color: Colors.black26,
                                    child: const Icon(Icons.broken_image,
                                        color: Colors.white54),
                                  ),
                      ),
                    ),
                    Positioned(
                      right: 0,
                      top: 0,
                      child: InkWell(
                        onTap: () => onRemoveObjectPhoto(idx),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black87,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(4),
                          child: const Icon(Icons.close,
                              size: 14, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}
