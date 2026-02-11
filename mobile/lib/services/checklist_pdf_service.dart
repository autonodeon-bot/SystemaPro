import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import '../models/vessel_checklist.dart';

/// Формирует PDF-документ по чек-листу обследования сосуда (текстовый отчёт).
class ChecklistPdfService {
  static const PdfColor _textColor = PdfColors.black;
  static const PdfColor _headerColor = PdfColors.blue900;

  static pw.Widget _sectionTitle(String text) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 12, bottom: 4),
      child: pw.Text(
        text,
        style: pw.TextStyle(
          color: _headerColor,
          fontSize: 12,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    );
  }

  static pw.Widget _line(String label, String? value) {
    if (value == null || value.isEmpty) return pw.SizedBox.shrink();
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 2),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.SizedBox(
            width: 140,
            child: pw.Text(label, style: const pw.TextStyle(fontSize: 9, color: _textColor)),
          ),
          pw.Expanded(
            child: pw.Text(value, style: const pw.TextStyle(fontSize: 9, color: _textColor)),
          ),
        ],
      ),
    );
  }

  static String _boolStr(bool? v) {
    if (v == null) return '—';
    return v ? 'Да' : 'Нет';
  }

  /// Собирает PDF в байты. [equipmentName] — название оборудования для заголовка.
  static Future<Uint8List> buildPdf(VesselChecklist checklist, String equipmentName) async {
    final doc = pw.Document();
    final List<pw.Widget> blocks = [];

    blocks.add(pw.Text(
      'Обследование: $equipmentName',
      style: pw.TextStyle(color: _headerColor, fontSize: 14, fontWeight: pw.FontWeight.bold),
    ));
    blocks.add(_line('Дата обследования', checklist.inspectionDate));
    blocks.add(_line('Исполнители', checklist.executors));
    blocks.add(_line('Организация', checklist.organization));
    blocks.add(_line('Наименование сосуда', checklist.vesselName));
    blocks.add(_line('Заводской номер', checklist.serialNumber));
    blocks.add(_line('Регистрационный номер', checklist.regNumber));
    blocks.add(_line('Изготовитель', checklist.manufacturer));
    blocks.add(_line('Год изготовления', checklist.manufactureYear));
    blocks.add(_line('Диаметр', checklist.diameter));
    blocks.add(_line('Рабочее давление', checklist.workingPressure));
    blocks.add(_line('Толщина стенки', checklist.wallThickness));

    blocks.add(_sectionTitle('Проверки'));
    blocks.add(_line('Соответствует чертежу', _boolStr(checklist.matchesDrawing)));
    blocks.add(_line('Тепловая изоляция', _boolStr(checklist.hasThermalInsulation)));
    blocks.add(_line('Состояние антикоррозионного покрытия', checklist.anticorrosionCoatingState));
    blocks.add(_line('Состояние опор', checklist.supportState));
    blocks.add(_line('Состояние крепежа', checklist.fastenersState));
    blocks.add(_line('Перекосы фланцев', _boolStr(checklist.hasFlangeMisalignment)));
    blocks.add(_line('Непрямолинейность патрубков', _boolStr(checklist.hasNozzleMisalignment)));
    blocks.add(_line('Ремонт сосуда', _boolStr(checklist.hasVesselRepairs)));
    blocks.add(_line('Ремонт ТПА', _boolStr(checklist.hasTpaRepairs)));
    blocks.add(_line('Внутренние устройства', checklist.internalDevicesState));

    if (checklist.zraItems.isNotEmpty) {
      blocks.add(_sectionTitle('ЗРА (запорно-регулирующая арматура)'));
      for (var i = 0; i < checklist.zraItems.length; i++) {
        final z = checklist.zraItems[i];
        blocks.add(_line('${i + 1}. Кол-во / тип', '${z.quantity ?? "—"} / ${z.typeSize ?? "—"}'));
        blocks.add(_line('   Тех. № / Зав. №', '${z.techNumber ?? "—"} / ${z.serialNumber ?? "—"}'));
        blocks.add(_line('   Место на схеме', z.locationOnScheme ?? '—'));
      }
    }

    if (checklist.sppkItems.isNotEmpty) {
      blocks.add(_sectionTitle('СППК'));
      for (var i = 0; i < checklist.sppkItems.length; i++) {
        final s = checklist.sppkItems[i];
        blocks.add(_line('${i + 1}. Кол-во / тип', '${s.quantity ?? "—"} / ${s.typeSize ?? "—"}'));
        blocks.add(_line('   Тех. № / Зав. №', '${s.techNumber ?? "—"} / ${s.serialNumber ?? "—"}'));
        blocks.add(_line('   Место на схеме', s.locationOnScheme ?? '—'));
      }
    }

    if (checklist.ovalityMeasurements.isNotEmpty) {
      blocks.add(_sectionTitle('Овальность'));
      for (var m in checklist.ovalityMeasurements) {
        blocks.add(_line('Участок ${m.sectionNumber}', 'макс. ${m.maxDiameter ?? "—"} мм, мин. ${m.minDiameter ?? "—"} мм'));
      }
    }

    if (checklist.thicknessMeasurements.isNotEmpty) {
      blocks.add(_sectionTitle('УЗТ (толщинометрия)'));
      for (var t in checklist.thicknessMeasurements) {
        blocks.add(_line('${t.location} / ${t.sectionNumber}', '${t.thickness ?? "—"} мм${t.minAllowedThickness != null ? ", мин. доп. ${t.minAllowedThickness} мм" : ""}'));
      }
    }

    blocks.add(_sectionTitle('Дефекты'));
    blocks.add(_line('Локальные деформации', _boolStr(checklist.hasLocalDeformations)));
    blocks.add(_line('Наружный осмотр', _boolStr(checklist.hasExternalDefects)));
    blocks.add(_line('Внутренний осмотр', _boolStr(checklist.hasInternalDefects)));
    blocks.add(_line('Арматура', _boolStr(checklist.hasArmatureDefects)));

    blocks.add(_sectionTitle('Заключение'));
    blocks.add(pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 8),
      child: pw.Text(
        checklist.conclusion ?? '—',
        style: const pw.TextStyle(fontSize: 10, color: _textColor),
      ),
    ));

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (pw.Context context) => blocks,
      ),
    );

    return doc.save();
  }
}
