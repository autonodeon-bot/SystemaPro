// Утилита для генерации имен файлов фотографий
// Формат: {инвентарный_номер}_{название_пункта}_{код}_{timestamp}.jpg

import 'dart:io';
import 'package:intl/intl.dart';

class FileNaming {
  /// Генерирует имя файла для фотографии
  /// 
  /// Параметры:
  /// - inventoryNumber: Инвентарный номер оборудования
  /// - itemName: Название пункта опросного листа
  /// - itemId: ID пункта (код)
  /// - extension: Расширение файла (по умолчанию .jpg)
  /// 
  /// Возвращает: имя файла в формате {инв_номер}_{название}_{код}_{timestamp}.jpg
  static String generateFileName({
    required String inventoryNumber,
    required String itemName,
    required String itemId,
    String extension = 'jpg',
  }) {
    // Нормализуем инвентарный номер (убираем спецсимволы, заменяем пробелы на _)
    final normalizedInventory = inventoryNumber
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .toUpperCase();
    
    // Нормализуем название пункта (убираем спецсимволы, заменяем пробелы на _)
    final normalizedName = itemName
        .replaceAll(RegExp(r'[^\w\s-]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .substring(0, itemName.length > 30 ? 30 : itemName.length);
    
    // Нормализуем ID пункта
    final normalizedId = itemId
        .replaceAll(RegExp(r'[^\w]'), '_')
        .toUpperCase();
    
    // Генерируем timestamp
    final timestamp = DateFormat('yyyyMMdd_HHmmss').format(DateTime.now());
    
    // Формируем имя файла
    final fileName = '${normalizedInventory}_${normalizedName}_${normalizedId}_$timestamp.$extension';
    
    return fileName;
  }
  
  /// Генерирует полный путь для сохранения файла
  /// 
  /// Параметры:
  /// - baseDirectory: Базовая директория для сохранения
  /// - inventoryNumber: Инвентарный номер оборудования
  /// - itemName: Название пункта опросного листа
  /// - itemId: ID пункта (код)
  /// - extension: Расширение файла
  /// 
  /// Возвращает: полный путь к файлу
  static Future<String> generateFilePath({
    required Directory baseDirectory,
    required String inventoryNumber,
    required String itemName,
    required String itemId,
    String extension = 'jpg',
  }) async {
    // Создаем подпапку по инвентарному номеру
    final equipmentFolder = Directory('${baseDirectory.path}/$inventoryNumber');
    if (!await equipmentFolder.exists()) {
      await equipmentFolder.create(recursive: true);
    }
    
    // Генерируем имя файла
    final fileName = generateFileName(
      inventoryNumber: inventoryNumber,
      itemName: itemName,
      itemId: itemId,
      extension: extension,
    );
    
    return '${equipmentFolder.path}/$fileName';
  }
  
  /// Извлекает информацию из имени файла
  /// 
  /// Параметры:
  /// - fileName: Имя файла
  /// 
  /// Возвращает: Map с полями inventoryNumber, itemName, itemId, timestamp
  static Map<String, String>? parseFileName(String fileName) {
    try {
      // Убираем расширение
      final nameWithoutExt = fileName.replaceAll(RegExp(r'\.[^.]+$'), '');
      
      // Разбиваем по подчеркиваниям
      final parts = nameWithoutExt.split('_');
      
      if (parts.length < 4) {
        return null;
      }
      
      // Последние 2 части - это timestamp (yyyyMMdd_HHmmss)
      final timestamp = '${parts[parts.length - 2]}_${parts[parts.length - 1]}';
      
      // Предпоследняя часть - это itemId
      final itemId = parts[parts.length - 3];
      
      // Остальные части - это inventoryNumber и itemName
      // Первая часть - inventoryNumber
      final inventoryNumber = parts[0];
      
      // Остальные части между inventoryNumber и itemId - это itemName
      final itemNameParts = parts.sublist(1, parts.length - 3);
      final itemName = itemNameParts.join('_');
      
      return {
        'inventory_number': inventoryNumber,
        'item_name': itemName,
        'item_id': itemId,
        'timestamp': timestamp,
      };
    } catch (e) {
      return null;
    }
  }
}





