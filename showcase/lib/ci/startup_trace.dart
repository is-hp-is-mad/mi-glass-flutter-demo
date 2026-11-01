import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/scheduler.dart';

/// MIGLASS_STARTUP=path: log every frame over 20 ms during the first seconds to that file, then exit.
void startupTrace() {
  final path = Platform.environment['MIGLASS_STARTUP'];
  if (path == null) return;
  final log = StringBuffer();
  var n = 0;
  int? first;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final f in timings) {
      n++;
      final v = f.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      first ??= v;
      if (n <= 3 || f.totalSpan.inMilliseconds > 20) {
        log.writeln(
          '#$n t=${(v - first!) ~/ 1000}ms build=${f.buildDuration.inMilliseconds} '
          'raster=${f.rasterDuration.inMilliseconds} total=${f.totalSpan.inMilliseconds}',
        );
      }
    }
  });
  Future<void>.delayed(const Duration(seconds: 8), () {
    File(path).writeAsStringSync('frames=$n\n$log');
    exit(0);
  });
}
