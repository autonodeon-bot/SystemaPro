#!/bin/bash
APK_VER=es-td-ngo-3.7.26-63.apk
for i in $(seq 1 120); do
  if grep -q "${APK_VER}" /tmp/build-apk.log 2>/dev/null; then
    if test -f "/opt/es-td-ngo/mobile-apk/${APK_VER}"; then
      echo BUILD_OK
      ls -lh "/opt/es-td-ngo/mobile-apk/${APK_VER}" /opt/es-td-ngo/mobile-apk/app-release.apk
      chmod a+r /opt/es-td-ngo/mobile-apk/*.apk 2>/dev/null || true
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
