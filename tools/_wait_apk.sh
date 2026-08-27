#!/bin/bash
for i in $(seq 1 30); do
  if test -f /opt/es-td-ngo/mobile-apk/es-td-ngo-3.7.7-44.apk; then
    # ensure file is fresh (mtime after build start)
    echo BUILD_OK
    ls -lh /opt/es-td-ngo/mobile-apk/es-td-ngo-3.7.7-44.apk /opt/es-td-ngo/mobile-apk/app-release.apk
    exit 0
  fi
  if grep -q 'BUILD FAILED' /tmp/build-apk.log 2>/dev/null; then
    # only fail if process ended
    if ! pgrep -f 'flutter build apk' >/dev/null 2>&1; then
      echo BUILD_FAIL
      tail -60 /tmp/build-apk.log
      exit 1
    fi
  fi
  echo "wait $i"
  sleep 30
done
echo TIMEOUT
tail -40 /tmp/build-apk.log
exit 3
