# 📱 Пошаговая инструкция по сборке

## Шаг 1: Установка Flutter

### Windows

1. Скачайте Flutter SDK:
   - https://docs.flutter.dev/get-started/install/windows
   - Распакуйте в `C:\src\flutter`

2. Добавьте в PATH:
   - Откройте "Переменные среды"
   - Добавьте `C:\src\flutter\bin`

3. Проверьте:
   ```cmd
   flutter doctor
   ```

### macOS

```bash
# Через Homebrew
brew install --cask flutter

# Или вручную
cd ~/development
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:`pwd`/flutter/bin"
```

### Linux

```bash
cd ~/development
git clone https://github.com/flutter/flutter.git -b stable
export PATH="$PATH:`pwd`/flutter/bin"
```

## Шаг 2: Установка зависимостей

```bash
cd mobile
flutter pub get
```

## Шаг 3: Настройка Android

### Установите Android Studio

1. Скачайте: https://developer.android.com/studio
2. Установите Android SDK (API 33+)
3. Создайте эмулятор или подключите устройство

### Настройте проект

1. Откройте Android Studio
2. `File > Open > mobile/android`
3. Дождитесь синхронизации Gradle

## Шаг 4: Настройка iOS (только macOS)

```bash
cd mobile/ios
pod install
cd ../..
```

## Шаг 5: Запуск

### Android

```bash
# Проверьте устройства
flutter devices

# Запустите
flutter run
```

### iOS

```bash
# Откройте симулятор
open -a Simulator

# Запустите
flutter run
```

## Шаг 6: Сборка APK

```bash
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`

## Шаг 7: Сборка App Bundle (для Google Play)

```bash
flutter build appbundle --release
```

Файл: `build/app/outputs/bundle/release/app-release.aab`

## Шаг 8: Сборка для iOS (только macOS)

```bash
flutter build ios --release
```

Затем в Xcode:
1. Откройте `ios/Runner.xcworkspace`
2. `Product > Archive`
3. `Distribute App`

## ⚠️ Частые проблемы

### "No devices found"

**Android:**
- Запустите эмулятор через Android Studio
- Или подключите устройство с включенной отладкой USB

**iOS:**
```bash
open -a Simulator
```

### "Gradle build failed"

```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
```

### "CocoaPods error" (iOS)

```bash
sudo gem install cocoapods
cd ios
pod install
cd ..
```

---

**Готово!** Приложение собрано и готово к использованию.




