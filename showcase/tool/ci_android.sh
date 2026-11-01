#!/bin/bash
# Runs the release APK's perf mode on the booted emulator; the CSV comes back through logcat.
set -u
out=$1
adb logcat -G 32M || true
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb logcat -c
adb shell am start -n com.example.hyper_glass/.MainActivity
for i in $(seq 1 90); do
  sleep 10
  adb logcat -d -s flutter:I > "$out"
  grep -q 'PERF,E' "$out" && break
  adb shell pidof com.example.hyper_glass > /dev/null || { echo 'app is gone'; break; }
done
adb logcat -d -s flutter:I > "$out"
adb logcat -d -b crash | tail -40
grep -c 'PERF,' "$out" || true
