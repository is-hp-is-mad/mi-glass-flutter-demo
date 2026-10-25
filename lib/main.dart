import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import 'ci/capture_stub.dart' if (dart.library.io) 'ci/capture_io.dart';
import 'ci/driver.dart';
import 'demo/morph_menu.dart';
import 'demo/settings_page.dart';
import 'demo/sky.dart';
import 'demo/units.dart';
import 'hyper_glass.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  limitSkiaResourceCache();
  runApp(const DemoApp());
}

class DemoApp extends StatefulWidget {
  const DemoApp({super.key});

  @override
  State<DemoApp> createState() => _DemoAppState();
}

class _DemoAppState extends State<DemoApp> {
  ThemeMode _mode = ThemeMode.system;
  final _root = GlobalKey(); // whole-app boundary, used by the CI capture script

  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'HyperGlass',
    themeMode: _mode,
    theme: ThemeData(brightness: Brightness.light, fontFamily: 'MiSans'),
    darkTheme: ThemeData(brightness: Brightness.dark, fontFamily: 'MiSans'),
    builder: (context, child) => RepaintBoundary(key: _root, child: child),
    home: WeatherDemo(
      captureRoot: _root,
      onToggleDark: (dark) => setState(() => _mode = dark ? ThemeMode.dark : ThemeMode.light),
    ),
  );
}

class WeatherDemo extends StatefulWidget {
  const WeatherDemo({super.key, required this.onToggleDark, required this.captureRoot});

  final ValueChanged<bool> onToggleDark;
  final GlobalKey captureRoot;

  @override
  State<WeatherDemo> createState() => _WeatherDemoState();
}

// Unbounded controllers driven by springs so menu and dialog can overshoot like HyperOS.
class _WeatherDemoState extends State<WeatherDemo> with TickerProviderStateMixin implements DemoDriver {
  @override
  void initState() {
    super.initState();
    if (captureRequested) WidgetsBinding.instance.addPostFrameCallback((_) => runCapture(widget.captureRoot, this));
  }

  @override
  void setMenu(bool open) => _setMenu(open);
  @override
  void setDialog(bool open) => _setDialog(open);
  @override
  void setDark(bool dark) => widget.onToggleDark(dark);
  final _settings = GlobalKey<SettingsPageState>();
  @override
  void setSettings(bool open) =>
      open ? Navigator.of(context).push(SettingsPage.route(key: _settings)) : Navigator.of(context).maybePop();
  @override
  void settingsScroll(double offset) => _settings.currentState?.scrollTo(offset);
  @override
  void settingsOptions(bool open) => _settings.currentState?.setOptions(open);

  late final _menu = PopupMotion(this);
  late final _dialog = AnimationController.unbounded(vsync: this);
  bool _dialogOpen = false;

  static const _dialogSpring = SpringDescription(mass: 1, stiffness: 300, damping: 26);

  void _setMenu(bool open) {
    _menu.set(open);
    setState(() {});
  }

  void _setDialog(bool open) {
    _dialogOpen = open;
    _dialog.animateWith(SpringSimulation(_dialogSpring, _dialog.value, open ? 1 : 0, _dialog.velocity));
    setState(() {});
  }

  @override
  void dispose() {
    _menu.dispose();
    _dialog.dispose();
    super.dispose();
  }

