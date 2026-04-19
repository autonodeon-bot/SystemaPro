import 'dart:convert';

/// Модель шаблона чертежа оборудования (П.2 ТЗ 2026-04).
///
/// Координаты точек замера хранятся в ПРОЦЕНТАХ (0-100) от размеров
/// оригинального изображения — это делает шаблон переносимым между
/// устройствами с разной плотностью пикселей и разрешением.
class DrawingTemplate {
  final String id;
  final String name;
  final String? description;
  final String? category;
  final String? equipmentId;
  final String? equipmentTypeId;
  final String? equipmentName;
  final String? equipmentTypeName;
  final String imageFilePath; // серверный путь (/app/uploads/...)
  final int? imageWidth;
  final int? imageHeight;
  final String? mimeType;
  final int? fileSize;
  final int version;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final List<DrawingTemplatePoint> points;

  /// Локальный абсолютный путь до закешированного файла на устройстве.
  /// Заполняется сервисом [DrawingTemplatesService] после скачивания.
  final String? localImagePath;

  const DrawingTemplate({
    required this.id,
    required this.name,
    this.description,
    this.category,
    this.equipmentId,
    this.equipmentTypeId,
    this.equipmentName,
    this.equipmentTypeName,
    required this.imageFilePath,
    this.imageWidth,
    this.imageHeight,
    this.mimeType,
    this.fileSize,
    this.version = 1,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
    this.points = const [],
    this.localImagePath,
  });

  factory DrawingTemplate.fromJson(Map<String, dynamic> json, {String? localImagePath}) {
    final rawPoints = json['points'];
    final pointsList = <DrawingTemplatePoint>[];
    if (rawPoints is List) {
      for (final p in rawPoints) {
        if (p is Map) {
          pointsList.add(DrawingTemplatePoint.fromJson(Map<String, dynamic>.from(p)));
        }
      }
    }

    DateTime? parseDt(dynamic v) {
      if (v == null) return null;
      try {
        return DateTime.parse(v.toString());
      } catch (_) {
        return null;
      }
    }

    return DrawingTemplate(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      description: json['description']?.toString(),
      category: json['category']?.toString(),
      equipmentId: json['equipment_id']?.toString(),
      equipmentTypeId: json['equipment_type_id']?.toString(),
      equipmentName: json['equipment_name']?.toString(),
      equipmentTypeName: json['equipment_type_name']?.toString(),
      imageFilePath: json['image_file_path']?.toString() ?? '',
      imageWidth: _asInt(json['image_width']),
      imageHeight: _asInt(json['image_height']),
      mimeType: json['mime_type']?.toString(),
      fileSize: _asInt(json['file_size']),
      version: _asInt(json['version']) ?? 1,
      isActive: json['is_active'] != false,
      createdAt: parseDt(json['created_at']),
      updatedAt: parseDt(json['updated_at']),
      points: pointsList,
      localImagePath: localImagePath,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'category': category,
        'equipment_id': equipmentId,
        'equipment_type_id': equipmentTypeId,
        'equipment_name': equipmentName,
        'equipment_type_name': equipmentTypeName,
        'image_file_path': imageFilePath,
        'image_width': imageWidth,
        'image_height': imageHeight,
        'mime_type': mimeType,
        'file_size': fileSize,
        'version': version,
        'is_active': isActive,
        'created_at': createdAt?.toIso8601String(),
        'updated_at': updatedAt?.toIso8601String(),
        'points': points.map((p) => p.toJson()).toList(),
      };

  DrawingTemplate copyWith({
    String? localImagePath,
    int? version,
    List<DrawingTemplatePoint>? points,
  }) =>
      DrawingTemplate(
        id: id,
        name: name,
        description: description,
        category: category,
        equipmentId: equipmentId,
        equipmentTypeId: equipmentTypeId,
        equipmentName: equipmentName,
        equipmentTypeName: equipmentTypeName,
        imageFilePath: imageFilePath,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
        mimeType: mimeType,
        fileSize: fileSize,
        version: version ?? this.version,
        isActive: isActive,
        createdAt: createdAt,
        updatedAt: updatedAt,
        points: points ?? this.points,
        localImagePath: localImagePath ?? this.localImagePath,
      );
}

enum DrawingPointType { thickness, ndt, reference, custom }

DrawingPointType parseDrawingPointType(String? raw) {
  switch (raw) {
    case 'ndt':
      return DrawingPointType.ndt;
    case 'reference':
      return DrawingPointType.reference;
    case 'custom':
      return DrawingPointType.custom;
    case 'thickness':
    default:
      return DrawingPointType.thickness;
  }
}

String drawingPointTypeToString(DrawingPointType t) {
  switch (t) {
    case DrawingPointType.ndt:
      return 'ndt';
    case DrawingPointType.reference:
      return 'reference';
    case DrawingPointType.custom:
      return 'custom';
    case DrawingPointType.thickness:
      return 'thickness';
  }
}

class DrawingTemplatePoint {
  final String id;
  final String label;
  final DrawingPointType pointType;
  /// X в процентах (0.0 - 100.0) от ширины изображения
  final double xPercent;
  /// Y в процентах (0.0 - 100.0) от высоты изображения
  final double yPercent;
  final double? expectedValue;
  final String? notes;
  final int sortOrder;

