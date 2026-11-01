import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'catalog/app.dart';
import 'ci/shots_stub.dart' if (dart.library.io) 'ci/shots.dart';
import 'ci/startup_trace.dart';
import 'hyper_glass.dart';
import 'ui/kit.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  limitSkiaResourceCache();
  await ViewShadow.load();
  startupTrace();
  runApp(const ShowcaseApp());
}

/// miuix lists spring back past their ends and show no desktop scrollbar; the mouse drags like a finger.
class _SpringScroll extends MaterialScrollBehavior {
  const _SpringScroll();
  @override
  Set<PointerDeviceKind> get dragDevices => PointerDeviceKind.values.toSet();
  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  @override
  Widget buildScrollbar(BuildContext context, Widget child, ScrollableDetails details) => child;
  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) => child;
}

class ShowcaseApp extends StatefulWidget {
  const ShowcaseApp({super.key});
  @override
  State<ShowcaseApp> createState() => _ShowcaseAppState();
}

class _ShowcaseAppState extends State<ShowcaseApp> {
  // SHOWCASE_STILL: a frozen wallpaper, so two screenshot runs can be compared pixel by pixel
  final _os = Os()..animatedWallpaper = !Platform.environment.containsKey('SHOWCASE_STILL');
  final _root = GlobalKey();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => runShots(_root, _os));
  }

  @override
  Widget build(BuildContext context) => OsScope(
    os: _os,
    child: AnimatedBuilder(
      animation: _os,
      builder: (context, _) => MaterialApp(
        debugShowCheckedModeBanner: false,
        title: '柔光玻璃',
        scrollBehavior: const _SpringScroll(),
        themeMode: _os.dark ? ThemeMode.dark : ThemeMode.light,
        theme: ThemeData(brightness: Brightness.light, fontFamily: 'MiSans', splashFactory: NoSplash.splashFactory),
        darkTheme: ThemeData(brightness: Brightness.dark, fontFamily: 'MiSans', splashFactory: NoSplash.splashFactory),
        // On a desktop window the phone UI keeps phone proportions, centred.
        builder: (context, child) => LayoutBuilder(
          builder: (context, c) {
            final w = math.min(c.maxWidth, c.maxHeight * 0.52).clamp(320.0, 520.0);
            return ColoredBox(
              color: Colors.black,
              child: Center(
                child: SizedBox(
                  width: w,
                  height: c.maxHeight,
                  child: RepaintBoundary(
                    key: _root,
                    child: ClipRect(child: child),
                  ),
                ),
              ),
            );
          },
        ),
        home: const CatalogApp(),
      ),
    ),
  );
}
