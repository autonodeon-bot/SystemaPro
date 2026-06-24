import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../data/technical_report_form_registry.dart';
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
    required this.onPickAdditionalObjectPhoto,
    required this.onRemoveObjectPhoto,
  });

  @override
  Widget build(BuildContext context) {
    final form = TechnicalReportFormRegistry.formForChecklist(checklist.reportFormId);
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
              : 'Наименование сосуда',
          (value) => checklist.vesselName = value,
        ),
        buildInspectionTextField('serial_number', 'Заводской номер',
            (value) => checklist.serialNumber = value),
        buildInspectionTextField('reg_number', 'Регистрационный номер',
            (value) => checklist.regNumber = value),
        buildInspectionTextField('manufacturer', 'Изготовитель',
            (value) => checklist.manufacturer = value),
        buildInspectionTextField('manufacture_year', 'Год изготовления',
            (value) => checklist.manufactureYear = value),
        if (!isCompressor) ..._buildVesselFields(form),
        if (isCompressor) _buildCompressorFields(),
        const SizedBox(height: 16),
        _buildPhotoSection(context, 'Фото заводской таблички',
            factoryPlatePhoto, true),
        _buildAdditionalObjectPhotosSection(context),
      ],
    );
  }

  List<Widget> _buildVesselFields(TechnicalReportForm form) {
    return [
      buildInspectionTextField('diameter', 'Диаметр сосуда',
          (value) => checklist.diameter = value),
      buildInspectionTextField('working_pressure', 'Рабочее давление',
          (value) => checklist.workingPressure = value),
      buildInspectionTextField(
          'wall_thickness', 'Толщина стенки (обечайка / днище)',
          (value) => checklist.wallThickness = value),
      buildSectionHeader(
        form.sectionHeader('survey', fallback: 'Краткая техническая характеристика'),
      ),
      buildInspectionTextField(
          'purpose', 'Назначение', (v) => checklist.purpose = v),
      buildInspectionTextField('commissioning_year',
          'Год ввода в эксплуатацию', (v) => checklist.commissioningYear = v),
      buildInspectionTextField('design_pressure',
          'Расчётное давление, МПа', (v) => checklist.designPressure = v),
      buildInspectionTextField(
          'test_pressure',
          'Пробное давление гидравлического испытания, МПа',
          (v) => checklist.testPressure = v),
      buildInspectionTextField(
          'working_temperature',
          'Допустимая рабочая температура стенки, ℃',
          (v) => checklist.workingTemperature = v),
      buildInspectionTextField('design_temperature',
          'Расчётная температура стенки, ℃',
          (v) => checklist.designTemperature = v),
      buildInspectionTextField('working_medium',
          'Наименование рабочей среды', (v) => checklist.workingMedium = v),
      buildInspectionTextField('medium_characteristics',
          'Характеристика рабочей среды',
          (v) => checklist.mediumCharacteristics = v),
      buildInspectionTextField(
          'vessel_group', 'Группа сосуда', (v) => checklist.vesselGroup = v),
      buildInspectionTextField('medium_group', 'Группа рабочей среды',
          (v) => checklist.mediumGroup = v),
      buildInspectionTextField('corrosion_allowance',
          'Прибавка для компенсации коррозии, мм',
          (v) => checklist.corrosionAllowance = v),
      buildSectionHeader(
        form.sectionHeader('survey_prev', fallback: '12. Анализ результатов предыдущих обследований'),
      ),
      buildMultilineField(
          'previous_inspection_result',
          'Замечания по результатам предыдущих обследований',
          (v) => checklist.previousInspectionResult = v),
    ];
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