  /// Фактическое значение, введённое инженером (не хранится в шаблоне,
  /// но используется при аннотации для связки с thickness_measurements).
  final double? actualValue;

  /// Флаг: точка добавлена инженером на месте, а не была в шаблоне.
  final bool isUserAdded;

  const DrawingTemplatePoint({
    required this.id,
    required this.label,
    this.pointType = DrawingPointType.thickness,
    required this.xPercent,
    required this.yPercent,
    this.expectedValue,
    this.notes,
    this.sortOrder = 0,
    this.actualValue,
    this.isUserAdded = false,
  });

  factory DrawingTemplatePoint.fromJson(Map<String, dynamic> json) {
    return DrawingTemplatePoint(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      pointType: parseDrawingPointType(json['point_type']?.toString()),
      xPercent: _asDouble(json['x_percent']) ?? 0.0,
      yPercent: _asDouble(json['y_percent']) ?? 0.0,
      expectedValue: _asDouble(json['expected_value']),
      notes: json['notes']?.toString(),
      sortOrder: _asInt(json['sort_order']) ?? 0,
      actualValue: _asDouble(json['actual_value']),
      isUserAdded: json['is_user_added'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'label': label,
        'point_type': drawingPointTypeToString(pointType),
        'x_percent': xPercent,
        'y_percent': yPercent,
        'expected_value': expectedValue,
        'notes': notes,
        'sort_order': sortOrder,
        'actual_value': actualValue,
        'is_user_added': isUserAdded,
      };

  DrawingTemplatePoint copyWith({
    String? label,
    DrawingPointType? pointType,
    double? xPercent,
    double? yPercent,
    double? expectedValue,
    String? notes,
    int? sortOrder,
    double? actualValue,
    bool? isUserAdded,
  }) =>
      DrawingTemplatePoint(
        id: id,
        label: label ?? this.label,
        pointType: pointType ?? this.pointType,
        xPercent: xPercent ?? this.xPercent,
        yPercent: yPercent ?? this.yPercent,
        expectedValue: expectedValue ?? this.expectedValue,
        notes: notes ?? this.notes,
        sortOrder: sortOrder ?? this.sortOrder,
        actualValue: actualValue ?? this.actualValue,
        isUserAdded: isUserAdded ?? this.isUserAdded,
      );
}

int? _asInt(dynamic v) {
  if (v == null) return null;
  if (v is int) return v;
  if (v is num) return v.toInt();
  return int.tryParse(v.toString());
}

double? _asDouble(dynamic v) {
  if (v == null) return null;
  if (v is double) return v;
  if (v is num) return v.toDouble();
  return double.tryParse(v.toString());
}

/// Обёртка для сериализации в JSON-строку (для sqflite.data).
String drawingTemplateToJsonString(DrawingTemplate t) => jsonEncode(t.toJson());
DrawingTemplate drawingTemplateFromJsonString(String s, {String? localImagePath}) =>
    DrawingTemplate.fromJson(jsonDecode(s) as Map<String, dynamic>, localImagePath: localImagePath);
