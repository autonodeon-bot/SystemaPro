#!/bin/bash
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30; do
  if test -f /opt/es-td-ngo/mobile-apk/es-td-ngo-3.7.8-45.apk; then
    echo BUILD_OK
    ls -lh /opt/es-td-ngo/mobile-apk/es-td-ngo-3.7.8-45.apk
    exit 0
  fi
  if grep -q 'BUILD FAILED' /tmp/build-apk.log 2>/dev/null; then
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
