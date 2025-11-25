# ⚡ Быстрый старт - Сборка мобильного приложения

## 🎯 Минимальные шаги для запуска

### 1. Установите Flutter

**Windows:**
```cmd
# Скачайте с https://flutter.dev/docs/get-started/install/windows
# Распакуйте в C:\src\flutter
# Добавьте C:\src\flutter\bin в PATH
```

**macOS:**
```bash
# Скачайте с https://flutter.dev/docs/get-started/install/macos
# Или через Homebrew:
brew install --cask flutter
```

**Linux:**
```bash
# Скачайте с https://flutter.dev/docs/get-started/install/linux
# Распакуйте и добавьте в PATH
```

### 2. Проверьте установку

```bash
flutter doctor
```

Исправьте все проблемы, которые покажет команда.

### 3. Перейдите в папку проекта

```bash
cd mobile
```

### 4. Установите зависимости

```bash
flutter pub get
```

### 5. Запустите приложение

```bash
# Android
flutter run

# iOS (только macOS)
flutter run -d ios
```

## 📱 Если нет устройства

### Android эмулятор

1. Откройте Android Studio
2. `Tools > Device Manager`
3. Создайте новый виртуальный девайс
4. Запустите его
5. Выполните `flutter run`

### iOS симулятор (macOS)

```bash
open -a Simulator
flutter run
```

## 🔨 Сборка APK

```bash
cd mobile
flutter build apk --release
```

APK будет в: `build/app/outputs/flutter-apk/app-release.apk`

## ⚙️ Настройка API

Откройте `lib/services/api_service.dart` и измените:

```dart
static const String baseUrl = 'http://ВАШ_СЕРВЕР:8000';
```

## ✅ Готово!

Приложение должно запуститься и подключиться к вашему backend.

---

**Нужна помощь?** Смотрите полную инструкцию в `BUILD.md`




