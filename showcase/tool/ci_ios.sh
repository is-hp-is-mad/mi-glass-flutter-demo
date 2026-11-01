#!/bin/bash
# Runs the debug simulator build's perf mode. The simulator shares the host's file system, so the app writes the CSV
# straight to $1, passed in through SIMCTL_CHILD_.
set -u
out=$1
udid=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
d = json.load(sys.stdin)['devices']
print(next(x['udid'] for r in sorted(d, reverse=True) if 'iOS' in r for x in d[r] if 'iPhone' in x['name']))")
xcrun simctl boot "$udid"
xcrun simctl bootstatus "$udid" -b
xcrun simctl install "$udid" build/ios/iphonesimulator/Runner.app
SIMCTL_CHILD_SHOWCASE_PERF="$out" xcrun simctl launch "$udid" com.example.hyperGlass
for i in $(seq 1 90); do
  sleep 10
  [ -f "$out" ] && grep -q 'PERF,E' "$out" && break
done
ls -la "$out"
