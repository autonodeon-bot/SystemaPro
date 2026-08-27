#!/bin/bash
# Ждём сборку APK 3.7.11+48
APK_VER=es-td-ngo-3.7.11-48.apk
for i in $(seq 1 100); do
  if grep -q "${APK_VER}" /tmp/build-apk.log 2>/dev/null; then
    if test -f "/opt/es-td-ngo/mobile-apk/${APK_VER}"; then
      echo BUILD_OK
      ls -lh "/opt/es-td-ngo/mobile-apk/${APK_VER}" /opt/es-td-ngo/mobile-apk/app-release.apk
      mkdir -p /opt/es-td-ngo/nginx/html/mobile /opt/es-td-ngo/dist/mobile /opt/es-td-ngo/public/mobile
      cp -f /opt/es-td-ngo/mobile-apk/app-release.apk /opt/es-td-ngo/nginx/html/mobile/app-release.apk
      cp -f /opt/es-td-ngo/mobile-apk/app-release.apk /opt/es-td-ngo/nginx/html/mobile/app.apk
      cp -f "/opt/es-td-ngo/mobile-apk/${APK_VER}" /opt/es-td-ngo/nginx/html/mobile/
      cp -f /opt/es-td-ngo/mobile-apk/app-release.apk /opt/es-td-ngo/dist/mobile/app-release.apk
      cp -f /opt/es-td-ngo/mobile-apk/app-release.apk /opt/es-td-ngo/public/mobile/app-release.apk
      # docker volume mount — обновить то, что отдаёт nginx контейнер
      if docker inspect es_td_ngo_frontend >/dev/null 2>&1; then
        docker cp /opt/es-td-ngo/mobile-apk/app-release.apk es_td_ngo_frontend:/usr/share/nginx/html/mobile/app-release.apk 2>/dev/null || true
        docker cp /opt/es-td-ngo/mobile-apk/app.apk es_td_ngo_frontend:/usr/share/nginx/html/mobile/app.apk 2>/dev/null || true
        docker cp "/opt/es-td-ngo/mobile-apk/${APK_VER}" "es_td_ngo_frontend:/usr/share/nginx/html/mobile/${APK_VER}" 2>/dev/null || true
      fi
      chmod a+r /opt/es-td-ngo/mobile-apk/*.apk /opt/es-td-ngo/nginx/html/mobile/*.apk 2>/dev/null || true
      exit 0
    fi
  fi

  if grep -q 'BUILD FAILED\|Gradle task assembleRelease failed\|Flutter failed' /tmp/build-apk.log 2>/dev/null; then
    if ! pgrep -f 'flutter_tools.snapshot' >/dev/null 2>&1 \
       && ! pgrep -f 'build-apk-server' >/dev/null 2>&1; then
      echo BUILD_FAILED
      tail -c 4000 /tmp/build-apk.log
      exit 1
    fi
  fi

  if pgrep -f 'flutter_tools.snapshot' >/dev/null 2>&1 \
     || pgrep -f 'gradle' >/dev/null 2>&1 \
     || pgrep -f 'build-apk-server' >/dev/null 2>&1 \
     || pgrep -f 'sdkmanager' >/dev/null 2>&1 \
     || pgrep -f 'dartvm' >/dev/null 2>&1; then
    echo "wait $i"
    sleep 30
    continue
  fi

  if test -f /opt/es-td-ngo/mobile/build/app/outputs/flutter-apk/app-release.apk; then
    cp /opt/es-td-ngo/mobile/build/app/outputs/flutter-apk/app-release.apk /opt/es-td-ngo/mobile-apk/app-release.apk
    cp /opt/es-td-ngo/mobile-apk/app-release.apk "/opt/es-td-ngo/mobile-apk/${APK_VER}"
    cp /opt/es-td-ngo/mobile-apk/app-release.apk /opt/es-td-ngo/mobile-apk/app.apk
    chmod a+r /opt/es-td-ngo/mobile-apk/*.apk
    echo BUILD_OK_FALLBACK
    ls -lh "/opt/es-td-ngo/mobile-apk/${APK_VER}"
    exit 0
  fi

  if [ "$i" -lt 4 ]; then
    echo "startup wait $i"
    sleep 30
    continue
  fi

  echo ENDED
  tail -c 4000 /tmp/build-apk.log
  exit 1
done
echo TIMEOUT
tail -c 4000 /tmp/build-apk.log
exit 1
