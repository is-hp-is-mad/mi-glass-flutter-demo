#!/bin/bash
# Runs the debug simulator build's perf mode. iOS apps get no environment, so the path comes from --dart-define at build
# time; the simulator shares the host's file system, so the app writes the CSV straight to $1.
set -u
out=$1
log=$(dirname "$out")
udid=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
d = json.load(sys.stdin)['devices']
print(next(x['udid'] for r in sorted(d, reverse=True) if 'iOS' in r for x in d[r] if 'iPhone' in x['name']))")
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b > /dev/null
xcrun simctl install "$udid" build/ios/iphonesimulator/Runner.app
xcrun simctl launch --stdout="$log/ios_stdout.txt" --stderr="$log/ios_stderr.txt" "$udid" com.example.hyperGlass
for i in $(seq 1 120); do
  sleep 10
  [ -f "$out" ] && grep -q 'PERF,E' "$out" && break
done
xcrun simctl io "$udid" screenshot "$log/ios_last.png" || true
cp ~/Library/Logs/DiagnosticReports/Runner* "$log/" 2>/dev/null || true
ls -la "$log"
[ -f "$out" ]
