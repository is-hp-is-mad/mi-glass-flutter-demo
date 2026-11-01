import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';

import '../catalog/app.dart';
import '../screens/traits.dart';
import '../screens/weather.dart';
import '../ui/kit.dart';

/// SHOWCASE_SHOTS=dir: walks through every screen and saves a PNG of each. Screens are reached through
/// [Os.drive]; inside a screen, taps target a Text or Icon found in the element tree.
Future<void> runShots(GlobalKey root, Os os) async {
  final dir = Platform.environment['SHOWCASE_SHOTS'];
  // SHOWCASE_PERF=file, or --dart-define=SHOWCASE_PERF=stdout where the app gets no environment (Android)
  const perfDefine = String.fromEnvironment('SHOWCASE_PERF');
  final perf = Platform.environment['SHOWCASE_PERF'] ?? (perfDefine.isEmpty ? null : perfDefine);
  if (dir == null && perf == null) return;
  if (dir != null) Directory(dir).createSync(recursive: true);
  FlutterError.onError = (d) => stderr.writeln('shots: ${d.exceptionAsString()}\n${d.stack}');
  Timer(Duration(minutes: perf != null ? 15 : 4), () => exit(2)); // software GPUs on CI are slow
  Future<void> wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));
  final ro = root.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final view = WidgetsBinding.instance.platformDispatcher.views.first;
  var id = 100;

  void send(PointerEvent e) => GestureBinding.instance.handlePointerEvent(e);
  Future<void> tapAt(Offset p, {int hold = 40}) async {
    id++;
    send(PointerAddedEvent(pointer: id, position: p));
    send(PointerDownEvent(pointer: id, position: p));
    await wait(hold);
    send(PointerUpEvent(pointer: id, position: p));
  }

  // the last match is the one painted on top
  Offset? find(bool Function(Widget) test) {
    Offset? hit;
    void visit(Element e) {
      if (test(e.widget)) {
        final box = e.renderObject;
        if (box is RenderBox && box.hasSize && box.attached) hit = box.localToGlobal(box.size.center(Offset.zero));
      }
      e.visitChildElements(visit);
    }

    root.currentContext!.visitChildElements(visit);
    return hit;
  }

  Future<void> tapText(String t) async {
    final p = find((w) => w is Text && w.data == t);
    if (p == null) return stderr.writeln('shots: no text "$t"');
    await tapAt(p);
  }

  Future<void> tapFraction(double x, double y) => tapAt(ro.localToGlobal(Offset(ro.size.width * x, ro.size.height * y)));

  Future<void> drag(double x, double y0, double y1, {int steps = 12}) async {
    final a = ro.localToGlobal(Offset(ro.size.width * x, ro.size.height * y0));
    final b = ro.localToGlobal(Offset(ro.size.width * x, ro.size.height * y1));
    id++;
    send(PointerAddedEvent(pointer: id, position: a));
    send(PointerDownEvent(pointer: id, position: a));
    var last = a;
    for (var i = 1; i <= steps; i++) {
      final p = Offset.lerp(a, b, i / steps)!;
      send(PointerMoveEvent(pointer: id, position: p, delta: p - last));
      last = p;
      await wait(16);
    }
    await wait(140); // rest before lifting: no fling, and a scrollable ignores taps during one
    send(PointerUpEvent(pointer: id, position: b));
  }

  void tab(int i) {
    void visit(Element e) {
      if (e is StatefulElement && e.state is CatalogAppState) (e.state as CatalogAppState).selectTab(i);
      e.visitChildElements(visit);
    }

    root.currentContext!.visitChildElements(visit);
  }

  Future<void> shot(String name) async {
    final image = await ro.toImage(pixelRatio: view.devicePixelRatio);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    File('$dir/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  }

  if (perf != null) {
    final app = () {
      CatalogAppState? s;
      void visit(Element e) {
        if (e is StatefulElement && e.state is CatalogAppState) s = e.state as CatalogAppState;
        e.visitChildElements(visit);
      }

      root.currentContext!.visitChildElements(visit);
      return s!;
    }();
    final frames = <FrameTiming>[];
    SchedulerBinding.instance.addTimingsCallback(frames.addAll);
    if (perf != 'stdout') File(perf).writeAsStringSync('');
    int? origin;

    // CSV, one record per line: M(eta), S(ummary of a scene), F(rame), E(nd). tool/plot_perf.py reads it.
    Future<void> emit(List<String> lines) async {
      if (perf != 'stdout') {
        File(perf).writeAsStringSync('${lines.join('\n')}\n', mode: FileMode.append);
        return;
      }
      for (var i = 0; i < lines.length; i++) {
        // ignore: avoid_print
        print(lines[i]);
        if (i % 30 == 29) await wait(4); // logcat drops lines when flooded
      }
    }

    Future<void> report(String name, int ms) async {
      List<double> sorted(double Function(FrameTiming) f) => frames.map(f).toList()..sort();
      double at(List<double> v, double q) => v.isEmpty ? 0 : v[((v.length - 1) * q).round()];
      final build = sorted((f) => f.buildDuration.inMicroseconds / 1000);
      final raster = sorted((f) => f.rasterDuration.inMicroseconds / 1000);
      // the time between finished frames: what the eye gets, unlike totalSpan, which counts the wait for vsync
      int done(FrameTiming f) => f.timestampInMicroseconds(ui.FramePhase.rasterFinish);
      final ordered = [...frames]..sort((x, y) => done(x).compareTo(done(y)));
      final gaps = [for (var i = 1; i < ordered.length; i++) (done(ordered[i]) - done(ordered[i - 1])) / 1000.0]..sort();
      String n(double v) => v.toStringAsFixed(2);
      final lines = [
        'PERF,S,$name,${frames.length},${(frames.length * 1000 / ms).toStringAsFixed(0)},'
            '${n(at(build, .5))},${n(at(build, .95))},${n(at(raster, .5))},${n(at(raster, .95))},${n(at(raster, 1))},'
            '${n(at(gaps, .5))},${n(at(gaps, .95))},${n(at(gaps, 1))},${gaps.where((v) => v > 33.4).length},'
            '${ProcessInfo.currentRss >> 20}',
      ];
      for (var i = 0; i < ordered.length; i++) {
        final f = ordered[i];
        origin ??= done(f);
        final gap = i == 0 ? 0.0 : (done(f) - done(ordered[i - 1])) / 1000;
        lines.add(
          'PERF,F,$name,${((done(f) - origin!) / 1000).round()},${n(f.buildDuration.inMicroseconds / 1000)},'
          '${n(f.rasterDuration.inMicroseconds / 1000)},${n(gap)}',
        );
      }
      await emit(lines);
    }

    Future<void> run(String name, Future<void> Function() body) async {
      await wait(600);
      frames.clear();
      final sw = Stopwatch()..start();
      await body();
      await wait(120);
      final ms = sw.elapsedMilliseconds;
      await report(name, ms);
    }

    // the finger stays down and swings the list up and down, one move per frame
    Future<void> swing(int count) async {
      Offset at(int i) => ro.localToGlobal(Offset(ro.size.width * 0.5, ro.size.height * (0.5 + 0.25 * math.sin(i * math.pi / 30))));
      id++;
      var last = at(0);
      send(PointerAddedEvent(pointer: id, position: last));
      send(PointerDownEvent(pointer: id, position: last));
      for (var i = 1; i <= count; i++) {
        final p = at(i);
        send(PointerMoveEvent(pointer: id, position: p, delta: p - last));
        last = p;
        await wait(16);
      }
      send(PointerUpEvent(pointer: id, position: last));
    }

    await wait(1800);
    await emit([
      'PERF,M,${Platform.operatingSystem},${view.display.refreshRate.toStringAsFixed(0)},${ro.size.width.round()},'
          '${ro.size.height.round()},${view.devicePixelRatio},${ui.ImageFilter.isShaderFilterSupported ? 'impeller' : 'skia'}',
    ]);
    await run('idle', () => wait(3000));
    await run('settings scroll', () => swing(240));
    tab(1);
    await run('controls scroll', () => swing(240));
    tab(2);
    await wait(800);
    await run('materials scroll', () => swing(240));
    tab(0);
    await run('tab switch', () async {
      for (var i = 0; i < 18; i++) {
        tab(i % 3);
        await wait(350);
      }
    });
    tab(1);
    await run('dialog', () async {
      for (var i = 0; i < 6; i++) {
        app.dialog('标题', '内容');
        await wait(500);
        await tapFraction(0.5, 0.15);
        await wait(500);
      }
    });
    await run('sheet', () async {
      for (var i = 0; i < 6; i++) {
        app.sheet();
        await wait(500);
        await tapFraction(0.5, 0.15);
        await wait(500);
      }
    });
    await run('push pop', () async {
      for (var i = 0; i < 6; i++) {
        app.push(WeatherApp(onBack: app.pop));
        await wait(700);
        app.pop();
        await wait(700);
      }
    });
    app.push(TraitsApp(onBack: app.pop));
    await wait(1500);
    await run('traits idle', () => wait(3000));
    await run('traits scroll', () => swing(240));
    app.pop();
    await wait(900);
    app.push(WeatherApp(onBack: app.pop));
    await wait(1200);
    await run('weather scroll', () => swing(240));
    app.pop();
    await wait(900);
    await emit(['PERF,E']);
    await wait(300);
    exit(0);
  }

  await wait(1800);
  await shot('01_settings');
  await drag(0.5, 0.8, 0.3);
  await wait(700);
  await shot('02_settings_scrolled');
  await drag(0.5, 0.8, 0.25);
  await wait(700);
  await shot('03_settings_more');
  tab(1);
  await wait(900);
  await shot('04_controls');
  await drag(0.5, 0.85, 0.25);
  await wait(700);
  await shot('05_controls_2');
  await drag(0.5, 0.85, 0.2);
  await wait(700);
  await shot('06_controls_3');
  await drag(0.5, 0.85, 0.2);
  await wait(700);
  await shot('07_controls_4');
  await tapText('下拉选择');
  await wait(800);
  await shot('08_spinner');
  await tapFraction(0.1, 0.2);
  await wait(800);
  await tapText('对话框');
  await wait(800);
  await shot('09_dialog');
  await tapText('取消');
  await wait(800);
  await tapText('底部面板');
  await wait(800);
  await shot('10_sheet');
  await tapFraction(0.5, 0.2);
  await wait(800);
  tab(2);
  await wait(1400);
  await shot('11_materials');
  await drag(0.5, 0.85, 0.25);
  await wait(900);
  await shot('12_materials_2');
  await drag(0.5, 0.85, 0.2);
  await wait(900);
  await shot('13_materials_3');
  for (var i = 0; i < 6; i++) {
    await drag(0.5, 0.85, 0.2);
    await wait(300);
  }
  await wait(900);
  for (final (i, name) in const ['玻璃实验室', '特性图鉴', '相册示例', '天气示例'].indexed) {
    await tapText(name);
    await wait(1500);
    await shot('2${i}_detail');
    final back = find((w) => w is Icon && w.icon == Icons.arrow_back_ios_new);
    if (back == null) {
      stderr.writeln('shots: no back on $name');
    } else {
      await tapAt(back);
    }
    await wait(900);
  }
  // back to the top, shooting as the sample comes back into view
  for (var i = 0; i < 8; i++) {
    await drag(0.5, 0.2, 0.85, steps: 8);
    await shot('3${i}_back');
  }
  tab(0);
  await wait(600);
  os.setDark(true);
  await wait(900);
  await shot('14_settings_dark');
  tab(1);
  await wait(800);
  await shot('15_controls_dark');
  exit(0);
}
