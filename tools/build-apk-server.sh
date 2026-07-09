#!/bin/bash
set -e
export DEBIAN_FRONTEND=noninteractive
if ! command -v java >/dev/null 2>&1; then
  apt-get update -qq
  apt-get install -y -qq openjdk-17-jdk wget unzip git ca-certificates
fi
if [ ! -d /opt/flutter/bin ]; then
  cd /tmp
  wget -q https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_3.38.4-stable.tar.xz -O flutter.tar.xz
  tar -xf flutter.tar.xz -C /opt
fi
export PATH="/opt/flutter/bin:$PATH"
git config --global --add safe.directory /opt/flutter
flutter config --no-analytics >/dev/null 2>&1 || true
if [ ! -d /opt/android-sdk/cmdline-tools/latest ]; then
  mkdir -p /opt/android-sdk/cmdline-tools
  cd /tmp
  wget -q https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O cmdline-tools.zip
  unzip -qo cmdline-tools.zip -d /opt/android-sdk/cmdline-tools
  mv /opt/android-sdk/cmdline-tools/cmdline-tools /opt/android-sdk/cmdline-tools/latest
fi
export ANDROID_HOME=/opt/android-sdk
export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager "platform-tools" "platforms;android-36" "build-tools;36.0.0" >/dev/null
rm -f /opt/es-td-ngo/mobile/android/local.properties
rm -rf /opt/es-td-ngo/mobile/android/.gradle
cd /opt/es-td-ngo/mobile
flutter pub get
flutter build apk --release
cp build/app/outputs/flutter-apk/app-release.apk /opt/es-td-ngo/mobile-apk/app-release.apk
cp /opt/es-td-ngo/mobile-apk/app-release.apk /opt/es-td-ngo/mobile-apk/es-td-ngo-3.7.5-42.apk
chmod -R a+rX /opt/es-td-ngo/mobile-apk
ls -lh /opt/es-td-ngo/mobile-apk/app-release.apk
