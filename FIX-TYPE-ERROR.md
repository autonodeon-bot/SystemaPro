# Исправление ошибки типов в мобильном приложении

## Проблема
```
Error fetching equipment: type "String" is not a subtype of type "Int?" in type cast
```

## Причина
В модели `Equipment` поле `typeId` было определено как `int?`, но backend возвращает UUID как строку (`String`).

Backend возвращает:
```json
{
  "id": "uuid-string",
  "name": "Сосуд В-101",
  "type_id": "uuid-string",  // ← Это строка, не число!
  ...
}
```

Модель ожидала:
```dart
typeId: json['type_id'] as int?,  // ❌ Ошибка!
```

## Исправление

### 1. Изменен тип `typeId`

**Было:**
```dart
final int? typeId;
typeId: json['type_id'] as int?,
```

**Стало:**
```dart
final String? typeId;  // UUID - это строка
typeId: json['type_id'] as String?,
```

### 2. Добавлен безопасный парсинг JSON

Теперь парсинг обрабатывает случаи, когда `type_id` может быть:
- `String` (UUID) - основной случай
- `int` - для обратной совместимости
- `null` - если не указан

```dart
String? parseTypeId(dynamic value) {
  if (value == null) return null;
  if (value is String) return value;
  if (value is int) return value.toString();
  return null;
}
```

## Что нужно сделать

### 1. Пересобрать мобильное приложение

```bash
cd mobile
flutter clean
flutter pub get
flutter build apk --release
```

Или для запуска в режиме разработки:
```bash
flutter run
```

### 2. Проверить работу

После пересборки:
1. Запустите приложение
2. Попробуйте загрузить список оборудования
3. Ошибка должна исчезнуть

## Файлы изменены

- ✅ `mobile/lib/models/equipment.dart` - исправлен тип `typeId` и добавлен безопасный парсинг

## Проверка

После исправления приложение должно:
- ✅ Успешно загружать список оборудования
- ✅ Корректно обрабатывать `type_id` как строку (UUID)
- ✅ Не выдавать ошибки приведения типов



