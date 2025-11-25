# 🔨 Инструкция по сборке мобильного приложения

## 📋 Требования

### Обязательные:
- **Flutter SDK** >= 3.2.0
- **Dart SDK** >= 3.2.0
- **Git**

### Для Android:
- **Android Studio** (последняя версия)
- **Android SDK** (API Level 21+)
- **JDK** 11 или выше

### Для iOS (только macOS):
- **Xcode** 14.0+
- **CocoaPods**
- **macOS** 12.0+

## 🚀 Установка Flutter

### Windows

1. **Скачайте Flutter SDK:**
   - https://flutter.dev/docs/get-started/install/windows
   - Распакуйте в `C:\src\flutter` (или другую папку)

2. **Добавьте Flutter в PATH:**
   - Откройте "Переменные среды"
   - Добавьте `C:\src\flutter\bin` в PATH

3. **Проверьте установку:**
   ```cmd
   flutter doctor
   ```

4. **Установите зависимости:**
   ```cmd
   flutter doctor --android-licenses
   ```

### macOS

1. **Скачайте Flutter SDK:**
   ```bash
   cd ~/development
   git clone https://github.com/flutter/flutter.git -b stable
   ```

2. **Добавьте в PATH:**
   ```bash
   export PATH="$PATH:`pwd`/flutter/bin"
   # Добавьте в ~/.zshrc или ~/.bash_profile
   ```

3. **Проверьте установку:**
   ```bash
   flutter doctor
   ```

### Linux

1. **Установите зависимости:**
   ```bash
   sudo apt-get update
   sudo apt-get install -y curl git unzip xz-utils zip libglu1-mesa
   ```

2. **Скачайте Flutter:**
   ```bash
   cd ~/development
   git clone https://github.com/flutter/flutter.git -b stable
   export PATH="$PATH:`pwd`/flutter/bin"
   ```

3. **Проверьте установку:**
   ```bash
   flutter doctor
   ```

## 📱 Подготовка к сборке

### 1. Перейдите в папку проекта

```bash
cd mobile
```

### 2. Установите зависимости

```bash
flutter pub get
```

### 3. Проверьте подключенные устройства

```bash
flutter devices
```

Должны быть доступны:
- Эмулятор Android
- Физическое устройство (через USB)
- iOS симулятор (только на macOS)

## 🔧 Настройка проекта

### Android

1. **Откройте Android Studio**
2. **Откройте проект:** `File > Open > mobile/android`
3. **Установите SDK:**
   - `Tools > SDK Manager`
   - Установите Android SDK Platform 33+
   - Установите Android SDK Build-Tools

4. **Создайте файл `android/local.properties`** (если его нет):
   ```properties
   sdk.dir=C:\\Users\\ВашеИмя\\AppData\\Local\\Android\\Sdk
   ```

5. **Настройте подпись (для release):**
   - Создайте keystore:
     ```bash
     keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
     ```
   - Создайте `android/key.properties`:
     ```properties
     storePassword=<password>
     keyPassword=<password>
     keyAlias=upload
     storeFile=<path-to-keystore>
     ```

### iOS (только на macOS)

1. **Установите CocoaPods:**
   ```bash
   sudo gem install cocoapods
   ```

2. **Установите зависимости:**
   ```bash
   cd ios
   pod install
   cd ..
   ```

3. **Настройте подпись в Xcode:**
   - Откройте `ios/Runner.xcworkspace` в Xcode
   - Выберите `Runner` в навигаторе
   - Вкладка `Signing & Capabilities`
   - Выберите вашу команду разработчика

## 🏃 Запуск в режиме разработки

### Android

```bash
# Запуск на подключенном устройстве/эмуляторе
flutter run

# Запуск на конкретном устройстве
flutter devices
flutter run -d <device_id>

# Запуск в режиме отладки
flutter run --debug

# Запуск в release режиме (быстрее)
flutter run --release
```

### iOS

```bash
# Запуск на симуляторе
flutter run

# Запуск на физическом устройстве
flutter run -d <device_id>

# Запуск в release режиме
flutter run --release
```

## 📦 Сборка APK (Android)

### Debug APK

```bash
flutter build apk --debug
```

APK будет в: `build/app/outputs/flutter-apk/app-debug.apk`

### Release APK

```bash
flutter build apk --release
```

APK будет в: `build/app/outputs/flutter-apk/app-release.apk`