  bool get _overlayActive => _menu.active || _dialogOpen || _dialog.value > 0.001;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      body: LayoutBuilder(
        builder: (context, c) {
          // Inner scene: sky + weather cards + the glass button. Outer scene: everything below the
          // overlays (inner scene and the dialog dim), so menu and dialog blur what is really under them.
          final page = HyperGlassScene(
            background: ValueListenableBuilder(
              valueListenable: TemperatureUnit.fahrenheit,
              builder: (_, _, _) => Sky(dark: dark, label: TemperatureUnit.format(23)),
            ),
            child: Stack(children: [_cards(), _button(c)]),
          );
          return AnimatedBuilder(
            animation: Listenable.merge([_menu.listenable, _dialog]),
            builder: (context, _) => HyperGlassScene(
              animate: _overlayActive,
              background: Stack(
                fit: StackFit.expand,
                children: [
                  page,
                  IgnorePointer(
                    child: ColoredBox(
                      color: Colors.black.withValues(alpha: (dark ? 0.45 : 0.3) * _dialog.value.clamp(0.0, 1.0)),
                    ),
                  ),
                ],
              ),
              child: Stack(children: [_menuLayer(c, dark), _dialogLayer(c, dark)]),
            ),
          );
        },
      ),
    );
  }

  Widget _cards() {
    const white = TextStyle(color: Colors.white);
    Widget card(String title, String body, {double height = 120}) => HyperGlass(
      borderRadius: 24,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: white.copyWith(fontSize: 13, color: Colors.white70)),
              const SizedBox(height: 8),
              Text(body, style: white.copyWith(fontSize: 20, fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
    return ValueListenableBuilder(
      valueListenable: TemperatureUnit.fahrenheit,
      builder: (_, _, _) => SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const SizedBox(height: 200),
                card('空气质量', '优 32'),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(child: card('湿度', '62%', height: 150)),
                    const SizedBox(width: 14),
                    Expanded(child: card('体感', TemperatureUnit.format(25), height: 150)),
                  ],
                ),
                const SizedBox(height: 14),
                card('15 日预报', '多云转晴  ${TemperatureUnit.format(18)} / ${TemperatureUnit.format(26)}', height: 220),
                const SizedBox(height: 14),
                card('日出日落', '06:12  ·  17:48'),
                const SizedBox(height: 400),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static const _buttonSize = Size(64, 64);
  // HyperOS puts such buttons at a screen edge / corner; the menu then bursts out of that corner.
  Rect _buttonRect(BoxConstraints c) => Rect.fromLTWH(
    c.maxWidth - 24 - _buttonSize.width,
    c.maxHeight - 24 - _buttonSize.height,
    _buttonSize.width,
    _buttonSize.height,
  );

  // The menu grows out of the button and replaces it, so the button hides as soon as the menu starts.
  Widget _button(BoxConstraints c) => Positioned.fromRect(
    rect: _buttonRect(c),
    child: AnimatedBuilder(
      animation: _menu.listenable,
      builder: (context, child) => IgnorePointer(
        ignoring: _menu.open,
        child: Opacity(opacity: 1 - menuSwap(_menu.geometry.value), child: child),
      ),
      child: GestureDetector(
        onTap: () => _setMenu(true),
        child: const HyperGlass(
          borderRadius: 32,
          child: Center(child: Icon(Icons.more_horiz, color: Colors.white, size: 28)),
        ),
      ),
    ),
  );

  // ---------------------------------------------------------------- popup menu (hyperos.popup_menu)
  Widget _menuLayer(BoxConstraints c, bool dark) {
    final items = [
      MorphMenuItem('降雨提醒', icon: Icons.umbrella_outlined, () {
        _setMenu(false);
        _setDialog(true);
      }),
      MorphMenuItem(dark ? '浅色模式' : '深色模式', icon: dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined, () {
        _setMenu(false);
        widget.onToggleDark(!dark);
      }),
      MorphMenuItem('分享天气', icon: Icons.share_outlined, () => _setMenu(false)),
      MorphMenuItem('设置', icon: Icons.settings_outlined, () {
        _setMenu(false);
        Navigator.of(context).push(SettingsPage.route());
      }),
    ];
    const itemH = 56.0, width = 220.0;
    final anchor = _buttonRect(c);
    final menu = menuRectFor(anchor, c.biggest, width, itemH * items.length + 16, growUp: true);
    return MorphMenu(
      motion: _menu,
      anchor: anchor,
      menu: menu,
      dark: dark,
      items: items,
      itemHeight: itemH,
      onDismiss: () => _setMenu(false),
    );
  }

  // ---------------------------------------------------------------- dialog (launcher uninstall style)
  Widget _dialogLayer(BoxConstraints c, bool dark) {
    final t = _dialog.value;
    if (t <= 0.001 && !_dialogOpen) return const SizedBox.shrink();
    final fg = dark ? Colors.white.withValues(alpha: 0.9) : Colors.black.withValues(alpha: 0.9);
    final sub = dark ? Colors.white.withValues(alpha: 0.6) : Colors.black.withValues(alpha: 0.6);
    final w = math.min(420.0, c.maxWidth - 24);
    const h = 236.0;
    final rect = Rect.fromLTWH((c.maxWidth - w) / 2, c.maxHeight - h - 12 + (1 - t) * (h + 24), w, h);
    Widget button(String label, bool primary, VoidCallback onTap) => Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          height: 50,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary
                ? const Color(0xff3482ff)
                : (dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.06)),
            borderRadius: BorderRadius.circular(25),
          ),
          child: Text(
            label,
            style: TextStyle(color: primary ? Colors.white : fg, fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ),
    );
    return Stack(
      children: [
        if (_dialogOpen) Positioned.fill(child: GestureDetector(onTap: () => _setDialog(false))),
        Positioned.fromRect(
          rect: rect,
          child: HyperBlendBlur(
            material: dark ? BlendMaterial.dialogDark : BlendMaterial.dialogLight,
            borderRadius: 32,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
              child: Column(
                children: [
                  Text(
                    '开启降雨提醒？',
                    style: TextStyle(color: fg, fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    '未来 2 小时内有小雨。开启后，降雨前 15 分钟会通知你带伞。',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: sub, fontSize: 15, height: 1.5),
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      button('取消', false, () => _setDialog(false)),
                      const SizedBox(width: 12),
                      button('开启', true, () => _setDialog(false)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
