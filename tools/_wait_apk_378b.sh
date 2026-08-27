#!/bin/bash
# Wait until build log shows successful copy of 3.7.8-45
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  if grep -q 'es-td-ngo-3.7.8-45.apk' /tmp/build-apk.log 2>/dev/null; then
    if grep -q 'BUILD FAILED' /tmp/build-apk.log 2>/dev/null; then
      # only fail if latest section failed
      :
    fi
    if ls -lh /opt/es-td-ngo/mobile-apk/es-td-ngo-3.7.8-45.apk >/dev/null 2>&1; then
      if grep -E 'Built build/app|cp .*es-td-ngo-3.7.8-45|es-td-ngo-3.7.8-45.apk$' /tmp/build-apk.log >/dev/null 2>&1; then
        echo BUILD_OK
        ls -lh /opt/es-td-ngo/mobile-apk/es-td-ngo-3.7.8-45.apk
        tail -8 /tmp/build-apk.log
        exit 0
      fi
    fi
  fi
  if ! pgrep -f 'flutter build apk' >/dev/null 2>&1; then
    if grep -q 'BUILD FAILED' /tmp/build-apk.log; then
      echo BUILD_FAIL
      tail -40 /tmp/build-apk.log
      exit 1
    fi
    if test -f /opt/es-td-ngo/mobile/build/app/outputs/flutter-apk/app-release.apk; then
      cp /opt/es-td-ngo/mobile/build/app/outputs/flutter-apk/app-release.apk /opt/es-td-ngo/mobile-apk/app-release.apk
      cp /opt/es-td-ngo/mobile-apk/app-release.apk /opt/es-td-ngo/mobile-apk/es-td-ngo-3.7.8-45.apk
      cp /opt/es-td-ngo/mobile-apk/app-release.apk /opt/es-td-ngo/mobile-apk/app.apk
      echo BUILD_OK_MANUAL_COPY
      ls -lh /opt/es-td-ngo/mobile-apk/es-td-ngo-3.7.8-45.apk
      exit 0
    fi
    echo ENDED_NO_APK
    tail -40 /tmp/build-apk.log
    exit 2
  fi
  echo "wait $i"
  sleep 30
done
echo TIMEOUT
tail -40 /tmp/build-apk.log
exit 3