### Split APK (по архитектурам)

```bash
flutter build apk --split-per-abi
```

Создаст отдельные APK для:
- `app-armeabi-v7a-release.apk`
- `app-arm64-v8a-release.apk`
- `app-x86_64-release.apk`

## 📱 Сборка App Bundle (Android)

Для публикации в Google Play:

```bash
flutter build appbundle --release
```

Файл будет в: `build/app/outputs/bundle/release/app-release.aab`

## 🍎 Сборка для iOS

### Debug

```bash
flutter build ios --debug
```

### Release

```bash
flutter build ios --release
```

### Архив для App Store

1. Откройте Xcode:
   ```bash
   open ios/Runner.xcworkspace
   ```

2. В Xcode:
   - Выберите `Product > Archive`
   - Дождитесь завершения
   - Нажмите `Distribute App`
   - Следуйте инструкциям

Или через командную строку:
```bash
flutter build ipa
```

## 🔍 Проверка перед сборкой

### 1. Анализ кода

```bash
flutter analyze
```

### 2. Проверка зависимостей

```bash
flutter pub outdated
```

### 3. Тесты (если есть)

```bash
flutter test
```

## 🐛 Устранение проблем

### Проблема: "No devices found"

**Решение:**
```bash
# Android - запустите эмулятор через Android Studio
# Или подключите устройство через USB с включенной отладкой

# iOS - запустите симулятор
open -a Simulator
```

### Проблема: "Gradle build failed"

**Решение:**
```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter run
```

### Проблема: "CocoaPods not installed" (iOS)

**Решение:**
```bash
sudo gem install cocoapods
cd ios
pod install
cd ..
```

### Проблема: "SDK location not found" (Android)

**Решение:**
Создайте `android/local.properties`:
```properties
sdk.dir=C:\\Users\\ВашеИмя\\AppData\\Local\\Android\\Sdk
```

### Проблема: "Permission denied" (Linux/macOS)

**Решение:**
```bash
chmod +x android/gradlew
```

## 📊 Размер приложения

### Проверка размера APK

```bash
flutter build apk --release --analyze-size
```

### Оптимизация размера

1. **Используйте ProGuard (Android):**
   - В `android/app/build.gradle`:
   ```gradle
   buildTypes {
       release {
           minifyEnabled true
           shrinkResources true
           proguardFiles getDefaultProguardFile('proguard-android.txt'), 'proguard-rules.pro'
       }
   }
   ```

2. **Удалите неиспользуемые ресурсы:**
   ```bash
   flutter build apk --release --split-per-abi
   ```

## 🔐 Подпись приложения

### Android

1. Создайте keystore (если еще нет):
```bash
keytool -genkey -v -keystore ~/upload-keystore.jks -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

2. Создайте `android/key.properties`:
```properties
storePassword=<ваш_пароль>
keyPassword=<ваш_пароль>
keyAlias=upload
storeFile=<путь_к_keystore>
```

3. Обновите `android/app/build.gradle` (добавьте в начало):
```gradle
def keystoreProperties = new Properties()
def keystorePropertiesFile = rootProject.file('key.properties')
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}
```

## 📝 Чек-лист перед релизом

- [ ] Все зависимости установлены (`flutter pub get`)
- [ ] Код проанализирован (`flutter analyze`)
- [ ] Тесты пройдены (`flutter test`)
- [ ] Версия обновлена в `pubspec.yaml`
- [ ] Иконка приложения настроена
- [ ] Splash screen настроен
- [ ] Подпись настроена (для release)
- [ ] API URL проверен
- [ ] Приложение протестировано на реальных устройствах

## 🚀 Быстрая сборка

### Android APK (Release)

```bash
cd mobile
flutter pub get
flutter build apk --release
```

APK: `build/app/outputs/flutter-apk/app-release.apk`

### iOS (только macOS)

```bash
cd mobile
flutter pub get
cd ios && pod install && cd ..
flutter build ios --release
```

## 📞 Полезные команды

```bash
# Очистка проекта
flutter clean

# Обновление зависимостей
flutter pub get

# Обновление Flutter
flutter upgrade

# Проверка установки
flutter doctor -v

# Список устройств
flutter devices

# Запуск с горячей перезагрузкой
flutter run

# Сборка без запуска
flutter build apk --release
```

---

**Готово!** 🎉 Теперь вы можете собрать и запустить мобильное приложение.




