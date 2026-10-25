import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'driver.dart';

/// Set MIGLASS_CAPTURE=1 to run the scripted capture used by CI; MIGLASS_OUT picks the output folder.
bool get captureRequested => Platform.environment['MIGLASS_CAPTURE'] == '1';

/// Drives the demo through light / dark, menu and dialog, saves a PNG of each state and records every
/// frame's build / raster time plus process RSS, then exits. Output (in MIGLASS_OUT, default ci_out):
///   *.png         screenshots
///   frames.csv    t_ms,build_ms,raster_ms,total_ms   (one row per frame)
///   rss.csv       t_ms,rss_mb                          (every 100 ms)
///   markers.csv   t_ms,label                           (script steps)
Future<void> runCapture(GlobalKey root, DemoDriver d) async {
  final out = Directory(Platform.environment['MIGLASS_OUT'] ?? 'ci_out')..createSync(recursive: true);
  // never hang a CI job
  Timer(const Duration(minutes: 3), () => exit(2));

  final clock = Stopwatch()..start();
  final frames = StringBuffer('t_ms,build_ms,raster_ms,total_ms\n');
  final rss = StringBuffer('t_ms,rss_mb\n');
  final markers = StringBuffer('t_ms,label\n');
  int? firstVsyncUs;
  SchedulerBinding.instance.addTimingsCallback((timings) {
    for (final f in timings) {
      final v = f.timestampInMicroseconds(ui.FramePhase.vsyncStart);
      firstVsyncUs ??= v - clock.elapsedMicroseconds;
      final ms = (v - firstVsyncUs!) / 1000;
      frames.writeln('${ms.toStringAsFixed(1)},${_ms(f.buildDuration)},${_ms(f.rasterDuration)},${_ms(f.totalSpan)}');
    }
  });
  final rssTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
    rss.writeln('${clock.elapsedMilliseconds},${(ProcessInfo.currentRss / (1 << 20)).toStringAsFixed(1)}');
  });
  void mark(String label) => markers.writeln('${clock.elapsedMilliseconds},$label');
  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

  Future<void> shot(String name) async {
    mark('shot $name');
    final boundary = root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final image = await boundary.toImage(pixelRatio: view.devicePixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('${out.path}/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  }

  // shaders load and warm up first
  await wait(3000);
  for (final dark in [false, true]) {
    final mode = dark ? 'dark' : 'light';
    d.setDark(dark);
    mark('$mode mode');
    await wait(1500);
    await shot('${mode}_1_cards');
    mark('$mode menu open');
    d.setMenu(true);
    await wait(1200);
    await shot('${mode}_2_menu');
    mark('$mode dialog');
    d.setMenu(false);
    d.setDialog(true);
    await wait(1200);
    await shot('${mode}_3_dialog');
    d.setDialog(false);
    await wait(800);
    mark('$mode settings');
    d.setSettings(true);
    await wait(1200);
    await shot('${mode}_4_settings');
    d.settingsScroll(160);
    await wait(900);
    await shot('${mode}_5_settings_scrolled');
    d.settingsScroll(0);
    await wait(700);
    d.settingsOptions(true);
    await wait(1000);
    await shot('${mode}_6_settings_options');
    d.settingsOptions(false);
    await wait(600);
    d.setSettings(false);
    await wait(900);
  }
  // stress: open / close the menu repeatedly (the memory-heavy path)
  mark('menu stress');
  for (var i = 0; i < 8; i++) {
    d.setMenu(true);
    await wait(600);
    d.setMenu(false);
    await wait(600);
  }
  mark('idle');
  await wait(2000);
  mark('end');

  rssTimer.cancel();
  await wait(500); // let the last frame timings arrive
  File('${out.path}/frames.csv').writeAsStringSync(frames.toString());
  File('${out.path}/rss.csv').writeAsStringSync(rss.toString());
  File('${out.path}/markers.csv').writeAsStringSync(markers.toString());
  exit(0);
}

String _ms(Duration d) => (d.inMicroseconds / 1000).toStringAsFixed(2);
