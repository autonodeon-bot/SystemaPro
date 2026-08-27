#!/bin/bash
# Ждём сборку APK 3.7.10+47; не выходим на этапе pub get / sdkmanager
for i in $(seq 1 80); do
  if test -f /opt/es-td-ngo/mobile-apk/es-td-ngo-3.7.10-47.apk; then
    # файл мог остаться от прошлого — проверяем свежесть (< 2 часов) или маркер в логе
    if grep -q 'es-td-ngo-3.7.10-47.apk' /tmp/build-apk.log 2>/dev/null; then
      echo BUILD_OK
      ls -lh /opt/es-td-ngo/mobile-apk/es-td-ngo-3.7.10-47.apk /opt/es-td-ngo/mobile-apk/app-release.apk
      mkdir -p /opt/es-td-ngo/nginx/html/mobile /opt/es-td-ngo/dist/mobile /opt/es-td-ngo/public/mobile
      cp -f /opt/es-td-ngo/mobile-apk/app-release.apk /opt/es-td-ngo/nginx/html/mobile/app-release.apk
      cp -f /opt/es-td-ngo/mobile-apk/es-td-ngo-3.7.10-47.apk /opt/es-td-ngo/nginx/html/mobile/
      cp -f /opt/es-td-ngo/mobile-apk/app-release.apk /opt/es-td-ngo/dist/mobile/app-release.apk
      cp -f /opt/es-td-ngo/mobile-apk/app-release.apk /opt/es-td-ngo/public/mobile/app-release.apk
      chmod a+r /opt/es-td-ngo/mobile-apk/*.apk /opt/es-td-ngo/nginx/html/mobile/*.apk 2>/dev/null || true
      exit 0
    fi
  fi

  # процесс ещё идёт?
  if pgrep -f 'flutter_tools.snapshot' >/dev/null 2>&1 \
     || pgrep -f 'gradle' >/dev/null 2>&1 \
     || pgrep -f 'build-apk-server' >/dev/null 2>&1 \
     || pgrep -f 'sdkmanager' >/dev/null 2>&1 \
     || pgrep -f 'dartvm' >/dev/null 2>&1; then
    echo "wait $i"
    sleep 30
    continue
  fi

  # процесс умер — пробуем собрать артефакт вручную
  if test -f /opt/es-td-ngo/mobile/build/app/outputs/flutter-apk/app-release.apk; then
    cp /opt/es-td-ngo/mobile/build/app/outputs/flutter-apk/app-release.apk /opt/es-td-ngo/mobile-apk/app-release.apk
    cp /opt/es-td-ngo/mobile-apk/app-release.apk /opt/es-td-ngo/mobile-apk/es-td-ngo-3.7.10-47.apk
    cp /opt/es-td-ngo/mobile-apk/app-release.apk /opt/es-td-ngo/mobile-apk/app.apk
    chmod a+r /opt/es-td-ngo/mobile-apk/*.apk
    echo BUILD_OK_FALLBACK
    ls -lh /opt/es-td-ngo/mobile-apk/es-td-ngo-3.7.10-47.apk
    exit 0
  fi

  # дать процессу время стартовать в первые минуты
  if [ "$i" -lt 4 ]; then
    echo "startup wait $i"
    sleep 30
    continue
  fi

  echo ENDED
  tail -c 3000 /tmp/build-apk.log
  exit 1
done
echo TIMEOUT
tail -c 3000 /tmp/build-apk.log
exit 1
